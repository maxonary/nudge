# Agent Attention V0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local Nudge surface for Claude Code and Codex completion alerts, supported questions, approvals, and honest host jumping.

**Architecture:** A Foundation-only reducer owns one interactive lease and presentation state; a main-actor center adds timing and AppKit effects. Claude/Codex hook helpers normalize official hook payloads over an owner-only Unix-domain socket, while reversible connectors install only Nudge-owned configuration.

**Tech Stack:** Swift 5/SwiftUI/AppKit on macOS 14, Swift Package Manager test harness, POSIX Unix sockets, Python 3 standard library hook helper, Claude Code user plugin, Codex user hooks.

**Spec:** `docs/superpowers/specs/2026-09-03-agent-attention-v0-design.md`

## Global Constraints

- Keep exactly one active interactive request; never persist or queue requests.
- Collapse after exactly three seconds outside hover; every hover entry invalidates every older timer.
- Keep drafts and the current question step while an unfinished request is collapsed.
- Disable auto-collapse while editing text.
- Keep Codex arbitrary questions native in V0.
- Use only local IPC; do not send agent content over the network.
- Preserve existing Claude and Codex configuration and remove only Nudge-owned configuration on disconnect.
- Reuse `nudgePlaySoundOnReceive`; never post a backup macOS notification for agent events.
- Keep Hardened Runtime enabled; disable App Sandbox for explicit user-wide connector installation.

## File map

- `Package.swift`: CLI-testable core target; not an app dependency.
- `Nudge/AgentAttention/Core/AgentAttentionModels.swift`: Codable bridge/domain value types.
- `Nudge/AgentAttention/Core/AgentAttentionState.swift`: deterministic reducer, drafts, arbitration, and timer generations.
- `Nudge/AgentAttention/Core/ConnectorConfiguration.swift`: Foundation-only additive Codex JSON transforms.
- `Nudge/AgentAttention/Core/ConnectorLifecycle.swift`: persisted retry intent plus safe helper/plugin integrity and path checks.
- `Nudge/AgentAttention/AgentAttentionCenter.swift`: observable runtime state, timers, callbacks, sound, host suppression/handoff.
- `Nudge/AgentAttention/AgentBridgeServer.swift`: owner-only Unix socket and request sessions.
- `Nudge/AgentAttention/AgentConnectorManager.swift`: connector status, stable helper installation, additive connect/disconnect.
- `Nudge/AgentAttention/AgentAttentionView.swift`: compact completion/question/approval UI.
- `Nudge/AgentAttention/AgentPanelFocusController.swift`: temporary panel activation and previous-app restoration.
- `Nudge/AgentAttention/Resources/nudge_agent_hook.py`: Claude/Codex hook normalization and output mapping.
- `Tests/NudgeAgentCoreTests/AgentAttentionStateTests.swift`: reducer contract tests.
- `Tests/NudgeAgentCoreTests/ConnectorConfigurationTests.swift`: additive Codex configuration tests.
- `Tests/NudgeAgentCoreTests/ConnectorLifecycleTests.swift`: connector retry, integrity, and managed-path tests.
- `Tests/HookHelperTests/test_nudge_agent_hook.py`: helper mapping and fail-open tests.
- `Nudge/ContentView.swift`: presentation lifecycle and hover forwarding.
- `Nudge/Nudge/NudgeNotchView.swift`: content priority routing.
- `Nudge/NudgeApp.swift`: bridge lifecycle, host activation observer, and shared state injection.
- `Nudge/components/Notch/NudgeSkyLightWindow.swift`: opt-in key focus.
- `Nudge/components/Settings/SettingsView.swift`: Claude/Codex connect controls and preview actions.
- `Nudge/Nudge.entitlements`: remove App Sandbox only.
- `Nudge.xcodeproj/project.pbxproj`: add Swift sources and helper resource to the app target.

---

### Task 1: Deterministic attention core

**Files:**
- Create: `Package.swift`
- Create: `Nudge/AgentAttention/Core/AgentAttentionModels.swift`
- Create: `Nudge/AgentAttention/Core/AgentAttentionState.swift`
- Create: `Tests/NudgeAgentCoreTests/AgentAttentionStateTests.swift`

