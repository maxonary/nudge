//
//  BoringNotchSkyLightWindow.swift
//  Nudge
//
//  Borderless NSPanel that sits at the system menu-bar level over the
//  physical notch. The SkyLight-based lock-screen overlay from upstream
//  Boring Notch is dropped — Nudge doesn't need to render over the
//  lock screen and dropping it removes the SkyLightWindow SPM dep.
//

import Cocoa

class BoringNotchSkyLightWindow: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
    }

    // No-op preserved so AppDelegate's lock/unlock paths still compile.
    func enableSkyLight() {}
    func disableSkyLight() {}
}
