//
//  NudgeSkyLightWindow.swift
//  nudge
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine
import SwiftUI

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class NudgeSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    weak var notchViewModel: NudgeViewModel?
    private var localDismissMonitor: Any?
    private var outsideClickMonitor: Any?
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
        setupDismissal()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        // SwiftUI's hosting view doesn't request key status through
        // needsPanelToBecomeKey, so take focus on click, never on hover.
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func setupDismissal() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.dismissIfOutside()
        }
        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [clicks, .keyDown]) { [weak self] event in
            guard let self, self.notchViewModel?.notchState == .open else { return event }
            if event.type == .keyDown {
                // Handle Escape before text fields or the picker consume it.
                if event.keyCode == 53, event.window === self || self.isKeyWindow {
                    self.dismissNotch()
                    return nil
                }
            } else {
                self.dismissIfOutside()
            }
            return event
        }
    }

    private func dismissIfOutside() {
        guard let vm = notchViewModel, vm.notchState == .open else { return }
        // The backing panel includes transparent space reserved for expansion.
        // Hit-test against the visible notch, not the whole panel frame.
        let visibleRect = NSRect(
            x: frame.midX - vm.notchSize.width / 2,
            y: frame.maxY - vm.notchSize.height,
            width: vm.notchSize.width,
            height: vm.notchSize.height
        )
        if !visibleRect.contains(NSEvent.mouseLocation) { dismissNotch() }
    }

    private func dismissNotch() {
        guard let vm = notchViewModel else { return }
        withAnimation(.smooth(duration: 0.2)) { vm.dismiss() }
        makeFirstResponder(nil)
        if isKeyWindow { resignKey() }
    }

    deinit {
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
