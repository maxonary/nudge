import AppKit

@MainActor
final class AgentPanelFocusController {
    private weak var attachedWindow: NudgeSkyLightWindow?
    private var previousApplication: NSRunningApplication?

    nonisolated init() {}

    func attach(window: NSWindow) {
        attachedWindow = window as? NudgeSkyLightWindow
    }

    func beginTextEntry(window: NSWindow? = nil) {
        if let providedPanel = window as? NudgeSkyLightWindow {
            attachedWindow = providedPanel
        }
        guard let panel = attachedWindow else { return }

        if previousApplication == nil,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApplication = frontmost
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func endTextEntry() {
        if attachedWindow?.isKeyWindow == true {
            attachedWindow?.resignKey()
        }
    }

    /// `willActivate` runs right before the previous app is brought forward, so
    /// the caller can tell that activation apart from the user switching apps.
    func restorePreviousApplication(willActivate: (NSRunningApplication) -> Void = { _ in }) {
        endTextEntry()

        let previous = previousApplication
        previousApplication = nil

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == NSRunningApplication.current.processIdentifier,
              let previous else {
            return
        }
        willActivate(previous)
        previous.activate(options: [.activateAllWindows])
    }
}