**Interfaces:**
- Produces: `AgentEventEnvelope`, `AgentCompletion`, `AgentQuestionSet`, `AgentApproval`, `ActiveAgentRequest`, `AgentAttentionState`.
- Produces actions: `claim(_:) -> Bool`, `receiveCompletion(_:) -> CompletionDisposition`, `answer(_:at:)`, `move(to:)`, `armCollapse() -> Int?`, `cancelCollapse()`, `collapse(generation:) -> Bool`, `clearRequest(id:)`.

- [x] **Step 1: Write reducer tests before production types exist**

```swift
func testSecondInteractiveRequestIsRejectedWithoutQueueing() {
    var state = AgentAttentionState()
    XCTAssertTrue(state.claim(.question(.fixture(id: "first"))))
    XCTAssertFalse(state.claim(.approval(.fixture(id: "second"))))
    XCTAssertEqual(state.activeRequest?.id, "first")
}

func testOldCollapseGenerationCannotHideAfterRehover() {
    var state = AgentAttentionState()
    state.visible = true
    let old = state.armCollapse()!
    state.cancelCollapse()
    let fresh = state.armCollapse()!
    XCTAssertFalse(state.collapse(generation: old))
    XCTAssertTrue(state.collapse(generation: fresh))
}

func testQuestionDraftSurvivesCollapseAndBackNavigation() {
    var state = AgentAttentionState(activeRequest: .question(.twoQuestionFixture))
    state.answer(.single("A"), at: 0)
    state.move(to: 1)
    state.answer(.text("because"), at: 1)
    _ = state.collapse(generation: state.armCollapse()!)
    state.move(to: 0)
    XCTAssertEqual(state.drafts[0], .single("A"))
    XCTAssertEqual(state.drafts[1], .text("because"))
}
```

- [x] **Step 2: Run the focused tests and record the expected red state**

Run: `swift test --filter AgentAttentionStateTests`

Expected: FAIL because `AgentAttentionState` and the domain types do not exist.

- [x] **Step 3: Implement the smallest Codable models and reducer**

```swift
public mutating func armCollapse() -> Int? {
    guard !isHovering, !isEditing, visible else { return nil }
    collapseGeneration += 1
    return collapseGeneration
}

public mutating func cancelCollapse() {
    collapseGeneration += 1
}

public mutating func collapse(generation: Int) -> Bool {
    guard generation == collapseGeneration, !isHovering, !isEditing else { return false }
    visible = false
    return true
}
```

Implement `claim` as a compare-with-nil lease, preserve question drafts on `visible = false`, discard visual completions while a request exists, and replace older completions otherwise.

- [x] **Step 4: Run all Swift core tests**

Run: `swift test`

Expected: PASS.

- [x] **Step 5: Commit the core**

```bash
git add Package.swift Nudge/AgentAttention/Core Tests/NudgeAgentCoreTests
git commit -m "feat: add agent attention state machine"
```

### Task 2: Hook protocol and fail-open helper

**Files:**
- Create: `Nudge/AgentAttention/Resources/nudge_agent_hook.py`
- Create: `Tests/HookHelperTests/test_nudge_agent_hook.py`
- Create: `Nudge/AgentAttention/AgentBridgeServer.swift`

**Interfaces:**
- Consumes: Codable `AgentEventEnvelope` from Task 1.
- Produces: `AgentBridgeServer.start(onEvent:)`, `stop()`, and one-shot `AgentBridgeSession.respond(_:)` / `handoff()`.
- Wire format: one UTF-8 JSON object plus newline in each direction, `protocolVersion == 1`.

- [x] **Step 1: Write Python mapping tests first**

```python
def test_claude_question_answer_preserves_questions(module):
    event = claude_question_fixture()
    output = module.output_for_response(event, {
        "kind": "answered", "answers": {"Which?": "A"}
    })
    assert output["hookSpecificOutput"]["updatedInput"]["questions"] == event["tool_input"]["questions"]
    assert output["hookSpecificOutput"]["updatedInput"]["answers"] == {"Which?": "A"}

def test_codex_handoff_returns_empty_object(module):
    assert module.output_for_response(codex_approval_fixture(), {"kind": "handoff"}) == {}
```

- [x] **Step 2: Run the helper tests and verify red**

Run: `python3 -m unittest discover -s Tests/HookHelperTests -v`

Expected: FAIL because `nudge_agent_hook.py` does not exist.

