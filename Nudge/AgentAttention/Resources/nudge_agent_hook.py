#!/usr/bin/env python3
"""Fail-open local bridge for Claude Code and Codex lifecycle hooks."""

import copy
import hashlib
import json
import os
import socket
import stat
import sys
import uuid


PROTOCOL_VERSION = 1
MAX_LINE_BYTES = 1024 * 1024
SOURCES = {"claude": "claudeCode", "codex": "codex"}
HOSTS = {
    "WarpTerminal": ("Warp", "dev.warp.Warp-Stable"),
    "Apple_Terminal": ("Terminal", "com.apple.Terminal"),
    "iTerm.app": ("iTerm", "com.googlecode.iterm2"),
    "vscode": ("Visual Studio Code", "com.microsoft.VSCode"),
}


def host_from_environment(environ):
    term_program = environ.get("TERM_PROGRAM") or "Unknown terminal"
    app_name, bundle_id = HOSTS.get(term_program, (term_program, None))
    return {
        "appName": app_name,
        "bundleID": bundle_id,
        "terminalSessionID": (
            environ.get("TERM_SESSION_ID") or environ.get("ITERM_SESSION_ID")
        ),
    }


def normalize_event(source, hook_input, environ=None):
    if source not in SOURCES or not isinstance(hook_input, dict):
        return None

    environment = os.environ if environ is None else environ
    agent_source = SOURCES[source]
    cwd = hook_input.get("cwd")
    if not isinstance(cwd, str):
        cwd = ""

    event_name = hook_input.get("hook_event_name")
    payload = None
    event_type = None

    if event_name == "Stop":
        session_id = hook_input.get("session_id")
        turn_key = "prompt_id" if source == "claude" else "turn_id"
        turn_id = hook_input.get(turn_key)
        if not isinstance(session_id, str):
            return None
        if source == "claude" and (not isinstance(turn_id, str) or not turn_id):
            transcript_path = hook_input.get("transcript_path")
            last_message = hook_input.get("last_assistant_message")
            legacy_material = (
                (transcript_path if isinstance(transcript_path, str) else "")
                + (last_message if isinstance(last_message, str) else "")
            )
            turn_id = hashlib.sha256(legacy_material.encode("utf-8")).hexdigest()[:12]
        elif not isinstance(turn_id, str):
            return None
        payload = {
            "id": f"{agent_source}:{session_id}:{turn_id}",
            "source": agent_source,
            "context": cwd,
            "title": "Claude Code finished" if source == "claude" else "Codex finished",
        }
        message = hook_input.get("last_assistant_message")
        if isinstance(message, str):
            payload["message"] = message
        event_type = "completion"

    elif (
        source == "claude"
        and event_name == "PreToolUse"
        and hook_input.get("tool_name") == "AskUserQuestion"
    ):
        tool_use_id = hook_input.get("tool_use_id")
        tool_input = hook_input.get("tool_input")
        questions = tool_input.get("questions") if isinstance(tool_input, dict) else None
        if not isinstance(tool_use_id, str) or not isinstance(questions, list) or not questions:
            return None

        prompts = [question.get("question") for question in questions if isinstance(question, dict)]
        if (
            len(prompts) != len(questions)
            or any(not isinstance(prompt, str) for prompt in prompts)
            or len(set(prompts)) != len(prompts)
        ):
            return None

        normalized_questions = []
        for index, question in enumerate(questions):
            raw_options = question.get("options")
            if not isinstance(raw_options, list):
                raw_options = []
            choices = []
            for option in raw_options:
                if not isinstance(option, dict) or not isinstance(option.get("label"), str):
                    continue
                choices.append({
                    "label": option["label"],
                    "description": option.get("description")
                    if isinstance(option.get("description"), str)
                    else "",
                })
            normalized_questions.append({
                "id": f"{tool_use_id}:{index}",
                "prompt": question["question"],
                "choices": choices,
                "multiSelect": bool(question.get("multiSelect", False)),
                "allowsFreeform": True,
            })

        first_header = questions[0].get("header")
        payload = {
            "id": tool_use_id,
            "header": first_header if isinstance(first_header, str) else "Question",
            "questions": normalized_questions,
        }
        event_type = "question"

    elif event_name == "PermissionRequest":
        tool_name = hook_input.get("tool_name")
        if not isinstance(tool_name, str):
            return None
        tool_input = hook_input.get("tool_input")
        if not isinstance(tool_input, dict):
            tool_input = {}
        request_id = hook_input.get("tool_use_id")
        if not isinstance(request_id, str) or not request_id:
            request_id = str(uuid.uuid4())
        description = tool_input.get("description")
        command = tool_input.get("command")
        if not isinstance(description, str):
            description = None
        if not isinstance(command, str):
            command = None

        payload = {
            "id": request_id,
            "source": agent_source,
            "toolName": tool_name,
            "detail": description or command or tool_name,
            "cwd": cwd,
            "allowsClaudeSessionRule": (
                source == "claude" and _first_compatible_suggestion(hook_input) is not None
            ),
        }
        if command is not None:
            payload["command"] = command
        event_type = "approval"

    if event_type is None:
        return None

    project = os.path.basename(os.path.normpath(cwd)) if cwd else None
    envelope = {
        "protocolVersion": PROTOCOL_VERSION,
        "source": agent_source,
        "cwd": cwd,
        "host": host_from_environment(environment),
        "event": {"type": event_type, "payload": payload},
    }
    if project:
        envelope["project"] = project
    return envelope


