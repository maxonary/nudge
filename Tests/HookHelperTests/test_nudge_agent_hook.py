import importlib.util
import json
import os
from pathlib import Path
import socket
import stat
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "Nudge" / "AgentAttention" / "Resources" / "nudge_agent_hook.py"


def claude_stop_fixture():
    return {
        "session_id": "claude-session",
        "prompt_id": "prompt-7",
        "cwd": "/work/atlas",
        "hook_event_name": "Stop",
        "last_assistant_message": "Implemented the bridge.",
    }


def claude_stop_without_prompt_id_fixture():
    return {
        "session_id": "legacy-claude-session",
        "transcript_path": "/Users/max/.claude/projects/atlas/session.jsonl",
        "cwd": "/work/atlas",
        "hook_event_name": "Stop",
        "stop_hook_active": False,
        "last_assistant_message": "Legacy Claude completion.",
    }


def codex_stop_fixture():
    return {
        "session_id": "codex-session",
        "turn_id": "turn-9",
        "cwd": "/work/atlas",
        "hook_event_name": "Stop",
        "last_assistant_message": "Tests pass.",
    }


def claude_question_fixture():
    return {
        "session_id": "claude-session",
        "cwd": "/work/atlas",
        "hook_event_name": "PreToolUse",
        "tool_name": "AskUserQuestion",
        "tool_use_id": "toolu-question",
        "tool_input": {
            "questions": [
                {
                    "question": "Which release track?",
                    "header": "Release",
                    "options": [
                        {"label": "Stable", "description": "Ship the proven build"},
                        {"label": "Beta", "description": "Ship the preview build"},
                    ],
                    "multiSelect": False,
                },
                {
                    "question": "Which checks?",
                    "header": "Checks",
                    "options": [{"label": "Tests", "description": "Run tests"}],
                    "multiSelect": True,
                },
            ]
        },
    }


def claude_approval_fixture(with_suggestion=True):
    event = {
        "session_id": "claude-session",
        "cwd": "/work/atlas",
        "hook_event_name": "PermissionRequest",
        "tool_name": "Bash",
        "tool_input": {
            "command": "npm test",
            "description": "Run the test suite",
        },
    }
    if with_suggestion:
        event["permission_suggestions"] = [
            {
                "type": "addRules",
                "rules": [{"toolName": "Bash", "ruleContent": "npm test"}],
                "behavior": "allow",
                "destination": "localSettings",
            },
            {
                "type": "addRules",
                "rules": [{"toolName": "Bash"}],
                "behavior": "deny",
                "destination": "userSettings",
            },
        ]
    return event


def codex_approval_fixture():
    return {
        "session_id": "codex-session",
        "turn_id": "turn-9",
        "cwd": "/work/atlas",
        "hook_event_name": "PermissionRequest",
        "tool_name": "Bash",
        "tool_use_id": "call-3",
        "tool_input": {
            "command": "git push",
            "description": "Publish the branch",
        },
    }


class HookHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("nudge_agent_hook", HELPER)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_claude_stop_normalizes_to_completion(self):
        envelope = self.module.normalize_event("claude", claude_stop_fixture(), {})

        self.assertEqual(envelope["protocolVersion"], 1)
        self.assertEqual(envelope["source"], "claudeCode")
        self.assertEqual(envelope["cwd"], "/work/atlas")
        self.assertEqual(envelope["project"], "atlas")
        self.assertEqual(envelope["event"], {
            "type": "completion",
            "payload": {
                "id": "claudeCode:claude-session:prompt-7",
                "source": "claudeCode",
                "context": "/work/atlas",
                "title": "Claude Code finished",
                "message": "Implemented the bridge.",
            },
        })

    def test_claude_stop_without_prompt_id_uses_deterministic_legacy_id(self):
        event = claude_stop_without_prompt_id_fixture()

        first = self.module.normalize_event("claude", event, {})
        second = self.module.normalize_event("claude", event, {})

        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertEqual(
            first["event"]["payload"]["id"],
            "claudeCode:legacy-claude-session:9981e90f59ef",
        )
        self.assertEqual(second["event"]["payload"]["id"], first["event"]["payload"]["id"])

    def test_codex_stop_normalizes_to_completion(self):
        envelope = self.module.normalize_event("codex", codex_stop_fixture(), {})

        self.assertEqual(envelope["source"], "codex")
        self.assertEqual(envelope["event"], {
            "type": "completion",
            "payload": {
                "id": "codex:codex-session:turn-9",
                "source": "codex",
                "context": "/work/atlas",
                "title": "Codex finished",
                "message": "Tests pass.",
            },
        })

    def test_claude_question_preserves_prompt_choices_and_flags(self):
        envelope = self.module.normalize_event("claude", claude_question_fixture(), {})

        self.assertEqual(envelope["event"], {
            "type": "question",
            "payload": {
                "id": "toolu-question",
                "header": "Release",
                "questions": [
                    {
                        "id": "toolu-question:0",
                        "prompt": "Which release track?",
                        "choices": [
                            {"label": "Stable", "description": "Ship the proven build"},
                            {"label": "Beta", "description": "Ship the preview build"},
                        ],
                        "multiSelect": False,
                        "allowsFreeform": True,
                    },
                    {
                        "id": "toolu-question:1",
                        "prompt": "Which checks?",
                        "choices": [{"label": "Tests", "description": "Run tests"}],
                        "multiSelect": True,
                        "allowsFreeform": True,
                    },
                ],
            },
        })

    def test_duplicate_claude_question_prompts_handoff_before_connecting(self):
        event = claude_question_fixture()
        event["tool_input"]["questions"][1]["question"] = "Which release track?"

        self.assertIsNone(self.module.normalize_event("claude", event, {}))

    def test_only_claude_ask_user_question_is_normalized(self):
        event = claude_question_fixture()
        event["tool_name"] = "Bash"

        self.assertIsNone(self.module.normalize_event("claude", event, {}))

    def test_claude_approval_contains_context_and_session_capability(self):
        envelope = self.module.normalize_event("claude", claude_approval_fixture(), {})
        approval = envelope["event"]["payload"]

        self.assertEqual(envelope["event"]["type"], "approval")
        self.assertEqual(approval["source"], "claudeCode")
        self.assertEqual(approval["toolName"], "Bash")
        self.assertEqual(approval["detail"], "Run the test suite")
        self.assertEqual(approval["command"], "npm test")
        self.assertEqual(approval["cwd"], "/work/atlas")
        self.assertTrue(approval["allowsClaudeSessionRule"])
        self.assertRegex(approval["id"], r"^[0-9a-f-]{36}$")

    def test_codex_approval_uses_tool_id_and_never_allows_session_rule(self):
        approval = self.module.normalize_event(
            "codex", codex_approval_fixture(), {}
        )["event"]["payload"]

        self.assertEqual(approval, {
            "id": "call-3",
            "source": "codex",
            "toolName": "Bash",
            "detail": "Publish the branch",
            "command": "git push",
            "cwd": "/work/atlas",
            "allowsClaudeSessionRule": False,
        })

    def test_host_mapping_and_terminal_session_ids(self):
        cases = [
            ("WarpTerminal", "Warp", "dev.warp.Warp-Stable"),
            ("Apple_Terminal", "Terminal", "com.apple.Terminal"),
            ("iTerm.app", "iTerm", "com.googlecode.iterm2"),
            ("vscode", "Visual Studio Code", "com.microsoft.VSCode"),
            ("Ghostty", "Ghostty", None),
        ]

        for term_program, app_name, bundle_id in cases:
            with self.subTest(term_program=term_program):
                host = self.module.host_from_environment({
                    "TERM_PROGRAM": term_program,
                    "TERM_SESSION_ID": "term-session",
                    "ITERM_SESSION_ID": "iterm-session",
                })
                self.assertEqual(host, {
                    "appName": app_name,
                    "bundleID": bundle_id,
                    "terminalSessionID": "term-session",
                })

        host = self.module.host_from_environment({
            "TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "fallback-session"
        })
        self.assertEqual(host["terminalSessionID"], "fallback-session")

    def test_host_without_known_term_program_uses_launching_app_bundle_id(self):
        conductor = self.module.host_from_environment({
            "__CFBundleIdentifier": "com.conductor.app",
        })
        self.assertEqual(conductor, {
            "appName": "Conductor",
            "bundleID": "com.conductor.app",
            "terminalSessionID": None,
        })

        ghostty = self.module.host_from_environment({
            "TERM_PROGRAM": "ghostty",
            "__CFBundleIdentifier": "com.mitchellh.ghostty",
        })
        self.assertEqual(ghostty["appName"], "ghostty")
        self.assertEqual(ghostty["bundleID"], "com.mitchellh.ghostty")

        known = self.module.host_from_environment({
            "TERM_PROGRAM": "vscode",
            "__CFBundleIdentifier": "com.microsoft.VSCode",
        })
        self.assertEqual(known["appName"], "Visual Studio Code")
        self.assertEqual(known["bundleID"], "com.microsoft.VSCode")

    def test_claude_question_answer_preserves_questions(self):
        event = claude_question_fixture()
        output = self.module.output_for_response("claude", event, {
            "kind": "answered", "answers": {"Which release track?": "Stable"}
        })

        specific = output["hookSpecificOutput"]
        self.assertEqual(specific["hookEventName"], "PreToolUse")
        self.assertEqual(specific["permissionDecision"], "allow")
        self.assertEqual(specific["updatedInput"]["questions"], event["tool_input"]["questions"])
        self.assertEqual(specific["updatedInput"]["answers"], {"Which release track?": "Stable"})

    def test_claude_approval_once_uses_official_allow_shape(self):
        output = self.module.output_for_response(
            "claude", claude_approval_fixture(), {"kind": "approvedOnce"}
        )

        self.assertEqual(output, {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        })

    def test_claude_session_approval_copies_first_allow_suggestion_to_session(self):
        event = claude_approval_fixture()
        output = self.module.output_for_response(
            "claude", event, {"kind": "approvedForSession"}
        )

        self.assertEqual(output, {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "allow",
                    "updatedPermissions": [{
                        "type": "addRules",
                        "rules": [{"toolName": "Bash", "ruleContent": "npm test"}],
                        "behavior": "allow",
                        "destination": "session",
                    }],
                },
            }
        })
        self.assertEqual(event["permission_suggestions"][0]["destination"], "localSettings")

    def test_claude_session_approval_without_compatible_rule_hands_off(self):
        event = claude_approval_fixture(with_suggestion=False)

        self.assertEqual(
            self.module.output_for_response("claude", event, {"kind": "approvedForSession"}),
            {},
        )

    def test_claude_denial_is_non_interrupting_and_has_message(self):
        output = self.module.output_for_response(
            "claude", claude_approval_fixture(), {"kind": "denied"}
        )

        decision = output["hookSpecificOutput"]["decision"]
        self.assertEqual(decision["behavior"], "deny")
        self.assertEqual(decision["interrupt"], False)
        self.assertTrue(decision["message"])

    def test_codex_approval_and_denial_use_only_supported_fields(self):
        approved = self.module.output_for_response(
            "codex", codex_approval_fixture(), {"kind": "approvedOnce"}
        )
        denied = self.module.output_for_response(
            "codex", codex_approval_fixture(), {"kind": "denied"}
        )

        self.assertEqual(approved, {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        })
        self.assertEqual(denied["hookSpecificOutput"]["decision"]["behavior"], "deny")
        self.assertTrue(denied["hookSpecificOutput"]["decision"]["message"])
        self.assertNotIn("interrupt", denied["hookSpecificOutput"]["decision"])

    def test_codex_session_approval_and_handoff_return_empty_object(self):
        event = codex_approval_fixture()

        self.assertEqual(
            self.module.output_for_response("codex", event, {"kind": "approvedForSession"}),
            {},
        )
        self.assertEqual(
            self.module.output_for_response("codex", event, {"kind": "handoff"}),
            {},
        )

    def test_missing_socket_returns_empty_object_and_exit_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_helper(
                "claude",
                claude_approval_fixture(),
                Path(directory) / "missing.sock",
            )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), {})
        self.assertEqual(result.stderr, "")

    def test_socket_path_requires_private_parent_and_owner_only_socket(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "bridge.sock"
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(str(socket_path))
                socket_path.chmod(0o600)
                environment = {"NUDGE_AGENT_SOCKET_PATH": str(socket_path)}

                self.assertEqual(self.module._socket_path(environment), str(socket_path))

                Path(directory).chmod(0o755)
                self.assertIsNone(self.module._socket_path(environment))
                Path(directory).chmod(0o700)

                socket_path.chmod(0o660)
                self.assertIsNone(self.module._socket_path(environment))

    def test_socket_path_rejects_relative_and_symlinked_override(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime_directory = Path(directory) / "runtime"
            runtime_directory.mkdir(mode=0o700)
            socket_path = runtime_directory / "bridge.sock"
            socket_alias = runtime_directory / "bridge-alias.sock"
            directory_alias = Path(directory) / "runtime-alias"
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(str(socket_path))
                socket_path.chmod(0o600)
                socket_alias.symlink_to(socket_path)
                directory_alias.symlink_to(runtime_directory, target_is_directory=True)

                self.assertIsNone(self.module._socket_path({
                    "NUDGE_AGENT_SOCKET_PATH": "relative.sock"
                }))
                self.assertIsNone(self.module._socket_path({
                    "NUDGE_AGENT_SOCKET_PATH": str(socket_alias)
                }))
                self.assertIsNone(self.module._socket_path({
                    "NUDGE_AGENT_SOCKET_PATH": str(directory_alias / "bridge.sock")
                }))

    def test_completion_sends_once_and_does_not_wait_for_response(self):
        with tempfile.TemporaryDirectory() as directory:
            socket_path = Path(directory) / "bridge.sock"
            received = []
            release = threading.Event()

            def server():
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                    listener.bind(str(socket_path))
                    socket_path.chmod(0o600)
                    listener.listen(1)
                    with listener.accept()[0] as connection:
                        received.append(self.read_line(connection))
                        release.wait(2)

            thread = threading.Thread(target=server)
            thread.start()
            self.wait_for_path(socket_path)
            started = time.monotonic()
            result = self.run_helper("codex", codex_stop_fixture(), socket_path)
            elapsed = time.monotonic() - started
            release.set()
            thread.join(3)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), {})
        self.assertLess(elapsed, 1)
        self.assertEqual(len(received), 1)
        self.assertEqual(json.loads(received[0])["event"]["type"], "completion")

    def test_protocol_error_disconnect_and_busy_handoff_fail_open(self):
        replies = [b"not json\n", b"", b'{"kind":"handoff"}\n']
        for reply in replies:
            with self.subTest(reply=reply):
                with tempfile.TemporaryDirectory() as directory:
                    socket_path = Path(directory) / "bridge.sock"

                    def server():
                        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                            listener.bind(str(socket_path))
                            socket_path.chmod(0o600)
                            listener.listen(1)
                            with listener.accept()[0] as connection:
                                self.read_line(connection)
                                if reply:
                                    connection.sendall(reply)

                    thread = threading.Thread(target=server)
                    thread.start()
                    self.wait_for_path(socket_path)
                    result = self.run_helper("codex", codex_approval_fixture(), socket_path)
                    thread.join(3)

                self.assertEqual(result.returncode, 0)
                self.assertEqual(json.loads(result.stdout), {})

    @staticmethod
    def read_line(connection):
        chunks = []
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                return b"".join(chunks).decode()
            chunks.append(chunk)
            if b"\n" in chunk:
                return b"".join(chunks).split(b"\n", 1)[0].decode()

    @staticmethod
    def wait_for_path(path):
        deadline = time.monotonic() + 2
        while True:
            try:
                metadata = path.lstat()
                if stat.S_ISSOCK(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o600:
                    return
            except FileNotFoundError:
                pass
            if time.monotonic() >= deadline:
                raise AssertionError(f"secure socket was not created: {path}")
            time.sleep(0.005)

    @staticmethod
    def run_helper(source, event, socket_path):
        environment = os.environ.copy()
        environment["NUDGE_AGENT_SOCKET_PATH"] = str(socket_path)
        return subprocess.run(
            ["python3", str(HELPER), source],
            input=json.dumps(event),
            text=True,
            capture_output=True,
            timeout=3,
            env=environment,
        )


if __name__ == "__main__":
    unittest.main()