- [x] **Step 3: Implement normalization and response mapping**

```python
def output_for_response(source, hook_input, response):
    kind = response.get("kind")
    if kind == "handoff":
        return {}
    if source == "claude" and hook_input["hook_event_name"] == "PreToolUse":
        return {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {
                "questions": hook_input["tool_input"]["questions"],
                "answers": response["answers"],
            },
        }}
```

Map Claude session approval only when an original `permission_suggestions` rule is present. Map Codex only to allow/deny. On missing socket, protocol error, busy handoff, or disconnect, print `{}` and exit `0`. Completion sends once and never waits.

The executable contract is `nudge_agent_hook.py <claude|codex>`. It reads exactly one hook JSON object from stdin and always exits `0`. Normalize official events as follows:

- Claude `Stop` and Codex `Stop` → `completion`; dedupe ID is source + `session_id` + (`prompt_id` or `turn_id`), title identifies the source, and `last_assistant_message` is optional context.
- Claude `PreToolUse` is accepted only for `tool_name == "AskUserQuestion"`; use `tool_use_id`, preserve exact prompt text, option label/description and `multiSelect`, enable freeform, and hand off without connecting when prompts are duplicated.
- Claude/Codex `PermissionRequest` → `approval`; include `tool_name`, optional `tool_input.description`, `tool_input.command`, and cwd. Generate a UUID request ID when no tool-use ID exists.
- Host is inferred from `TERM_PROGRAM`: `WarpTerminal` → `Warp` / `dev.warp.Warp-Stable`, `Apple_Terminal` → `Terminal` / `com.apple.Terminal`, `iTerm.app` → `iTerm` / `com.googlecode.iterm2`, `vscode` → `Visual Studio Code` / `com.microsoft.VSCode`; unknown values retain an honest app name with no bundle ID. Preserve `TERM_SESSION_ID` or `ITERM_SESSION_ID` when present.

Response JSON uses `{ "kind": "answered", "answers": {...} }`, `approvedOnce`, `approvedForSession`, `denied`, or `handoff`. Claude question output must preserve the original `questions` array exactly. Claude session approval copies the first compatible permission suggestion and changes only its `destination` to `session`. Codex never emits session approval. Denial includes a short message; Claude denial uses `interrupt: false`.

- [x] **Step 4: Implement and harden the Swift Unix socket**

Create the private runtime directory `/tmp/com.nudge.max.agent-<uid>` with exact owner-only mode `0700`, bind its `bridge.sock` with exact mode `0600`, and unlink only the validated socket inode. Cap each input line at 1 MiB, require `protocolVersion == 1`, decode on a background queue, and dispatch events to `@MainActor`. A waiting EOF calls an optional disconnect callback for that matching lease. `AgentBridgeSession` makes response/close idempotent under a lock; partial writes, `EINTR`, EOF, and invalid UTF-8 close fail-open.

- [x] **Step 5: Run helper tests and Swift syntax parsing**

Run: `python3 -m unittest discover -s Tests/HookHelperTests -v`

Run: `swiftc -frontend -parse Nudge/AgentAttention/AgentBridgeServer.swift Nudge/AgentAttention/Core/*.swift`

Expected: both commands PASS.

- [x] **Step 6: Commit the bridge**

```bash
git add Nudge/AgentAttention/AgentBridgeServer.swift Nudge/AgentAttention/Resources Tests/HookHelperTests
git commit -m "feat: bridge coding agent hooks into Nudge"
```

### Task 3: Reversible Claude and Codex connectors

**Files:**
- Create: `Nudge/AgentAttention/Core/ConnectorConfiguration.swift`
- Create: `Nudge/AgentAttention/Core/ConnectorLifecycle.swift`
- Create: `Nudge/AgentAttention/AgentConnectorManager.swift`
- Create: `Tests/NudgeAgentCoreTests/ConnectorConfigurationTests.swift`
- Create: `Tests/NudgeAgentCoreTests/ConnectorLifecycleTests.swift`

