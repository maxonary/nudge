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

        panel.allowsKeyFocus = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func endTextEntry() {
        attachedWindow?.allowsKeyFocus = false
        if attachedWindow?.isKeyWindow == true {
            attachedWindow?.resignKey()
        }
    }

    func restorePreviousApplication() {
        endTextEntry()

        let previous = previousApplication
        previousApplication = nil

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == NSRunningApplication.current.processIdentifier else {
            return
        }
        previous?.activate(options: [.activateAllWindows])
    }
}