def output_for_response(source, hook_input, response):
    if source not in SOURCES or not isinstance(response, dict):
        return {}
    kind = response.get("kind")
    if kind == "handoff":
        return {}

    event_name = hook_input.get("hook_event_name") if isinstance(hook_input, dict) else None
    if (
        source == "claude"
        and event_name == "PreToolUse"
        and hook_input.get("tool_name") == "AskUserQuestion"
        and kind == "answered"
        and isinstance(response.get("answers"), dict)
    ):
        tool_input = hook_input.get("tool_input")
        questions = tool_input.get("questions") if isinstance(tool_input, dict) else None
        if not isinstance(questions, list):
            return {}
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": {
                    "questions": questions,
                    "answers": response["answers"],
                },
            }
        }

    if event_name != "PermissionRequest":
        return {}

    decision = None
    if kind == "approvedOnce":
        decision = {"behavior": "allow"}
    elif kind == "approvedForSession" and source == "claude":
        suggestion = _first_compatible_suggestion(hook_input)
        if suggestion is None:
            return {}
        session_suggestion = copy.deepcopy(suggestion)
        session_suggestion["destination"] = "session"
        decision = {
            "behavior": "allow",
            "updatedPermissions": [session_suggestion],
        }
    elif kind == "denied":
        decision = {"behavior": "deny", "message": "Denied in Nudge."}
        if source == "claude":
            decision["interrupt"] = False
    if decision is None:
        return {}
    return {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": decision,
        }
    }


def _first_compatible_suggestion(hook_input):
    suggestions = hook_input.get("permission_suggestions")
    if not isinstance(suggestions, list):
        return None
    for suggestion in suggestions:
        if (
            isinstance(suggestion, dict)
            and suggestion.get("type") in {"addRules", "replaceRules"}
            and suggestion.get("behavior") == "allow"
            and isinstance(suggestion.get("rules"), list)
            and suggestion["rules"]
        ):
            return suggestion
    return None


def _socket_path(environ):
    path = environ.get("NUDGE_AGENT_SOCKET_PATH") or (
        f"/tmp/com.nudge.max.agent-{os.getuid()}/bridge.sock"
    )
    if not isinstance(path, str) or not os.path.isabs(path) or os.path.normpath(path) != path:
        return None

    try:
        parent_metadata = os.lstat(os.path.dirname(path))
        socket_metadata = os.lstat(path)
    except OSError:
        return None

    owner = os.geteuid()
    if (
        not stat.S_ISDIR(parent_metadata.st_mode)
        or parent_metadata.st_uid != owner
        or stat.S_IMODE(parent_metadata.st_mode) != 0o700
    ):
        return None
    if (
        not stat.S_ISSOCK(socket_metadata.st_mode)
        or socket_metadata.st_uid != owner
        or stat.S_IMODE(socket_metadata.st_mode) != 0o600
    ):
        return None
    return path


def _read_response(connection):
    data = bytearray()
    while True:
        chunk = connection.recv(min(65536, MAX_LINE_BYTES + 1 - len(data)))
        if not chunk:
            return None
        newline = chunk.find(b"\n")
        if newline >= 0:
            data.extend(chunk[:newline])
            break
        data.extend(chunk)
        if len(data) > MAX_LINE_BYTES:
            return None
    if len(data) > MAX_LINE_BYTES:
        return None
    try:
        response = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return response if isinstance(response, dict) else None


def run(source, hook_input, environ=None):
    environment = os.environ if environ is None else environ
    envelope = normalize_event(source, hook_input, environment)
    if envelope is None:
        return {}

    wire = json.dumps(envelope, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    socket_path = _socket_path(environment)
    if socket_path is None:
        return {}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.connect(socket_path)
        connection.sendall(wire)
        if envelope["event"]["type"] == "completion":
            return {}
        response = _read_response(connection)
    if response is None:
        return {}
    return output_for_response(source, hook_input, response)


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    output = {}
    try:
        if len(arguments) == 1 and arguments[0] in SOURCES:
            hook_input = json.load(sys.stdin)
            output = run(arguments[0], hook_input)
    except Exception:
        output = {}
    try:
        sys.stdout.write(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