**Interfaces:**
- Produces: `AgentConnectorManager.shared`, `refresh()`, `connect(_:) async`, `disconnect(_:) async`.
- Produces pure functions `addingNudgeCodexHooks(to:helperPath:)` and `removingNudgeCodexHooks(from:)` in `ConnectorConfiguration.swift` for structural tests.
- Produces pure `claudePluginFiles(helperData:)` whose relative-path/data output is written by the manager.
- Status values: `notInstalled`, `installing`, `needsTrust`, `connected`, `failed(String)`; Settings labels a fully verified Claude connector as the more honest **Bereit** and persists the last requested mutation so failed disconnects retry disconnect rather than reconnect.

- [x] **Step 1: Write additive merge tests first**

```swift
func testAddingCodexHooksPreservesExistingGroupsAndIsIdempotent() throws {
    let existing = try JSONSerialization.jsonObject(with: Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}"#.utf8))
    let once = addingNudgeCodexHooks(to: existing, helperPath: "/stable/nudge-hook")
    let twice = addingNudgeCodexHooks(to: once, helperPath: "/stable/nudge-hook")
    XCTAssertEqual(jsonData(once), jsonData(twice))
    XCTAssertTrue(jsonString(once).contains("mine"))
}

func testRemovingCodexHooksLeavesForeignHooks() throws {
    let connected = addingNudgeCodexHooks(to: foreignFixture, helperPath: "/stable/nudge-hook")
    let removed = removingNudgeCodexHooks(from: connected)
    XCTAssertTrue(jsonString(removed).contains("mine"))
    XCTAssertFalse(jsonString(removed).contains("com.nudge.max.agent-hook"))
}

func testClaudePluginFilesContainExactIDsHooksAndTimeouts() throws {
    let files = claudePluginFiles(helperData: Data("helper".utf8))
    #expect(files.keys.contains(".claude-plugin/marketplace.json"))
    #expect(files.keys.contains("nudge-agent-attention/hooks/hooks.json"))
    #expect(String(decoding: files["nudge-agent-attention/hooks/hooks.json"]!, as: UTF8.self).contains("\"${CLAUDE_PLUGIN_ROOT}\"/bin/nudge_agent_hook.py claude"))
}
```

- [x] **Step 2: Run focused tests and verify red**

Run: `swift test --filter ConnectorConfigurationTests`

Expected: FAIL because the merge functions do not exist.

- [x] **Step 3: Implement connector writes atomically**

Copy the helper to `~/Library/Application Support/Nudge/AgentBridge/nudge-agent-hook`, mark it executable, write JSON through a sibling temporary file, and replace the target only after successful serialization. Identify every Nudge hook with the exact command marker `# com.nudge.max.agent-hook` or a dedicated `nudgeId` field accepted by that config schema.

For Claude, generate this stable local marketplace/plugin tree beneath `~/Library/Application Support/Nudge/AgentBridge/ClaudeMarketplace`: `.claude-plugin/marketplace.json`, `nudge-agent-attention/.claude-plugin/plugin.json`, `nudge-agent-attention/hooks/hooks.json`, and `nudge-agent-attention/bin/nudge_agent_hook.py`. Use marketplace ID `nudge-local`, plugin ID `nudge-agent-attention`, version `0.1.0`, and a hook command of `"${CLAUDE_PLUGIN_ROOT}"/bin/nudge_agent_hook.py claude`. The hook file contains additive `Stop` (timeout `1`), `PreToolUse` matcher `AskUserQuestion` (timeout `86400`), and `PermissionRequest` matcher `*` (timeout `86400`). Run these noninteractive commands with the discovered Claude executable:

```text
claude plugin marketplace add <stable-marketplace-path> --scope user
claude plugin install nudge-agent-attention@nudge-local --scope user
```

For disconnect, call `claude plugin uninstall nudge-agent-attention@nudge-local --scope user --yes` followed by `claude plugin marketplace remove nudge-local --scope user`. Do not touch foreign plugins or settings. Discover Claude only from executable files at `~/.local/bin/claude`, `~/.claude/local/claude`, `/opt/homebrew/bin/claude`, or `/usr/local/bin/claude`; failure produces a clear status instead of invoking an arbitrary shell.

For Codex, structurally merge `Stop` (timeout `1`) and `PermissionRequest` matcher `*` (timeout `86400`) groups in `~/.codex/hooks.json`. The exact command is a shell-quoted stable helper path followed by `codex # com.nudge.max.agent-hook`; the suffix is the ownership marker used for idempotent removal. Report `needsTrust` after installation with the instruction `In Codex /hooks öffnen und Nudge vertrauen`. Missing or empty files become `{ "hooks": {} }`; malformed/non-object JSON is rejected without overwriting it.

