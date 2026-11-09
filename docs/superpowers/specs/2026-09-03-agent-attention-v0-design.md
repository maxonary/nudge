# Agent Attention V0 Design

**Date:** 2026-09-03
**Status:** Approved for implementation

## Goal

Nudge becomes a small local attention surface for coding agents. A user can notice a finished agent turn, jump back to its host application, answer Claude Code questions, and approve or deny supported tool requests without leaving the current workflow.

V0 optimizes for a simple, trustworthy interaction rather than broad agent orchestration.

## Scope

### Claude Code

- Show a completion alert after a main-agent `Stop` event.
- Capture `AskUserQuestion` requests, including multiple sequential questions, single choice, multiple choice, and a freeform answer.
- Capture `PermissionRequest` approvals.
- Offer **Allow once**, **Allow for session** only when Claude supplies a compatible permission suggestion, and **Deny**.
- Hand an unresolved request back to Claude whenever Nudge is unavailable, busy, times out, or the user activates the origin host.

### Codex

- Show a completion alert after a `Stop` event.
- Capture `PermissionRequest` approvals with **Allow once** and **Deny**.
- Keep arbitrary questions in the native Codex UI because current stable hooks cannot return a tool result.
- Hand an unresolved approval back to Codex under the same fail-open conditions as Claude.

### Explicitly deferred

- AI summaries of agent output.
- Request history, queues, inboxes, or cross-device sync.
- Conductor-specific APIs or terminal extensions.
- Guaranteed exact terminal-tab navigation.
- Codex app-server ownership and Codex arbitrary-question responses.

## User experience

### Completion

The agent card identifies the agent and project and provides a large click target labelled honestly for the available jump target, such as **Jump to tab** when an exact target is known or **Zu Warp** when only app activation is possible.

The card collapses after three seconds while the pointer is outside Nudge. Entering Nudge cancels the current timer. Leaving starts a fresh three-second timer. Re-entering cancels that fresh timer, so an older timer can never close the card unexpectedly.

If the originating host is already frontmost, Nudge suppresses the visual completion card. The configured sound can still play. While an interactive request is active, a completion can play its sound but never replaces the request. Otherwise, the newest completion replaces the older completion.

### Questions

Only one interactive request can be active. A second request is immediately handed back to its native agent UI; it is never queued.

Questions are displayed one step at a time. Selector dots indicate the current step and allow navigation back to change an answer. Single-choice answers advance immediately. Multi-select and freeform answers use **Weiter**. The last step uses an explicit final submit action.

An unfinished question card uses the same three-second collapse behavior. Collapsing only hides it; the active request, current step, selections, and text drafts remain. Hovering Nudge reveals it again. While a text field is being edited, auto-collapse is disabled.

Clicking a text field temporarily activates Nudge and makes its panel key-capable. Submit, cancel, or handoff restores the previously active app when appropriate.

### Approvals

The approval card shows the source agent, project, tool name, and available command/reason context before action buttons. Claude conditionally shows **Für Session erlauben**. Codex only shows **Einmal erlauben** and **Ablehnen**.

### Handoff and jumping

If the user manually activates the request's host app, Nudge releases the hook without returning a decision. The native agent UI then owns the unresolved request. Jumping to the host performs the same handoff before activation so no stale request remains in Nudge.

App-level activation through `NSWorkspace` is the reliable fallback. Exact terminal-tab jumps are used only when a supported, already available host identifier is present. V0 does not install host-specific automation extensions.

## Architecture

### Domain state

`AgentAttentionCenter` is the single `@MainActor` source of truth. It owns:

- at most one `ActiveAgentRequest`;
- at most one visible `AgentCompletion`;
- current question index and all draft answers;
- hover/editing flags;
- a cancellable timer plus a monotonically increasing timer generation;
- origin-host metadata used for suppression, handoff, focus restoration, and jumping.

Interactive requests have priority over completions. Views call center actions; they do not mutate shared state directly. This also prevents duplicate sounds when Nudge is shown on multiple displays.

### Local bridge

The app hosts a user-local Unix-domain socket. The socket lives in a per-user runtime path and is created with owner-only permissions. Hook helpers send one newline-delimited JSON envelope and, for interactive events, keep the connection open until they receive a response or handoff.

The bridge is local-only and sends no agent content over the network. Its protocol is versioned. Unknown versions and malformed events are rejected fail-open.

Event types are:

- `completion`
- `question`
- `approval`

Responses are:

- `answered`
- `approvedOnce`
- `approvedForSession`
- `denied`
- `handoff`

The helper converts a bridge response into the exact hook-specific JSON expected by Claude Code or Codex. If it receives no actionable response, it exits successfully without hook output so the native UI continues.

### Connectors

Claude is installed as a user-scope local plugin containing additive `Stop`, `PreToolUse/AskUserQuestion`, and `PermissionRequest` command hooks. This avoids rewriting existing Claude hooks and is cleanly removable. Running Claude sessions require plugin reload or restart.

Codex is installed additively in user-scope `~/.codex/hooks.json`, preserving all existing definitions and removing only Nudge-owned definitions on disconnect. Codex requires the user to review/trust a new exact hook definition through `/hooks`; Settings communicates that state instead of claiming silent trust.

Both helpers are fail-open. Completion hooks return immediately. Interactive hooks wait only while Nudge owns the lease.

### Sandbox decision

Nudge is a notarized desktop utility rather than a Mac App Store app. V0 disables App Sandbox so the explicit **Connect** action can install user-wide Claude and Codex integrations. Hardened Runtime remains enabled. Connector writes are limited to their documented user configuration locations, existing data is preserved, and disconnect removes only Nudge-owned entries.

### App integration

The bridge starts once in `AppDelegate`. `NudgeNotchView` renders in this priority order:

1. active agent question or approval;
2. visible agent completion;
3. recent human Nudge ping;
4. normal send UI.

Agent events use the existing receive-sound preference but do not create a macOS backup notification, preventing duplicate visuals.

## Failure and concurrency rules

- Nudge unavailable: helper exits successfully with no decision.
- Interactive slot occupied: new request is handed off immediately.
- Origin host activated: active request is handed off and cleared.
- Socket/helper disconnect: matching active request is cleared without persistence.
- App restart: no pending request is restored.
- Duplicate completion: deduplicate by connector plus session/turn identity.
- Duplicate question: deduplicate by connector plus request/tool-use identity.
- Claude questions with duplicate question text are handed off because Claude answers are keyed by exact question text.
- Another security hook can override a Nudge allow decision; Nudge does not claim otherwise.

## Test strategy

A small Swift Package compiles the Foundation-only domain and connector merge logic under the available Command Line Tools. Tests cover slot arbitration, completion priority, question drafts/navigation, timer generations, editing locks, submit/handoff, and additive configuration changes.

Python helper tests use a temporary Unix socket and fixture payloads to verify Claude and Codex output JSON plus fail-open behavior.

The app source is syntax-parsed locally. A complete Xcode build and whole-app macOS UI verification require a machine with full Xcode; that limitation must be reported rather than inferred as passing. In the Command Line Tools environment, the real Agent Attention view is additionally exercised in a minimal AppKit/SwiftUI render harness.

## Primary references

- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code plugins](https://code.claude.com/docs/en/plugins-reference)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Codex app server](https://developers.openai.com/codex/app-server)
