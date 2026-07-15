//
//  GifPickerWindowController.swift
//  Nudge
//
//  Hosts the GIF picker in its own panel, opened from the notch's GIF
//  button and the menu bar.
//

import AppKit
import SwiftUI

final class GifPickerWindowController: NSWindowController {
    static let shared = GifPickerWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        guard let window = window else { return }
        window.title = "Send a GIF"
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("NudgeGifPickerWindow")
        window.contentView = NSHostingView(
            rootView: NudgeGifPickerView(onClose: { [weak self] in self?.close() })
        )
        window.delegate = self
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        super.close()
        relinquishFocus()
    }

    private func relinquishFocus() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

extension GifPickerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { relinquishFocus() }
    func windowDidBecomeKey(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
}