- [x] **Step 4: Run all connector/core tests**

Run: `swift test`

Run: `swiftc -frontend -parse Nudge/AgentAttention/AgentConnectorManager.swift Nudge/AgentAttention/Core/*.swift`

Expected: PASS, including idempotent add/remove and exact Claude plugin fixtures; Swift parse exits `0`.

- [x] **Step 5: Commit connectors**

```bash
git add Nudge/AgentAttention/Core/ConnectorConfiguration.swift Nudge/AgentAttention/AgentConnectorManager.swift Tests/NudgeAgentCoreTests
git commit -m "feat: add reversible agent connectors"
```

### Task 4: Runtime center, compact UI, focus, and host handoff

**Files:**
- Create: `Nudge/AgentAttention/AgentAttentionCenter.swift`
- Create: `Nudge/AgentAttention/AgentAttentionView.swift`
- Create: `Nudge/AgentAttention/AgentPanelFocusController.swift`
- Modify: `Nudge/AgentAttention/Core/AgentAttentionState.swift`
- Modify: `Tests/NudgeAgentCoreTests/AgentAttentionStateTests.swift`
- Modify: `Nudge/ContentView.swift`
- Modify: `Nudge/Nudge/NudgeNotchView.swift`
- Modify: `Nudge/components/Notch/NudgeSkyLightWindow.swift`
- Modify: `Nudge/sizing/matters.swift`

**Interfaces:**
- Consumes: reducer actions from Task 1 and bridge sessions from Task 2.
- Produces: `AgentAttentionCenter.shared` with `receive`, `hoverBegan`, `hoverEnded`, `beginEditing`, `endEditing`, `submitQuestion`, `resolveApproval`, `jumpOrHandoff`.
- Produces: `AgentPanelFocusController.beginTextEntry(window:)` and `restorePreviousApplication()`.

- [x] **Step 1: Extend reducer tests for scheduler inputs before wiring the center**

Add assertions that `armCollapse()` returns `nil` during text editing, returns a generation after editing ends, and that only the generation created after the latest hover exit can collapse visibility. Add `dismissCompletion(id:)` and `answersForSubmission() -> [String: String]?`; test that an interactive claim clears an older completion, hidden requests retain drafts, every exact prompt maps to single/multiple/freeform output, incomplete/empty drafts cannot submit, and multiple labels preserve the question's option order.

- [x] **Step 2: Run the focused reducer tests and verify red**

Run: `swift test --filter AgentAttentionStateTests`

Expected: FAIL until all editing and hover transitions required by the runtime adapter are represented in the reducer.

- [x] **Step 3: Implement the thin center scheduler and lifecycle**

```swift
func hoverBegan() {
    collapseTask?.cancel()
    state.setHovering(true)
    if state.activeRequest != nil { state.visible = true }
}

func hoverEnded() {
    state.setHovering(false)
    scheduleCollapseAfterThreeSeconds()
}
```

Keep sound/open/window side effects centralized so multi-display views do not duplicate them. Observe `NSWorkspace.didActivateApplicationNotification`; matching bundle identifiers call `handoff`.

`receive(_ envelope: AgentEventEnvelope, session: AgentBridgeSession)` validates source/payload consistency. Completion IDs are deduplicated with one last-ID value, play sound once, close their session, suppress visual presentation when the origin bundle is frontmost, discard visual presentation while an interactive request is active, and otherwise replace the visible completion. Questions/approvals claim one slot or immediately `handoff()`; the center retains the matching envelope/session until response, peer disconnect, or handoff. `disconnect(envelope:session:)` clears only an exact active match.

Every displayed event arms exactly one three-second Task when not hovering/editing. `hoverBegan()` cancels the task, invalidates its generation, and reveals an unfinished request. `hoverEnded()` starts a fresh three-second task. Successful collapse dismisses a completion, but only hides an unfinished request. A new completion never resurfaces after its timer.

- [x] **Step 4: Implement the compact card**

