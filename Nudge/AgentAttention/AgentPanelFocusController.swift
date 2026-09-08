import AppKit

@MainActor
final class AgentPanelFocusController {
    private weak var attachedWindow: NudgeSkyLightWindow?
    private var previousApplication: NSRunningApplication?

    func attach(window: NSWindow) {
        attachedWindow = window as? NudgeSkyLightWindow
    }

    func beginTextEntry(window: NSWindow? = nil) {
        guard let panel = (window as? NudgeSkyLightWindow) ?? attachedWindow else { return }

        if previousApplication == nil,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApplication = frontmost
        }

        panel.allowsKeyFocus = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func restorePreviousApplication() {
        let panel = attachedWindow
        let previous = previousApplication
        previousApplication = nil

        panel?.allowsKeyFocus = false
        if panel?.isKeyWindow == true {
            panel?.resignKey()
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == NSRunningApplication.current.processIdentifier else {
            return
        }
        previous?.activate(options: [.activateAllWindows])
    }
}