Use the incumbent black Nudge surface, system typography, white translucent controls, and the existing accent color only for selected/primary state. Render question selector dots, a two-column option grid, an always-available `Eigene Antwort…` field, approval context and conditional buttons, and a large completion jump card. Use accessible button labels. Keep command detail selectable and at most three visual lines. The card consumes actions from the center; drafts remain in the reducer. Increase `openNotchSize` to exactly `640 × 270` and `windowSize` to exactly `640 × 290`, allowing four compact options without scrolling while preserving the existing width and 20-point shadow padding.

Single choice advances immediately except on the final step, which requires `Antworten`. Multi-select toggles choices and uses `Weiter`; freeform uses `Weiter`/`Antworten`. Selector dots allow back/edit. Buttons are `Ablehnen`, `Einmal erlauben`, and conditional `Für Session`; jump labels are exact only when a supported target exists, otherwise honest `Zu <host.appName>`.

- [x] **Step 5: Integrate content priority and robust hover semantics**

Route `NudgeNotchView` as active request → completion → human ping → sender. Forward every hover transition to the center. When agent content becomes visible, open the notch; when it collapses and no human ping is current, close it. Do not call `NudgeNotifier.postBackup` for agent events.

- [x] **Step 6: Enable temporary text focus**

Change `NudgeSkyLightWindow.canBecomeKey` to return `allowsKeyFocus`. Before a freeform field becomes focused, capture the previous `NSRunningApplication`, set `allowsKeyFocus = true`, activate Nudge, and call `makeKey()`. Restore only if Nudge remains frontmost.

- [x] **Step 7: Run tests and syntax parsing**

Run: `swift test`

Run: `find Nudge -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse`

Expected: PASS.

- [x] **Step 8: Commit UI/runtime integration**

```bash
git add Nudge/AgentAttention Nudge/ContentView.swift Nudge/Nudge/NudgeNotchView.swift Nudge/components/Notch/NudgeSkyLightWindow.swift Nudge/sizing/matters.swift Tests
git commit -m "feat: add agent attention notch experience"
```

### Task 5: Settings, app wiring, project resources, and verification

**Files:**
- Modify: `Nudge/components/Settings/SettingsView.swift`
- Modify: `Nudge/NudgeApp.swift`
- Modify: `Nudge/Nudge.entitlements`
- Modify: `Nudge.xcodeproj/project.pbxproj`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AgentAttentionCenter.shared`, `AgentBridgeServer`, `AgentConnectorManager.shared`.
- Produces: app-lifetime bridge startup/shutdown and user-facing connector controls.

- [x] **Step 1: Wire one bridge instance into app lifecycle**

Start the server after launch, route decoded envelopes to `AgentAttentionCenter.shared.receive`, and stop/unlink it during termination. Inject the shared center into every notch view; never create one center per display.

- [x] **Step 2: Add the Agent integrations Settings section**

Each Claude Code/Codex row contains icon/name, derived status, Connect or Disconnect, concise failure text, and a **Demo anzeigen** action. Codex `needsTrust` explains `/hooks`. Claude success explains that existing sessions need `/reload-plugins` or restart.

- [x] **Step 3: Register all sources/resources and remove only App Sandbox**

Add all new Swift files to Sources and `nudge_agent_hook.py` to Copy Bundle Resources. Remove `com.apple.security.app-sandbox` from `Nudge.entitlements`; retain network client/server, automation, camera, calendar, and Hardened Runtime build settings.

- [x] **Step 4: Document V0 behavior and privacy**

Add a README section stating that agent data stays on-device, exact supported Claude/Codex actions, Codex trust requirement, fail-open handoff, and deferred summaries/history.

- [x] **Step 5: Run fresh verification**

Run: `swift test`

Run: `python3 -m unittest discover -s Tests/HookHelperTests -v`

Run: `find Nudge -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse`

Run: `plutil -lint Nudge/Nudge.entitlements Nudge/Info.plist`

Run: `git diff --check origin/main...HEAD || git diff --check`

Expected: every available command PASS. Record that a full `xcodebuild` and rendered UI verification are unavailable until full Xcode is installed.

- [x] **Step 6: Review the complete diff for scope and connector safety**

Confirm: no history/queue/summary code, no network upload, no overwrite of foreign hooks, no duplicate macOS agent notification, and no unowned config removal.

- [x] **Step 7: Commit final wiring**

```bash
git add Nudge Nudge.xcodeproj README.md docs/superpowers
git commit -m "feat: ship agent attention v0"
```
