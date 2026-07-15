commit 4d8c2b9f552cc0d8a481072805de807a678c6a21
Author: Maximilian Arnold <max@ontora.com>
Date:   Fri May 15 14:21:28 2026 -0700

    Drop unused SPM deps, XPC helper target, mediaremote-adapter, updater (Tier 3)
    
    Final pass of the upstream cleanup. With Tier 1+2 having stripped all
    the .swift files that imported these, they were pure bloat.
    
    SPM dependencies removed from the project (none imported by any
    remaining code):
    - Sparkle, Lottie (lottie-spm), LaunchAtLogin-Modern, MacroVisionKit,
      SkyLightWindow, AsyncXPCConnection, SwiftUIIntrospect, Pow,
      swift-collections (Collections)
    
    Kept (still imported): Defaults, KeyboardShortcuts.
    
    Targets / embedded resources removed:
    - The whole BoringNotchXPCHelper.xpc target (PBXNativeTarget,
      XCConfigurationList, both build configs, the synchronized root
      group, the ContainerItemProxy + TargetDependency that linked it,
      the Embed XPC Services build phase entry, and the XPCHelperClient
      group). The directory on disk is gone too.
    - The mediaremote-adapter framework + mediaremote-adapter.pl +
      MediaRemoteAdapterTestClient (Frameworks + Embed Frameworks + the
      PBXGroup + the file refs). Directory on disk gone.
    - The Sparkle appcast template at updater/.
    - TODO_V2_CLEANUP.md (its work is done).
    
    pbxproj numbers: 1171 -> 866 lines (-26%). plutil -lint passes.
    
    Workflow knock-on: the release workflow's "Sign every nested binary
    inside-out" pass becomes mostly a no-op now — Sparkle's nested helper
    binaries and the test client are no longer embedded, so there's
    nothing for xcodebuild to miss.
    
    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>

diff --git a/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements b/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements
deleted file mode 100644
index e89b7f3..0000000
--- a/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements
+++ /dev/null
@@ -1,8 +0,0 @@
-<?xml version="1.0" encoding="UTF-8"?>
-<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
-<plist version="1.0">
-<dict>
-	<key>com.apple.security.app-sandbox</key>
-	<false/>
-</dict>
-</plist>
diff --git a/BoringNotchXPCHelper/BoringNotchXPCHelper.swift b/BoringNotchXPCHelper/BoringNotchXPCHelper.swift
deleted file mode 100644
index fc93dfb..0000000
--- a/BoringNotchXPCHelper/BoringNotchXPCHelper.swift
+++ /dev/null
@@ -1,191 +0,0 @@
-//
-//  BoringNotchXPCHelper.swift
-//  BoringNotchXPCHelper
-//
-//  Created by Alexander on 2025-11-16.
-//
-
-import Foundation
-import ApplicationServices
-import IOKit
-import CoreGraphics
-
-class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
-    
-    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
-        reply(AXIsProcessTrusted())
-    }
-
-    @objc func requestAccessibilityAuthorization() {
-        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
-        AXIsProcessTrustedWithOptions(options)
-    }
-
-    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
-        if AXIsProcessTrusted() {
-            reply(true)
-            return
-        }
-
-        if promptIfNeeded {
-            requestAccessibilityAuthorization()
-        }
-
-        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
-            reply(AXIsProcessTrusted())
-        }
-    }
-    
-    private class KeyboardBrightnessClient {
-        private static let keyboardID: UInt64 = 1
-        private var clientInstance: NSObject?
-        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
-        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
-
-        init() {
-            var loaded = false
-            let bundlePaths = [
-                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
-                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
-            ]
-            for path in bundlePaths where !loaded {
-                if let bundle = Bundle(path: path) {
-                    loaded = bundle.load()
-                }
-            }
-            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
-                clientInstance = cls.init()
-            }
-        }
-
-        var isAvailable: Bool { clientInstance != nil }
-
-        func currentBrightness() -> Float? {
-            guard let clientInstance,
-                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
-            else { return nil }
-            return fn(clientInstance, getSelector, Self.keyboardID)
-        }
-
-        func setBrightness(_ value: Float) -> Bool {
-            guard let clientInstance,
-                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
-            else { return false }
-            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
-        }
-
-        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
-        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool
-
-        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
-            guard let cls = object_getClass(object),
-                  let method = class_getInstanceMethod(cls, selector)
-            else { return nil }
-            let imp = method_getImplementation(method)
-            return unsafeBitCast(imp, to: type)
-        }
-    }
-
-    private static let keyboardClient = KeyboardBrightnessClient()
-
-    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
-        reply(Self.keyboardClient.isAvailable)
-    }
-
-    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
-        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
-    }
-
-    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
-        reply(Self.keyboardClient.setBrightness(value))
-    }
-    // MARK: - Screen Brightness (moved from client app into helper)
-
-    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
-        var b: Float = 0
-        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
-    }
-
-    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
-        var b: Float = 0
-        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
-            reply(NSNumber(value: b))
-            return
-        }
-        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
-            var level: Float = 0
-            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
-                IOObjectRelease(io)
-                reply(NSNumber(value: level))
-                return
-            }
-            IOObjectRelease(io)
-        }
-        reply(nil)
-    }
-
-    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
-        let clamped = max(0, min(1, value))
-        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
-            reply(true)
-            return
-        }
-        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
-            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
-            IOObjectRelease(io)
-            reply(ok)
-            return
-        }
-        reply(false)
-    }
-
-    // MARK: - Private helpers for DisplayServices / IOKit access
-    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
-        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
-        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
-        let fn = unsafeBitCast(sym, to: Fn.self)
-        var tmp: Float = 0
-        let r = fn(displayID, &tmp)
-        if r == 0 { out = tmp; return true }
-        return false
-    }
-
-    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
-        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
-        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
-        let fn = unsafeBitCast(sym, to: Fn.self)
-        return fn(displayID, value) == 0
-    }
-
-    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
-        var iterator: io_iterator_t = 0
-        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
-        defer { IOObjectRelease(iterator) }
-
-        while case let service = IOIteratorNext(iterator), service != 0 {
-            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
-            if let vendorID = info[kDisplayVendorID] as? UInt32,
-               let productID = info[kDisplayProductID] as? UInt32,
-               vendorID == CGDisplayVendorNumber(displayID),
-               productID == CGDisplayModelNumber(displayID) {
-                return service
-            }
-            IOObjectRelease(service)
-        }
-        return nil
-    }
-
-    // MARK: - Helper handle for private framework
-    private enum DisplayServicesHandle {
-        static let handle: UnsafeMutableRawPointer? = {
-            let paths = [
-                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
-                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
-            ]
-            for p in paths {
-                if let h = dlopen(p, RTLD_LAZY) { return h }
-            }
-            return nil
-        }()
-    }
-}
diff --git a/BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift b/BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift
deleted file mode 100644
index 01eccf6..0000000
--- a/BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift
+++ /dev/null
@@ -1,43 +0,0 @@
-//
-//  BoringNotchXPCHelperProtocol.swift
-//  BoringNotchXPCHelper
-//
-//  Created by Alexander on 2025-11-16.
-//
-
-import Foundation
-
-/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
-@objc protocol BoringNotchXPCHelperProtocol {
-    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
-    func requestAccessibilityAuthorization()
-    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
-    // Keyboard backlight / CoreBrightness access (performed by the helper)
-    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
-    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
-    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
-    // Screen brightness access (performed by the helper)
-    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
-    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
-    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
-}
-
-/*
- To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:
-
-     connectionToService = NSXPCConnection(serviceName: "theboringteam.boringnotch.BoringNotchXPCHelper")
-     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)
-     connectionToService.resume()
-
- Once you have a connection to the service, you can use it like this:
-
-     if let proxy = connectionToService.remoteObjectProxy as? BoringNotchXPCHelperProtocol {
-         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
-             NSLog("Result of calculation is: \(result)")
-         }
-     }
-
- And, when you are finished with the service, clean up the connection like this:
-
-     connectionToService.invalidate()
-*/
diff --git a/BoringNotchXPCHelper/Info.plist b/BoringNotchXPCHelper/Info.plist
deleted file mode 100644
index c123a5d..0000000
--- a/BoringNotchXPCHelper/Info.plist
+++ /dev/null
@@ -1,11 +0,0 @@
-<?xml version="1.0" encoding="UTF-8"?>
-<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
-<plist version="1.0">
-<dict>
-	<key>XPCService</key>
-	<dict>
-		<key>ServiceType</key>
-		<string>Application</string>
-	</dict>
-</dict>
-</plist>
diff --git a/BoringNotchXPCHelper/main.swift b/BoringNotchXPCHelper/main.swift
deleted file mode 100644
index f667f36..0000000
--- a/BoringNotchXPCHelper/main.swift
+++ /dev/null
@@ -1,39 +0,0 @@
-//
-//  main.swift
-//  BoringNotchXPCHelper
-//
-//  Created by Alexander on 2025-11-16.
-//
-
-import Foundation
-
-class ServiceDelegate: NSObject, NSXPCListenerDelegate {
-    
-    /// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
-    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
-        
-        // Configure the connection.
-        // First, set the interface that the exported object implements.
-        newConnection.exportedInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)
-        
-        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
-        let exportedObject = BoringNotchXPCHelper()
-        newConnection.exportedObject = exportedObject
-        
-        // Resuming the connection allows the system to deliver more incoming messages.
-        newConnection.resume()
-        
-        // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call invalidate() on the connection and return false.
-        return true
-    }
-}
-
-// Create the delegate for the service.
-let delegate = ServiceDelegate()
-
-// Set up the one NSXPCListener for this service. It will handle all incoming connections.
-let listener = NSXPCListener.service()
-listener.delegate = delegate
-
-// Resuming the serviceListener starts this service. This method does not return.
-listener.resume()
diff --git a/TODO_V2_CLEANUP.md b/TODO_V2_CLEANUP.md
deleted file mode 100644
index 39a34c8..0000000
--- a/TODO_V2_CLEANUP.md
+++ /dev/null
@@ -1,78 +0,0 @@
-# v2 cleanup TODO
-
-v1 took the "disable-and-replace" path rather than "delete-and-rewrite"
-to ship today. The features below are still on disk and still compile,
-but no live code path invokes them. The user-visible app is Nudge-only.
-
-When time permits, delete the following from disk AND remove their
-`PBXFileReference` / `PBXBuildFile` / group-children entries from
-`boringNotch.xcodeproj/project.pbxproj`:
-
-## Managers (boringNotch/managers/)
-- MusicManager.swift
-- CalendarManager.swift
-- WebcamManager.swift
-- BatteryActivityManager.swift
-- BrightnessManager.swift
-- VolumeManager.swift
-- ImageService.swift (used by music album art)
-
-## MediaControllers (boringNotch/MediaControllers/)
-- All 4 files (AppleMusic, Spotify, YouTubeMusic, NowPlaying)
-
-## Components (boringNotch/components/)
-- Music/ (entire folder)
-- Calendar/ (entire folder)
-- Webcam/ (entire folder)
-- Shelf/ (entire folder)
-- Tabs/ (entire folder — Nudge has no tabs)
-- Live activities/ (entire folder)
-- LottieView.swift, AnimatedFace.swift, EmptyState.swift,
-  ProgressIndicator.swift, TestView.swift, Tips/, WhatsNewView.swift
-
-## Observers (boringNotch/observers/)
-- DragDetector.swift
-- MediaKeyInterceptor.swift
-- FullscreenMediaDetection.swift
-
-## XPC + helpers
-- boringNotch/XPCHelperClient/ (entire folder)
-- BoringNotchXPCHelper/ (entire target — also drop from project)
-- mediaremote-adapter/ (entire folder + resource entry)
-
-## Helpers (boringNotch/helpers/)
-- AudioPlayer.swift, AppleScriptHelper.swift, MediaChecker.swift,
-  ApplicationRelauncher.swift, Clipboard+Content.swift
-
-## Models (boringNotch/models/)
-- CalendarModel.swift, EventModel.swift, BatteryStatusViewModel.swift,
-  PlaybackState.swift, MusicControlButton.swift, SharingStateManager.swift
-
-## SPM dependencies that can go
-- Sparkle (we disabled auto-update)
-- LaunchAtLogin (we removed the toggle)
-- Lottie (only used by music visualizer)
-- SkyLightWindow + AsyncXPCConnection + MacroVisionKit (depend on the
-  music/XPC features)
-
-## Other
-- `boringNotch/boring.m4a` (welcome sound) + its resource entry
-- `boringNotch/Localizable.xcstrings` — orphaned keys for music/calendar/etc.
-  Either replace with a tiny Nudge-only string catalog or remove entirely
-  (we don't ship localizations in v1).
-- `BoringViewCoordinator.swift`: `sneakPeek`, `expandingView`,
-  `toggleSneakPeek`, `toggleExpandingView` data + methods still exist for
-  data-model reasons but have no callers now.
-- `BoringViewModel.swift`: drop the `webcamManager`, `detector`,
-  `toggleCameraPreview`, drop-target fields, isHoveringCalendar,
-  isBatteryPopoverActive once their consumers are gone.
-
-## Rename internal identifiers
-- Xcode target name `boringNotch` → `Nudge` (touches schemes, build
-  configurations, file paths, and DerivedData).
-- Bundle identifier (likely `com.boring.notch` or similar) → something
-  Ontora-owned.
-- Top-level `boringNotch/` source folder → `Nudge/`.
-
-These were deferred because each one requires careful pbxproj surgery
-and we wanted v1 to build today.
diff --git a/boringNotch.xcodeproj/project.pbxproj b/boringNotch.xcodeproj/project.pbxproj
index a4c25a0..a5d1529 100644
--- a/boringNotch.xcodeproj/project.pbxproj
+++ b/boringNotch.xcodeproj/project.pbxproj
@@ -7,37 +7,23 @@
 	objects = {
 
 /* Begin PBXBuildFile section */
-		111BE95D2ECD71E10079DD4E /* AsyncXPCConnection in Frameworks */ = {isa = PBXBuildFile; productRef = 111BE95C2ECD71E10079DD4E /* AsyncXPCConnection */; };
-		111BEA512ECFBF7F0079DD4E /* MacroVisionKit in Frameworks */ = {isa = PBXBuildFile; productRef = 111BEA502ECFBF7F0079DD4E /* MacroVisionKit */; };
-		111BEA5F2ED07A340079DD4E /* MacroVisionKit in Frameworks */ = {isa = PBXBuildFile; productRef = 111BEA5E2ED07A340079DD4E /* MacroVisionKit */; };
 		111BEA612ED09B1B0079DD4E /* NSScreen+UUID.swift in Sources */ = {isa = PBXBuildFile; fileRef = 111BEA602ED09B1B0079DD4E /* NSScreen+UUID.swift */; };
-		111BEA6F2ED166E20079DD4E /* MacroVisionKit in Frameworks */ = {isa = PBXBuildFile; productRef = 111BEA6E2ED166E20079DD4E /* MacroVisionKit */; };
-		112B0EB82E30DD0F00562D6C /* MediaRemoteAdapterTestClient in Resources */ = {isa = PBXBuildFile; fileRef = 112B0EB52E30DD0F00562D6C /* MediaRemoteAdapterTestClient */; };
-		112B0EB92E30DD0F00562D6C /* mediaremote-adapter.pl in Resources */ = {isa = PBXBuildFile; fileRef = 112B0EB32E30DD0F00562D6C /* mediaremote-adapter.pl */; };
-		112B0EBB2E30DD5000562D6C /* MediaRemoteAdapter.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = 112B0EBA2E30DD5000562D6C /* MediaRemoteAdapter.framework */; };
 		112FB7352CCF16F70015238C /* NotchSpaceManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 112FB7342CCF16F70015238C /* NotchSpaceManager.swift */; };
 		1160F8D82DD98230006FBB94 /* NotchShape.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1160F8D72DD98230006FBB94 /* NotchShape.swift */; };
-		117AB5172E30E09C00558921 /* MediaRemoteAdapter.framework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = 112B0EBA2E30DD5000562D6C /* MediaRemoteAdapter.framework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
-		1194E8852EA57D23009C82D6 /* SkyLightWindow in Frameworks */ = {isa = PBXBuildFile; productRef = 1194E8842EA57D23009C82D6 /* SkyLightWindow */; };
 		1194E8872EA6DDA7009C82D6 /* BoringNotchSkyLightWindow.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1194E8862EA6DDA7009C82D6 /* BoringNotchSkyLightWindow.swift */; };
 		11C5E3132DFE85970065821E /* SettingsWindowController.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11C5E3112DFE85970065821E /* SettingsWindowController.swift */; };
 		11C5E3162DFE88510065821E /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11C5E3152DFE88510065821E /* SettingsView.swift */; };
 		11CC44A22CEE614100C7244B /* BoringViewCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11CC44A12CEE614100C7244B /* BoringViewCoordinator.swift */; };
 		11CFC65F2E097F2F00748C80 /* OnboardingView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11CFC65E2E097F2100748C80 /* OnboardingView.swift */; };
 		11CFC6652E09C7B300748C80 /* OnboardingFinishView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 11CFC6642E09C7B300748C80 /* OnboardingFinishView.swift */; };
-		11F7485B2EC9AABA00F841DB /* BoringNotchXPCHelper.xpc in Embed XPC Services */ = {isa = PBXBuildFile; fileRef = 11F7484F2EC9AABA00F841DB /* BoringNotchXPCHelper.xpc */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
-		11F748732EC9DA9300F841DB /* Lottie in Frameworks */ = {isa = PBXBuildFile; productRef = 11F748722EC9DA9300F841DB /* Lottie */; };
 		1443E7F32C609DCE0027C1FC /* matters.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1443E7F22C609DCE0027C1FC /* matters.swift */; };
 		14CEF4162C5CAED300855D72 /* boringNotchApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 14CEF4152C5CAED300855D72 /* boringNotchApp.swift */; };
 		14CEF4182C5CAED300855D72 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 14CEF4172C5CAED300855D72 /* ContentView.swift */; };
 		14CEF41A2C5CAED400855D72 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 14CEF4192C5CAED400855D72 /* Assets.xcassets */; };
 		14CEF41D2C5CAED400855D72 /* Preview Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 14CEF41C2C5CAED400855D72 /* Preview Assets.xcassets */; };
-		14D0321A2C68F32E0096E6A1 /* LaunchAtLogin in Frameworks */ = {isa = PBXBuildFile; productRef = 14D032192C68F32E0096E6A1 /* LaunchAtLogin */; };
-		14D0321D2C68F3350096E6A1 /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = 14D0321C2C68F3350096E6A1 /* Sparkle */; };
 		14D570B92C5E98A20011E668 /* drop.swift in Sources */ = {isa = PBXBuildFile; fileRef = 14D570B82C5E98A20011E668 /* drop.swift */; };
 		14D570BC2C5E98EB0011E668 /* generic.swift in Sources */ = {isa = PBXBuildFile; fileRef = 14D570BB2C5E98EB0011E668 /* generic.swift */; };
 		14D570C92C5F38890011E668 /* BoringViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = 14D570C82C5F38890011E668 /* BoringViewModel.swift */; };
-		9A987A102C73CA8D005CA465 /* Collections in Frameworks */ = {isa = PBXBuildFile; productRef = 9A987A0F2C73CA8D005CA465 /* Collections */; };
 		AAA000000000000000000020 /* NudgeConstants.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAA000000000000000000010 /* NudgeConstants.swift */; };
 		AAA000000000000000000021 /* NudgeIdentity.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAA000000000000000000011 /* NudgeIdentity.swift */; };
 		AAA000000000000000000022 /* NudgeTransport.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAA000000000000000000012 /* NudgeTransport.swift */; };
@@ -49,7 +35,6 @@
 		AAA000000000000000000028 /* NudgeStats.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAA000000000000000000018 /* NudgeStats.swift */; };
 		AAA000000000000000000029 /* NudgeRoster.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAA000000000000000000019 /* NudgeRoster.swift */; };
 		B10348D92C74E56000475897 /* ConditionalModifier.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10348D82C74E56000475897 /* ConditionalModifier.swift */; };
-		B1628B922CC260C0003D8DF3 /* SwiftUIIntrospect in Frameworks */ = {isa = PBXBuildFile; productRef = B1628B912CC260C0003D8DF3 /* SwiftUIIntrospect */; };
 		B17266DF2C64DFA00031BA0D /* BundleInfos.swift in Sources */ = {isa = PBXBuildFile; fileRef = B17266DE2C64DFA00031BA0D /* BundleInfos.swift */; };
 		B17266E12C6532560031BA0D /* Localizable.xcstrings in Resources */ = {isa = PBXBuildFile; fileRef = B17266E02C6532560031BA0D /* Localizable.xcstrings */; };
 		B18654392C6F4990000B926A /* KeyboardShortcuts in Frameworks */ = {isa = PBXBuildFile; productRef = B18654382C6F4990000B926A /* KeyboardShortcuts */; };
@@ -60,13 +45,6 @@
 /* End PBXBuildFile section */
 
 /* Begin PBXContainerItemProxy section */
-		11F748592EC9AABA00F841DB /* PBXContainerItemProxy */ = {
-			isa = PBXContainerItemProxy;
-			containerPortal = 14CEF40A2C5CAED200855D72 /* Project object */;
-			proxyType = 1;
-			remoteGlobalIDString = 11F7484E2EC9AABA00F841DB;
-			remoteInfo = BoringNotchXPCHelper;
-		};
 /* End PBXContainerItemProxy section */
 
 /* Begin PBXCopyFilesBuildPhase section */
@@ -76,7 +54,6 @@
 			dstPath = "$(CONTENTS_FOLDER_PATH)/XPCServices";
 			dstSubfolderSpec = 16;
 			files = (
-				11F7485B2EC9AABA00F841DB /* BoringNotchXPCHelper.xpc in Embed XPC Services */,
 			);
 			name = "Embed XPC Services";
 			runOnlyForDeploymentPostprocessing = 0;
@@ -87,7 +64,6 @@
 			dstPath = "";
 			dstSubfolderSpec = 10;
 			files = (
-				117AB5172E30E09C00558921 /* MediaRemoteAdapter.framework in Embed Frameworks */,
 			);
 			name = "Embed Frameworks";
 			runOnlyForDeploymentPostprocessing = 0;
@@ -96,9 +72,6 @@
 
 /* Begin PBXFileReference section */
 		111BEA602ED09B1B0079DD4E /* NSScreen+UUID.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "NSScreen+UUID.swift"; sourceTree = "<group>"; };
-		112B0EB32E30DD0F00562D6C /* mediaremote-adapter.pl */ = {isa = PBXFileReference; lastKnownFileType = text.script.perl; path = "mediaremote-adapter.pl"; sourceTree = "<group>"; };
-		112B0EB52E30DD0F00562D6C /* MediaRemoteAdapterTestClient */ = {isa = PBXFileReference; lastKnownFileType = "compiled.mach-o.executable"; path = MediaRemoteAdapterTestClient; sourceTree = "<group>"; };
-		112B0EBA2E30DD5000562D6C /* MediaRemoteAdapter.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = MediaRemoteAdapter.framework; path = "mediaremote-adapter/MediaRemoteAdapter.framework"; sourceTree = "<group>"; };
 		112FB7342CCF16F70015238C /* NotchSpaceManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NotchSpaceManager.swift; sourceTree = "<group>"; };
 		1160F8D72DD98230006FBB94 /* NotchShape.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NotchShape.swift; sourceTree = "<group>"; };
 		1194E8862EA6DDA7009C82D6 /* BoringNotchSkyLightWindow.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BoringNotchSkyLightWindow.swift; sourceTree = "<group>"; };
@@ -107,7 +80,6 @@
 		11CC44A12CEE614100C7244B /* BoringViewCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BoringViewCoordinator.swift; sourceTree = "<group>"; };
 		11CFC65E2E097F2100748C80 /* OnboardingView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OnboardingView.swift; sourceTree = "<group>"; };
 		11CFC6642E09C7B300748C80 /* OnboardingFinishView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OnboardingFinishView.swift; sourceTree = "<group>"; };
-		11F7484F2EC9AABA00F841DB /* BoringNotchXPCHelper.xpc */ = {isa = PBXFileReference; explicitFileType = "wrapper.xpc-service"; includeInIndex = 0; path = BoringNotchXPCHelper.xpc; sourceTree = BUILT_PRODUCTS_DIR; };
 		1443E7F22C609DCE0027C1FC /* matters.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = matters.swift; sourceTree = "<group>"; };
 		1443E7F42C609E650027C1FC /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
 		14CEF4122C5CAED300855D72 /* boringNotch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = boringNotch.app; sourceTree = BUILT_PRODUCTS_DIR; };
@@ -140,18 +112,10 @@
 /* End PBXFileReference section */
 
 /* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
-		11F7485C2EC9AABA00F841DB /* PBXFileSystemSynchronizedBuildFileExceptionSet */ = {
-			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
-			membershipExceptions = (
-				Info.plist,
-			);
-			target = 11F7484E2EC9AABA00F841DB /* BoringNotchXPCHelper */;
-		};
 /* End PBXFileSystemSynchronizedBuildFileExceptionSet section */
 
 /* Begin PBXFileSystemSynchronizedRootGroup section */
 		112FB72F2CCF12CC0015238C /* private */ = {isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {}; explicitFolders = (); path = private; sourceTree = "<group>"; };
-		11F748502EC9AABA00F841DB /* BoringNotchXPCHelper */ = {isa = PBXFileSystemSynchronizedRootGroup; exceptions = (11F7485C2EC9AABA00F841DB /* PBXFileSystemSynchronizedBuildFileExceptionSet */, ); explicitFileTypes = {}; explicitFolders = (); path = BoringNotchXPCHelper; sourceTree = "<group>"; };
 /* End PBXFileSystemSynchronizedRootGroup section */
 
 /* Begin PBXFrameworksBuildPhase section */
@@ -166,19 +130,8 @@
 			isa = PBXFrameworksBuildPhase;
 			buildActionMask = 2147483647;
 			files = (
-				111BEA5F2ED07A340079DD4E /* MacroVisionKit in Frameworks */,
-				9A987A102C73CA8D005CA465 /* Collections in Frameworks */,
-				1194E8852EA57D23009C82D6 /* SkyLightWindow in Frameworks */,
-				112B0EBB2E30DD5000562D6C /* MediaRemoteAdapter.framework in Frameworks */,
-				14D0321D2C68F3350096E6A1 /* Sparkle in Frameworks */,
-				111BEA6F2ED166E20079DD4E /* MacroVisionKit in Frameworks */,
-				11F748732EC9DA9300F841DB /* Lottie in Frameworks */,
-				14D0321A2C68F32E0096E6A1 /* LaunchAtLogin in Frameworks */,
-				111BEA512ECFBF7F0079DD4E /* MacroVisionKit in Frameworks */,
 				B18654392C6F4990000B926A /* KeyboardShortcuts in Frameworks */,
 				B19016222CC15B3D00E3F12E /* Defaults in Frameworks */,
-				111BE95D2ECD71E10079DD4E /* AsyncXPCConnection in Frameworks */,
-				B1628B922CC260C0003D8DF3 /* SwiftUIIntrospect in Frameworks */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
 		};
@@ -213,15 +166,6 @@
 			path = Views;
 			sourceTree = "<group>";
 		};
-		112B0EB62E30DD0F00562D6C /* mediaremote-adapter */ = {
-			isa = PBXGroup;
-			children = (
-				112B0EB32E30DD0F00562D6C /* mediaremote-adapter.pl */,
-				112B0EB52E30DD0F00562D6C /* MediaRemoteAdapterTestClient */,
-			);
-			path = "mediaremote-adapter";
-			sourceTree = "<group>";
-		};
 		1132E5232E78D6DA0068732D /* YouTube Music Controller */ = {
 			isa = PBXGroup;
 			children = (
@@ -244,13 +188,6 @@
 			path = Providers;
 			sourceTree = "<group>";
 		};
-		11F748672EC9AC9600F841DB /* XPCHelperClient */ = {
-			isa = PBXGroup;
-			children = (
-			);
-			path = XPCHelperClient;
-			sourceTree = "<group>";
-		};
 		14288DD92C6E015000B9F80C /* helpers */ = {
 			isa = PBXGroup;
 			children = (
@@ -315,9 +252,7 @@
 		14CEF4092C5CAED200855D72 = {
 			isa = PBXGroup;
 			children = (
-				112B0EB62E30DD0F00562D6C /* mediaremote-adapter */,
 				14CEF4142C5CAED300855D72 /* boringNotch */,
-				11F748502EC9AABA00F841DB /* BoringNotchXPCHelper */,
 				14CEF4132C5CAED300855D72 /* Products */,
 				14D031EC2C689DB70096E6A1 /* Frameworks */,
 			);
@@ -327,7 +262,6 @@
 			isa = PBXGroup;
 			children = (
 				14CEF4122C5CAED300855D72 /* boringNotch.app */,
-				11F7484F2EC9AABA00F841DB /* BoringNotchXPCHelper.xpc */,
 			);
 			name = Products;
 			sourceTree = "<group>";
@@ -336,7 +270,6 @@
 			isa = PBXGroup;
 			children = (
 				AAA000000000000000000030 /* Nudge */,
-				11F748672EC9AC9600F841DB /* XPCHelperClient */,
 				116398942DF5D6B40052E6AF /* Providers */,
 				14288DE22C6E016F00B9F80C /* observers */,
 				14288DD92C6E015000B9F80C /* helpers */,
@@ -375,7 +308,6 @@
 			children = (
 				14D031EF2C689DC00096E6A1 /* ApplicationServices.framework */,
 				14D031ED2C689DB70096E6A1 /* IOKit.framework */,
-				112B0EBA2E30DD5000562D6C /* MediaRemoteAdapter.framework */,
 			);
 			name = Frameworks;
 			sourceTree = "<group>";
@@ -510,28 +442,6 @@
 /* End PBXGroup section */
 
 /* Begin PBXNativeTarget section */
-		11F7484E2EC9AABA00F841DB /* BoringNotchXPCHelper */ = {
-			isa = PBXNativeTarget;
-			buildConfigurationList = 11F7485D2EC9AABA00F841DB /* Build configuration list for PBXNativeTarget "BoringNotchXPCHelper" */;
-			buildPhases = (
-				11F7484B2EC9AABA00F841DB /* Sources */,
-				11F7484C2EC9AABA00F841DB /* Frameworks */,
-				11F7484D2EC9AABA00F841DB /* Resources */,
-			);
-			buildRules = (
-			);
-			dependencies = (
-			);
-			fileSystemSynchronizedGroups = (
-				11F748502EC9AABA00F841DB /* BoringNotchXPCHelper */,
-			);
-			name = BoringNotchXPCHelper;
-			packageProductDependencies = (
-			);
-			productName = BoringNotchXPCHelper;
-			productReference = 11F7484F2EC9AABA00F841DB /* BoringNotchXPCHelper.xpc */;
-			productType = "com.apple.product-type.xpc-service";
-		};
 		14CEF4112C5CAED300855D72 /* boringNotch */ = {
 			isa = PBXNativeTarget;
 			buildConfigurationList = 14CEF4212C5CAED400855D72 /* Build configuration list for PBXNativeTarget "boringNotch" */;
@@ -545,25 +455,14 @@
 			buildRules = (
 			);
 			dependencies = (
-				11F7485A2EC9AABA00F841DB /* PBXTargetDependency */,
 			);
 			fileSystemSynchronizedGroups = (
 				112FB72F2CCF12CC0015238C /* private */,
 			);
 			name = boringNotch;
 			packageProductDependencies = (
-				14D032192C68F32E0096E6A1 /* LaunchAtLogin */,
-				14D0321C2C68F3350096E6A1 /* Sparkle */,
 				B18654382C6F4990000B926A /* KeyboardShortcuts */,
-				9A987A0F2C73CA8D005CA465 /* Collections */,
 				B19016212CC15B3D00E3F12E /* Defaults */,
-				B1628B912CC260C0003D8DF3 /* SwiftUIIntrospect */,
-				1194E8842EA57D23009C82D6 /* SkyLightWindow */,
-				11F748722EC9DA9300F841DB /* Lottie */,
-				111BE95C2ECD71E10079DD4E /* AsyncXPCConnection */,
-				111BEA502ECFBF7F0079DD4E /* MacroVisionKit */,
-				111BEA5E2ED07A340079DD4E /* MacroVisionKit */,
-				111BEA6E2ED166E20079DD4E /* MacroVisionKit */,
 			);
 			productName = dynamicNotch;
 			productReference = 14CEF4122C5CAED300855D72 /* boringNotch.app */;
@@ -579,9 +478,6 @@
 				LastSwiftUpdateCheck = 1640;
 				LastUpgradeCheck = 1640;
 				TargetAttributes = {
-					11F7484E2EC9AABA00F841DB = {
-						CreatedOnToolsVersion = 16.4;
-					};
 					14CEF4112C5CAED300855D72 = {
 						CreatedOnToolsVersion = 15.4;
 						LastSwiftMigration = 1540;
@@ -598,24 +494,14 @@
 			);
 			mainGroup = 14CEF4092C5CAED200855D72;
 			packageReferences = (
-				14D032182C68F32E0096E6A1 /* XCRemoteSwiftPackageReference "LaunchAtLogin-Modern" */,
-				14D0321B2C68F3350096E6A1 /* XCRemoteSwiftPackageReference "Sparkle" */,
 				B18654372C6F4990000B926A /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */,
-				9A987A0E2C73CA8D005CA465 /* XCRemoteSwiftPackageReference "swift-collections" */,
-				9A987A112C73CAA1005CA465 /* XCRemoteSwiftPackageReference "Pow" */,
 				B19016202CC15B3D00E3F12E /* XCRemoteSwiftPackageReference "Defaults" */,
-				B1628B902CC260C0003D8DF3 /* XCRemoteSwiftPackageReference "swiftui-introspect" */,
-				1194E8832EA57D23009C82D6 /* XCRemoteSwiftPackageReference "SkyLightWindow" */,
-				11F748712EC9DA9300F841DB /* XCRemoteSwiftPackageReference "lottie-spm" */,
-				111BE95B2ECD71E10079DD4E /* XCRemoteSwiftPackageReference "AsyncXPCConnection" */,
-				111BEA6D2ED166E20079DD4E /* XCRemoteSwiftPackageReference "MacroVisionKit" */,
 			);
 			productRefGroup = 14CEF4132C5CAED300855D72 /* Products */;
 			projectDirPath = "";
 			projectRoot = "";
 			targets = (
 				14CEF4112C5CAED300855D72 /* boringNotch */,
-				11F7484E2EC9AABA00F841DB /* BoringNotchXPCHelper */,
 			);
 		};
 /* End PBXProject section */
@@ -634,8 +520,6 @@
 			files = (
 				14CEF41D2C5CAED400855D72 /* Preview Assets.xcassets in Resources */,
 				14CEF41A2C5CAED400855D72 /* Assets.xcassets in Resources */,
-				112B0EB82E30DD0F00562D6C /* MediaRemoteAdapterTestClient in Resources */,
-				112B0EB92E30DD0F00562D6C /* mediaremote-adapter.pl in Resources */,
 				B17266E12C6532560031BA0D /* Localizable.xcstrings in Resources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
@@ -690,64 +574,9 @@
 /* End PBXSourcesBuildPhase section */
 
 /* Begin PBXTargetDependency section */
-		11F7485A2EC9AABA00F841DB /* PBXTargetDependency */ = {
-			isa = PBXTargetDependency;
-			target = 11F7484E2EC9AABA00F841DB /* BoringNotchXPCHelper */;
-			targetProxy = 11F748592EC9AABA00F841DB /* PBXContainerItemProxy */;
-		};
 /* End PBXTargetDependency section */
 
 /* Begin XCBuildConfiguration section */
-		11F7485E2EC9AABA00F841DB /* Debug */ = {
-			isa = XCBuildConfiguration;
-			buildSettings = {
-				CODE_SIGN_ENTITLEMENTS = BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements;
-				CODE_SIGN_IDENTITY = "Apple Development";
-				"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";
-				CODE_SIGN_STYLE = Automatic;
-				COMBINE_HIDPI_IMAGES = YES;
-				CURRENT_PROJECT_VERSION = 271;
-				DEVELOPMENT_TEAM = Q37KAF726J;
-				GENERATE_INFOPLIST_FILE = YES;
-				INFOPLIST_FILE = BoringNotchXPCHelper/Info.plist;
-				INFOPLIST_KEY_CFBundleDisplayName = BoringNotchXPCHelper;
-				INFOPLIST_KEY_NSHumanReadableCopyright = "";
-				MACOSX_DEPLOYMENT_TARGET = 14.0;
-				MARKETING_VERSION = 2.7.3;
-				PRODUCT_BUNDLE_IDENTIFIER = maxonary.boringnotch.BoringNotchXPCHelper;
-				PRODUCT_NAME = "$(TARGET_NAME)";
-				REGISTER_APP_GROUPS = YES;
-				SKIP_INSTALL = YES;
-				SWIFT_EMIT_LOC_STRINGS = YES;
-				SWIFT_VERSION = 5.0;
-			};
-			name = Debug;
-		};
-		11F7485F2EC9AABA00F841DB /* Release */ = {
-			isa = XCBuildConfiguration;
-			buildSettings = {
-				CODE_SIGN_ENTITLEMENTS = BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements;
-				CODE_SIGN_IDENTITY = "Apple Development";
-				"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";
-				CODE_SIGN_STYLE = Automatic;
-				COMBINE_HIDPI_IMAGES = YES;
-				CURRENT_PROJECT_VERSION = 271;
-				DEVELOPMENT_TEAM = Q37KAF726J;
-				GENERATE_INFOPLIST_FILE = YES;
-				INFOPLIST_FILE = BoringNotchXPCHelper/Info.plist;
-				INFOPLIST_KEY_CFBundleDisplayName = BoringNotchXPCHelper;
-				INFOPLIST_KEY_NSHumanReadableCopyright = "";
-				MACOSX_DEPLOYMENT_TARGET = 14.0;
-				MARKETING_VERSION = 2.7.3;
-				PRODUCT_BUNDLE_IDENTIFIER = maxonary.boringnotch.BoringNotchXPCHelper;
-				PRODUCT_NAME = "$(TARGET_NAME)";
-				REGISTER_APP_GROUPS = YES;
-				SKIP_INSTALL = YES;
-				SWIFT_EMIT_LOC_STRINGS = YES;
-				SWIFT_VERSION = 5.0;
-			};
-			name = Release;
-		};
 		14CEF41F2C5CAED400855D72 /* Debug */ = {
 			isa = XCBuildConfiguration;
 			buildSettings = {
@@ -894,7 +723,6 @@
 				ENABLE_USER_SCRIPT_SANDBOXING = YES;
 				FRAMEWORK_SEARCH_PATHS = (
 					"$(inherited)",
-					"$(PROJECT_DIR)/mediaremote-adapter",
 				);
 				GENERATE_INFOPLIST_FILE = YES;
 				INFOPLIST_FILE = boringNotch/Info.plist;
@@ -947,7 +775,6 @@
 				ENABLE_PREVIEWS = YES;
 				FRAMEWORK_SEARCH_PATHS = (
 					"$(inherited)",
-					"$(PROJECT_DIR)/mediaremote-adapter",
 				);
 				GENERATE_INFOPLIST_FILE = YES;
 				INFOPLIST_FILE = boringNotch/Info.plist;
@@ -982,15 +809,6 @@
 /* End XCBuildConfiguration section */
 
 /* Begin XCConfigurationList section */
-		11F7485D2EC9AABA00F841DB /* Build configuration list for PBXNativeTarget "BoringNotchXPCHelper" */ = {
-			isa = XCConfigurationList;
-			buildConfigurations = (
-				11F7485E2EC9AABA00F841DB /* Debug */,
-				11F7485F2EC9AABA00F841DB /* Release */,
-			);
-			defaultConfigurationIsVisible = 0;
-			defaultConfigurationName = Release;
-		};
 		14CEF40D2C5CAED200855D72 /* Build configuration list for PBXProject "boringNotch" */ = {
 			isa = XCConfigurationList;
 			buildConfigurations = (
@@ -1012,78 +830,6 @@
 /* End XCConfigurationList section */
 
 /* Begin XCRemoteSwiftPackageReference section */
-		111BE95B2ECD71E10079DD4E /* XCRemoteSwiftPackageReference "AsyncXPCConnection" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/ChimeHQ/AsyncXPCConnection";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 1.3.0;
-			};
-		};
-		111BEA6D2ED166E20079DD4E /* XCRemoteSwiftPackageReference "MacroVisionKit" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/TheBoredTeam/MacroVisionKit";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 0.2.0;
-			};
-		};
-		1194E8832EA57D23009C82D6 /* XCRemoteSwiftPackageReference "SkyLightWindow" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/Lakr233/SkyLightWindow";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 1.0.0;
-			};
-		};
-		11F748712EC9DA9300F841DB /* XCRemoteSwiftPackageReference "lottie-spm" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/airbnb/lottie-spm.git";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 4.5.2;
-			};
-		};
-		14D032182C68F32E0096E6A1 /* XCRemoteSwiftPackageReference "LaunchAtLogin-Modern" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/sindresorhus/LaunchAtLogin-Modern";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 1.1.0;
-			};
-		};
-		14D0321B2C68F3350096E6A1 /* XCRemoteSwiftPackageReference "Sparkle" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/sparkle-project/Sparkle";
-			requirement = {
-				kind = exactVersion;
-				version = 2.9.1;
-			};
-		};
-		9A987A0E2C73CA8D005CA465 /* XCRemoteSwiftPackageReference "swift-collections" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/apple/swift-collections.git";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 1.1.2;
-			};
-		};
-		9A987A112C73CAA1005CA465 /* XCRemoteSwiftPackageReference "Pow" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/EmergeTools/Pow";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 1.0.4;
-			};
-		};
-		B1628B902CC260C0003D8DF3 /* XCRemoteSwiftPackageReference "swiftui-introspect" */ = {
-			isa = XCRemoteSwiftPackageReference;
-			repositoryURL = "https://github.com/siteline/swiftui-introspect";
-			requirement = {
-				kind = upToNextMajorVersion;
-				minimumVersion = 1.3.0;
-			};
-		};
 		B18654372C6F4990000B926A /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */ = {
 			isa = XCRemoteSwiftPackageReference;
 			repositoryURL = "https://github.com/sindresorhus/KeyboardShortcuts";
@@ -1103,54 +849,6 @@
 /* End XCRemoteSwiftPackageReference section */
 
 /* Begin XCSwiftPackageProductDependency section */
-		111BE95C2ECD71E10079DD4E /* AsyncXPCConnection */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 111BE95B2ECD71E10079DD4E /* XCRemoteSwiftPackageReference "AsyncXPCConnection" */;
-			productName = AsyncXPCConnection;
-		};
-		111BEA502ECFBF7F0079DD4E /* MacroVisionKit */ = {
-			isa = XCSwiftPackageProductDependency;
-			productName = MacroVisionKit;
-		};
-		111BEA5E2ED07A340079DD4E /* MacroVisionKit */ = {
-			isa = XCSwiftPackageProductDependency;
-			productName = MacroVisionKit;
-		};
-		111BEA6E2ED166E20079DD4E /* MacroVisionKit */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 111BEA6D2ED166E20079DD4E /* XCRemoteSwiftPackageReference "MacroVisionKit" */;
-			productName = MacroVisionKit;
-		};
-		1194E8842EA57D23009C82D6 /* SkyLightWindow */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 1194E8832EA57D23009C82D6 /* XCRemoteSwiftPackageReference "SkyLightWindow" */;
-			productName = SkyLightWindow;
-		};
-		11F748722EC9DA9300F841DB /* Lottie */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 11F748712EC9DA9300F841DB /* XCRemoteSwiftPackageReference "lottie-spm" */;
-			productName = Lottie;
-		};
-		14D032192C68F32E0096E6A1 /* LaunchAtLogin */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 14D032182C68F32E0096E6A1 /* XCRemoteSwiftPackageReference "LaunchAtLogin-Modern" */;
-			productName = LaunchAtLogin;
-		};
-		14D0321C2C68F3350096E6A1 /* Sparkle */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 14D0321B2C68F3350096E6A1 /* XCRemoteSwiftPackageReference "Sparkle" */;
-			productName = Sparkle;
-		};
-		9A987A0F2C73CA8D005CA465 /* Collections */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = 9A987A0E2C73CA8D005CA465 /* XCRemoteSwiftPackageReference "swift-collections" */;
-			productName = Collections;
-		};
-		B1628B912CC260C0003D8DF3 /* SwiftUIIntrospect */ = {
-			isa = XCSwiftPackageProductDependency;
-			package = B1628B902CC260C0003D8DF3 /* XCRemoteSwiftPackageReference "swiftui-introspect" */;
-			productName = SwiftUIIntrospect;
-		};
 		B18654382C6F4990000B926A /* KeyboardShortcuts */ = {
 			isa = XCSwiftPackageProductDependency;
 			package = B18654372C6F4990000B926A /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */;
diff --git a/mediaremote-adapter/MediaRemoteAdapter.framework/MediaRemoteAdapter b/mediaremote-adapter/MediaRemoteAdapter.framework/MediaRemoteAdapter
deleted file mode 120000
index 65b3513..0000000
--- a/mediaremote-adapter/MediaRemoteAdapter.framework/MediaRemoteAdapter
+++ /dev/null
@@ -1 +0,0 @@
-Versions/Current/MediaRemoteAdapter
\ No newline at end of file
diff --git a/mediaremote-adapter/MediaRemoteAdapter.framework/Resources b/mediaremote-adapter/MediaRemoteAdapter.framework/Resources
deleted file mode 120000
index 953ee36..0000000
--- a/mediaremote-adapter/MediaRemoteAdapter.framework/Resources
+++ /dev/null
@@ -1 +0,0 @@
-Versions/Current/Resources
\ No newline at end of file
diff --git a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter b/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
deleted file mode 100755
index b717eb0..0000000
Binary files a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter and /dev/null differ
diff --git a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/Resources/Info.plist b/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/Resources/Info.plist
deleted file mode 100644
index bf2b7b1..0000000
--- a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/Resources/Info.plist
+++ /dev/null
@@ -1,28 +0,0 @@
-<?xml version="1.0" encoding="UTF-8"?>
-<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
-<plist version="1.0">
-<dict>
-	<key>CFBundleDevelopmentRegion</key>
-	<string>English</string>
-	<key>CFBundleExecutable</key>
-	<string>MediaRemoteAdapter</string>
-	<key>CFBundleIconFile</key>
-	<string></string>
-	<key>CFBundleIdentifier</key>
-	<string>com.vandenbe.MediaRemoteAdapter</string>
-	<key>CFBundleInfoDictionaryVersion</key>
-	<string>6.0</string>
-	<key>CFBundleName</key>
-	<string>MediaRemoteAdapter</string>
-	<key>CFBundlePackageType</key>
-	<string>FMWK</string>
-	<key>CFBundleSignature</key>
-	<string>????</string>
-	<key>CFBundleVersion</key>
-	<string>0.1.0</string>
-	<key>CFBundleShortVersionString</key>
-	<string>0.1</string>
-	<key>CSResourcesFileMapped</key>
-	<true/>
-</dict>
-</plist>
diff --git a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/_CodeSignature/CodeResources b/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/_CodeSignature/CodeResources
deleted file mode 100644
index 16ea63b..0000000
--- a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/_CodeSignature/CodeResources
+++ /dev/null
@@ -1,128 +0,0 @@
-<?xml version="1.0" encoding="UTF-8"?>
-<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
-<plist version="1.0">
-<dict>
-	<key>files</key>
-	<dict>
-		<key>Resources/Info.plist</key>
-		<data>
-		M6AF1VWVJ1A/DSliCSjg170FqsY=
-		</data>
-	</dict>
-	<key>files2</key>
-	<dict>
-		<key>Resources/Info.plist</key>
-		<dict>
-			<key>hash2</key>
-			<data>
-			z3yWmTAqjdrPJEZUQ+t6AVPhw0e/I8PAiVr0HIU2ivg=
-			</data>
-		</dict>
-	</dict>
-	<key>rules</key>
-	<dict>
-		<key>^Resources/</key>
-		<true/>
-		<key>^Resources/.*\.lproj/</key>
-		<dict>
-			<key>optional</key>
-			<true/>
-			<key>weight</key>
-			<real>1000</real>
-		</dict>
-		<key>^Resources/.*\.lproj/locversion.plist$</key>
-		<dict>
-			<key>omit</key>
-			<true/>
-			<key>weight</key>
-			<real>1100</real>
-		</dict>
-		<key>^Resources/Base\.lproj/</key>
-		<dict>
-			<key>weight</key>
-			<real>1010</real>
-		</dict>
-		<key>^version.plist$</key>
-		<true/>
-	</dict>
-	<key>rules2</key>
-	<dict>
-		<key>.*\.dSYM($|/)</key>
-		<dict>
-			<key>weight</key>
-			<real>11</real>
-		</dict>
-		<key>^(.*/)?\.DS_Store$</key>
-		<dict>
-			<key>omit</key>
-			<true/>
-			<key>weight</key>
-			<real>2000</real>
-		</dict>
-		<key>^(Frameworks|SharedFrameworks|PlugIns|Plug-ins|XPCServices|Helpers|MacOS|Library/(Automator|Spotlight|LoginItems))/</key>
-		<dict>
-			<key>nested</key>
-			<true/>
-			<key>weight</key>
-			<real>10</real>
-		</dict>
-		<key>^.*</key>
-		<true/>
-		<key>^Info\.plist$</key>
-		<dict>
-			<key>omit</key>
-			<true/>
-			<key>weight</key>
-			<real>20</real>
-		</dict>
-		<key>^PkgInfo$</key>
-		<dict>
-			<key>omit</key>
-			<true/>
-			<key>weight</key>
-			<real>20</real>
-		</dict>
-		<key>^Resources/</key>
-		<dict>
-			<key>weight</key>
-			<real>20</real>
-		</dict>
-		<key>^Resources/.*\.lproj/</key>
-		<dict>
-			<key>optional</key>
-			<true/>
-			<key>weight</key>
-			<real>1000</real>
-		</dict>
-		<key>^Resources/.*\.lproj/locversion.plist$</key>
-		<dict>
-			<key>omit</key>
-			<true/>
-			<key>weight</key>
-			<real>1100</real>
-		</dict>
-		<key>^Resources/Base\.lproj/</key>
-		<dict>
-			<key>weight</key>
-			<real>1010</real>
-		</dict>
-		<key>^[^/]+$</key>
-		<dict>
-			<key>nested</key>
-			<true/>
-			<key>weight</key>
-			<real>10</real>
-		</dict>
-		<key>^embedded\.provisionprofile$</key>
-		<dict>
-			<key>weight</key>
-			<real>20</real>
-		</dict>
-		<key>^version\.plist$</key>
-		<dict>
-			<key>weight</key>
-			<real>20</real>
-		</dict>
-	</dict>
-</dict>
-</plist>
diff --git a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/Current b/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/Current
deleted file mode 120000
index 8c7e5a6..0000000
--- a/mediaremote-adapter/MediaRemoteAdapter.framework/Versions/Current
+++ /dev/null
@@ -1 +0,0 @@
-A
\ No newline at end of file
diff --git a/mediaremote-adapter/MediaRemoteAdapterTestClient b/mediaremote-adapter/MediaRemoteAdapterTestClient
deleted file mode 100755
index 5cf79eb..0000000
Binary files a/mediaremote-adapter/MediaRemoteAdapterTestClient and /dev/null differ
diff --git a/mediaremote-adapter/mediaremote-adapter.pl b/mediaremote-adapter/mediaremote-adapter.pl
deleted file mode 100755
index 7ff9017..0000000
--- a/mediaremote-adapter/mediaremote-adapter.pl
+++ /dev/null
@@ -1,268 +0,0 @@
-#!/usr/bin/perl
-# Copyright (c) 2025 Jonas van den Berg
-# This file is licensed under the BSD 3-Clause License.
-
-# For usage information read below or run the script without arguments.
-
-use strict;
-use warnings;
-use DynaLoader;
-use File::Spec;
-use File::Basename;
-
-sub print_help() {
-  print <<'HELP';
-Usage:
-  mediaremote-adapter.pl FRAMEWORK_PATH [TEST_CLIENT_PATH]
-                         [FUNCTION [PARAMS|OPTIONS...]]
-
-FRAMEWORK_PATH:
-  Absolute path to the MediaRemoteAdapter.framework directory
-
-TEST_CLIENT_PATH: (optional)
-  Absolute path to the MediaRemoteAdapterTestClient executable. Only for "test"
-
-FUNCTION:
-  stream   Streams now playing information (as diff by default)
-  get      Prints now playing information once with all available metadata
-  send     Sends a command to the now playing application
-  seek     Seeks to a specific timeline position
-  shuffle  Sets the shuffle mode
-  repeat   Sets the repeat mode
-  speed    Sets the playback speed
-  test     Tests if the adapter is entitled to use the MediaRemote framework.
-           An exit code other than 0 indicates the adapter is non-functional
-
-PARAMS:
-  send(command)
-    command: The MRCommand ID as a number (e.g. kMRPlay = 0)
-  seek(position)
-    position: The timeline position in microseconds
-  shuffle(mode)
-    mode: The shuffle mode
-  repeat(mode)
-    mode: The repeat mode
-  speed(speed)
-    speed: The playback speed
-
-OPTIONS:
-  get
-    --now: Adds an "elapsedTimeNow" key with an estimation of the current
-      elapsed playback time. This estimation may be off by up to a second.
-      To determine a more accurate time without polling "get" continuously,
-      calculate it using the "elapsedTime" and "timestamp" keys. "elapsedTime"
-      contains the elapsed time at the time that is stored in "timestamp".
-  stream
-    --no-diff: Disable diffing and always dump all metadata
-    --debounce=N: Delay in milliseconds to prevent spam (0 by default)
-  get, stream
-    --micros: Replaces the following time keys with microsecond equivalents
-      "duration" -> "durationMicros"
-      "elapsedTime" -> "elapsedTimeMicros"
-      "elapsedTimeNow" -> "elapsedTimeNowMicros"
-      "timestamp" -> "timestampEpochMicros" (converted to epoch time)
-    --human-readable, -h: Makes values human-readable. Use only for debugging.
-      The JSON output is pretty-printed and the following keys are adapted:
-      "artworkData" -> Binary data is truncated to a shorter representation
-
-Examples (script name and framework path omitted):
-  stream --no-diff --debounce=100
-  send 2    # Toggles play/pause in the media player (kMRATogglePlayPause)
-  repeat 3  # Sets the repeat mode to "playlist" (kMRARepeatModePlaylist)
-
-HELP
-  exit 0;
-}
-
-if (!defined $ARGV[1]) {
-  print_help();
-}
-
-sub fail {
-  my ($error) = @_;
-  print STDERR "$error\n";
-  exit 1;
-}
-
-fail "Framework path not provided" unless @ARGV >= 1;
-
-my $framework_path = shift @ARGV;
-
-# Optionally accept MEDIAREMOTEADAPTER_TEST_CLIENT_PATH path as second argument
-my $maybe_helper_path = $ARGV[0] // '';
-if ($maybe_helper_path =~ m{/}){
-  my $helper_path = shift @ARGV;
-  $ENV{MEDIAREMOTEADAPTER_TEST_CLIENT_PATH} = $helper_path;
-}
-
-if (!defined $ARGV[0]) {
-  print_help();
-}
-
-my $framework_basename = File::Basename::basename($framework_path);
-fail "Provided path is not a framework: $framework_path"
-  unless $framework_basename =~ s/\.framework$//;
-
-my $framework = File::Spec->catfile($framework_path, $framework_basename);
-fail "Framework not found at $framework" unless -e $framework;
-
-my $handle = DynaLoader::dl_load_file($framework, 0)
-  or fail "Failed to load framework: $framework";
-my $function_name = shift @ARGV or fail "Missing function name";
-fail "Invalid function name: '$function_name'"
-  unless $function_name eq "stream"
-  || $function_name eq "get"
-  || $function_name eq "send"
-  || $function_name eq "seek"
-  || $function_name eq "shuffle"
-  || $function_name eq "repeat"
-  || $function_name eq "speed"
-  || $function_name eq "test";
-
-sub parse_options {
-  my ($start_index) = @_;
-  my %arg_map;
-  my $i = $start_index;
-  while ($i <= $#ARGV) {
-    my $arg = $ARGV[$i];
-    if ($arg =~ /^--([a-z\\-]+)(?:=(.*))?$/) {
-      my $key = $1;
-      my $value = defined $2 ? $2 : undef;
-      $arg_map{$key} = $value;
-      splice @ARGV, $i, 1;
-    }
-    elsif ($arg =~ /^-([a-zA-Z]+)$/) {
-      my @flags = split //, $1;
-      $arg_map{$_} = undef for @flags;
-      splice @ARGV, $i, 1;
-    }
-    else {
-      $i++;
-    }
-  }
-  return \%arg_map;
-}
-
-sub env_func {
-  my $symbol_name = shift;
-  return "${symbol_name}_env";
-}
-
-sub set_env_param {
-  my ($func, $index, $name, $value) = @_;
-  $ENV{"MEDIAREMOTEADAPTER_PARAM_${func}_${index}_${name}"} = "$value";
-}
-
-sub set_env_option_unsafe {
-  my ($name, $value) = @_;
-  $name =~ s/-/_/g;
-  $ENV{"MEDIAREMOTEADAPTER_OPTION_${name}"} = defined $value ? "$value" : "";
-}
-
-sub set_env_option {
-  my ($options, $key) = @_;
-  my $value = $options->{$key};
-  if (defined $value) {
-    fail "Unexpected value for option '$key'";
-  }
-  set_env_option_unsafe($key, $value);
-}
-
-sub set_env_option_value {
-  my ($options, $key) = @_;
-  my $value = $options->{$key};
-  if (!defined $value) {
-    fail "Missing value for option '$key'";
-  }
-  set_env_option_unsafe($key, $value);
-}
-
-my $symbol_name = "adapter_$function_name";
-if ($function_name eq "send") {
-  my $id = shift @ARGV;
-  fail "Missing ID for '$function_name' command" unless defined $id;
-  set_env_param($symbol_name, 0, "command", "$id");
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "stream") {
-  my $options = parse_options(0);
-  foreach my $key (keys %{$options}) {
-    if ($key eq "no-diff") {
-      set_env_option($options, $key);
-    }
-    elsif ($key eq "debounce") {
-      set_env_option_value($options, $key);
-    }
-    elsif ($key eq "micros") {
-      set_env_option($options, $key);
-    }
-    elsif ($key eq "human-readable" || $key eq "h") {
-      set_env_option($options, "human-readable");
-    }
-    else {
-      fail "Unrecognized option '$key'";
-    }
-  }
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "get") {
-  my $options = parse_options(0);
-  foreach my $key (keys %{$options}) {
-    if ($key eq "micros") {
-      set_env_option($options, $key);
-    }
-    elsif ($key eq "human-readable" || $key eq "h") {
-      set_env_option($options, "human-readable");
-    }
-    elsif ($key eq "now") {
-      set_env_option($options, $key);
-    }
-    else {
-      fail "Unrecognized option '$key'";
-    }
-  }
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "seek") {
-  my $position = shift @ARGV;
-  fail "Missing position for '$function_name' command" unless defined $position;
-  set_env_param($symbol_name, 0, "position", "$position");
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "shuffle") {
-  my $mode = shift @ARGV;
-  fail "Missing mode for '$function_name' command" unless defined $mode;
-  set_env_param($symbol_name, 0, "mode", "$mode");
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "repeat") {
-  my $mode = shift @ARGV;
-  fail "Missing mode for '$function_name' command" unless defined $mode;
-  set_env_param($symbol_name, 0, "mode", "$mode");
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "speed") {
-  my $speed = shift @ARGV;
-  fail "Missing speed for '$function_name' command" unless defined $speed;
-  set_env_param($symbol_name, 0, "speed", "$speed");
-  $symbol_name = env_func($symbol_name);
-}
-elsif ($function_name eq "test") {
-  $symbol_name = "adapter_test";
-}
-
-if (defined shift @ARGV) {
-  fail "Too many arguments";
-}
-
-my $symbol = DynaLoader::dl_find_symbol($handle, "$symbol_name")
-  or fail "Symbol '$symbol_name' not found in $framework";
-DynaLoader::dl_install_xsub("main::$function_name", $symbol);
-
-eval {
-  no strict "refs";
-  &{"main::$function_name"}();
-};
-if ($@) {
-  fail "Error executing $function_name: $@";
-}
diff --git a/updater/appcast.xml b/updater/appcast.xml
deleted file mode 100644
index 062efa1..0000000
--- a/updater/appcast.xml
+++ /dev/null
@@ -1,495 +0,0 @@
-<?xml version="1.0" standalone="yes"?>
-<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
-    <channel>
-        <item>
-            <title>2.7.3</title>
-            <pubDate>Mon, 24 Nov 2025 08:07:37 +0000</pubDate>
-            <link>https://github.com/TheBoredTeam/boring.notch/releases</link>
-            <sparkle:version>271</sparkle:version>
-            <sparkle:shortVersionString>2.7.3</sparkle:shortVersionString>
-            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
-            <description><![CDATA[<h2>🚀 v2.7.3— Flying Rabbit 🐇🪽</h2>
-<h3> Fixes: </h3>
-<ul>
-    <li><strong>Fixed regression in album artwork view<strong></li>
-    <li><strong>Fixed HUD for older versions of macOS<strong></li>
-    <li><strong>Added volume feedback for HUD when enabled in macOS settings<strong></li>
-    <li><strong>Added option to display percentages for HUDs<strong></li>
-    <li><strong>Created a new custom HUD for when the notch is open<strong></li>
-    <li><strong>Fixed NowPlaying controller launching Apple Music by itself<strong></li>
-    <li><strong>Improved responsiveness of volume slider<strong></li>
-    <li><strong>Improved onboarding experience<strong></li>
-</ul>
-
-<h2>🚀 v2.7 — Flying Rabbit 🐇🪽</h2>
-<h3>Shelf 2.0</h3>
-<p>Major update with improved stability, enhanced functionality, and a refreshed UI.</p>
-<ul>
-    <li><strong>New Context Menu</strong> – Right-click in the notch to access various file actions</li>
-    <li><strong>Multi-Item Selection</strong> – Hold <kbd>⇧</kbd> for consecutive or <kbd>⌘</kbd> for non-consecutive
-        selections</li>
-    <li><strong>Double-Click to Open</strong> – Double-click on selected files to open them</li>
-    <li><strong>Move by Default</strong> – Dragging files now moves them; hold <kbd>⌥</kbd> to copy</li>
-    <li><strong>Simplified Removal</strong> – Files can be removed after dragging (configurable in Settings)</li>
-    <li><strong>Expanded Drag Detection</strong> – The shelf opens when files are dragged into the notch area</li>
-    <li><strong>Expanded Sharing</strong> – More sharing services available in Settings</li>
-</ul>
-<h3>Complete HUD Replacement</h3>
-<p>Full support for macOS system controls:</p>
-<ul>
-    <li><strong>Screen Brightness</strong>, <strong>Keyboard Brightness</strong>, and <strong>System Volume</strong>
-    </li>
-    <li><strong>Keyboard Brightness Controls:</strong> <kbd>⌘ + Brightness Down/Up</kbd></li>
-    <li><strong>Option (<kbd>⌥</kbd>)</strong> – Triggers alternate action configured in Settings</li>
-    <li><strong>Option + Shift (<kbd>⌥</kbd> <kbd>⇧</kbd>)</strong> – Adjustments in smaller increments</li>
-</ul>
-<h3>Music Enhancements</h3>
-<ul>
-    <li><strong>YouTube Music Support Rewritten</strong> – Now powered by WebSocket for better accuracy and performance
-    </li>
-</ul>
-<blockquote>
-    <p><strong>Note:</strong> Requires version <strong>3.11+</strong> of <a
-            href="https://github.com/pear-devs/pear-desktop">YouTube Music/Pear Desktop</a>. Updating is strongly
-        recommended.</p>
-</blockquote>
-<ul>
-    <li><strong>Redesigned Music Controls</strong> – Fully customizable:
-        <ul>
-            <li>Skip backward/forward by 15 seconds</li>
-            <li>Adjust music app volume</li>
-            <li>Mark favorite songs  (Apple Music &amp;
-        YouTube MusiZ</li>
-            <li>Rearrange or remove existing controls</li>
-        </ul>
-    </li>
-    <li><strong>Optimized Spotify Artwork Cache</strong> – Significantly reduced storage usage with automatic cleanup
-    </li>
-    <li><strong>Lyrics (Beta)</strong> – View synchronized lyrics for currently playing songs</li>
-</ul>
-<h3>Calendar Improvements</h3>
-<ul>
-    <li>New setting to hide all-day events</li>
-    <li>New setting to auto-scroll to next current or upcoming event</li>
-    <li>New setting to prevent truncation of long event names</li>
-</ul>
-<h3>Improved Window Behavior</h3>
-<ul>
-    <li><strong>Enhanced Fullscreen Detection</strong> – Significantly more reliable</li>
-    <li><strong>Better Edge Handling</strong> – Fixed top edge cursor issues</li>
-    <li><strong>Reduced Title Bar Interference</strong> – Less intrusive during fullscreen</li>
-    <li><strong>Lock Screen Support</strong> – Notch now appears on lock screen</li>
-    <li><strong>Screenshot Privacy</strong> – Hide notch from screenshots and recordings</li>
-</ul>
-<h3>Advanced Settings</h3>
-<ul>
-    <li>Cleaner interface with lesser-used settings moved to Advanced</li>
-    <li>Accent color override reintroduced</li>
-</ul>
-<h3>General Enhancements</h3>
-<ul>
-    <li>Numerous UI fixes and polish</li>
-    <li>Localization updates across all supported languages</li>
-</ul>
-<hr>
-<h2>👋 New Contributors</h2>
-<p>@azhao4227 · @bueckerlars · @TheMalenia · @Corentin132 · @SupKittyMeow · @M7T5M3P · @charshith · @Decryptu ·
-    @EnesCinr · @lambegraham</p>
-<hr>
-<h3>📄 Full Changelog</h3>
-<p><a href="https://github.com/TheBoredTeam/boring.notch/compare/v2.7-rc.3...v2.7">Compare v2.7-rc.3 → v2.7</a></p>]]></description>
-            <enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/v2.7.3/boringNotch.dmg" length="9727030" type="application/octet-stream" sparkle:edSignature="gl1LSheePaR/h57sppaFMnIPGyX2AC3jITvMZzmYc95wiuuDAKLdSSjKAiUqDSvHqW8hx/fgCbS7878yUH3JCQ=="/>
-        </item>
-        <item>
-            <title>2.7.2</title>
-            <pubDate>Sat, 22 Nov 2025 22:40:29 +0000</pubDate>
-            <link>https://github.com/TheBoredTeam/boring.notch/releases</link>
-            <sparkle:version>262</sparkle:version>
-            <sparkle:shortVersionString>2.7.2</sparkle:shortVersionString>
-            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
-            <description><![CDATA[<h2>🚀 v2.7.2— Flying Rabbit 🐇🪽</h2>
-<h3> Fixes: </h3>
-<ul>
-    <li><strong>Fixed default sneak peak<strong></li>
-</ul>
-<h2>🚀 v2.7.1 — Flying Rabbit 🐇🪽</h2>
-<h3> Fixes: </h3>
-<ul>
-    <li><strong>Fixed update signing</strong></li>
-    <li><strong>Improved animations</strong></li>
-     <li><strong>Fixed shadow clipping</strong></li>
-     <h3>📄 Full Changelog</h3>
-      <p><a href="https://github.com/TheBoredTeam/boring.notch/compare/v2.7...v2.7.1">Compare v2.7 → v2.7.1</a></p>
-</ul>
-
-<h2>🚀 v2.7 — Flying Rabbit 🐇🪽</h2>
-<h3>Shelf 2.0</h3>
-<p>Major update with improved stability, enhanced functionality, and a refreshed UI.</p>
-<ul>
-    <li><strong>New Context Menu</strong> – Right-click in the notch to access various file actions</li>
-    <li><strong>Multi-Item Selection</strong> – Hold <kbd>⇧</kbd> for consecutive or <kbd>⌘</kbd> for non-consecutive
-        selections</li>
-    <li><strong>Double-Click to Open</strong> – Double-click on selected files to open them</li>
-    <li><strong>Move by Default</strong> – Dragging files now moves them; hold <kbd>⌥</kbd> to copy</li>
-    <li><strong>Simplified Removal</strong> – Files can be removed after dragging (configurable in Settings)</li>
-    <li><strong>Expanded Drag Detection</strong> – The shelf opens when files are dragged into the notch area</li>
-    <li><strong>Expanded Sharing</strong> – More sharing services available in Settings</li>
-</ul>
-<h3>Complete HUD Replacement</h3>
-<p>Full support for macOS system controls:</p>
-<ul>
-    <li><strong>Screen Brightness</strong>, <strong>Keyboard Brightness</strong>, and <strong>System Volume</strong>
-    </li>
-    <li><strong>Keyboard Brightness Controls:</strong> <kbd>⌘ + Brightness Down/Up</kbd></li>
-    <li><strong>Option (<kbd>⌥</kbd>)</strong> – Triggers alternate action configured in Settings</li>
-    <li><strong>Option + Shift (<kbd>⌥</kbd> <kbd>⇧</kbd>)</strong> – Adjustments in smaller increments</li>
-</ul>
-<h3>Music Enhancements</h3>
-<ul>
-    <li><strong>YouTube Music Support Rewritten</strong> – Now powered by WebSocket for better accuracy and performance
-    </li>
-</ul>
-<blockquote>
-    <p><strong>Note:</strong> Requires version <strong>3.11+</strong> of <a
-            href="https://github.com/pear-devs/pear-desktop">YouTube Music/Pear Desktop</a>. Updating is strongly
-        recommended.</p>
-</blockquote>
-<ul>
-    <li><strong>Redesigned Music Controls</strong> – Fully customizable:
-        <ul>
-            <li>Skip backward/forward by 15 seconds</li>
-            <li>Adjust music app volume</li>
-            <li>Mark favorite songs  (Apple Music &amp;
-        YouTube MusiZ</li>
-            <li>Rearrange or remove existing controls</li>
-        </ul>
-    </li>
-    <li><strong>Optimized Spotify Artwork Cache</strong> – Significantly reduced storage usage with automatic cleanup
-    </li>
-    <li><strong>Lyrics (Beta)</strong> – View synchronized lyrics for currently playing songs</li>
-</ul>
-<h3>Calendar Improvements</h3>
-<ul>
-    <li>New setting to hide all-day events</li>
-    <li>New setting to auto-scroll to next current or upcoming event</li>
-    <li>New setting to prevent truncation of long event names</li>
-</ul>
-<h3>Improved Window Behavior</h3>
-<ul>
-    <li><strong>Enhanced Fullscreen Detection</strong> – Significantly more reliable</li>
-    <li><strong>Better Edge Handling</strong> – Fixed top edge cursor issues</li>
-    <li><strong>Reduced Title Bar Interference</strong> – Less intrusive during fullscreen</li>
-    <li><strong>Lock Screen Support</strong> – Notch now appears on lock screen</li>
-    <li><strong>Screenshot Privacy</strong> – Hide notch from screenshots and recordings</li>
-</ul>
-<h3>Advanced Settings</h3>
-<ul>
-    <li>Cleaner interface with lesser-used settings moved to Advanced</li>
-    <li>Accent color override reintroduced</li>
-</ul>
-<h3>General Enhancements</h3>
-<ul>
-    <li>Numerous UI fixes and polish</li>
-    <li>Localization updates across all supported languages</li>
-</ul>
-<hr>
-<h2>👋 New Contributors</h2>
-<p>@azhao4227 · @bueckerlars · @TheMalenia · @Corentin132 · @SupKittyMeow · @M7T5M3P · @charshith · @Decryptu ·
-    @EnesCinr · @lambegraham</p>
-<hr>
-<h3>📄 Full Changelog</h3>
-<p><a href="https://github.com/TheBoredTeam/boring.notch/compare/v2.7-rc.3...v2.7">Compare v2.7-rc.3 → v2.7</a></p>]]></description>
-            <enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/v2.7.2/boringNotch.dmg" length="9684618" type="application/octet-stream" sparkle:edSignature="8fWrEF4oezQcnF/iM9X0B4bGIe4zPnJSzpEuwq3OfyZ5TphlXf85DmRL21PWDIYuUIGuX6DaUyzv7NOB9Fk9Cg=="/>
-        </item>
-        <item>
-            <title>2.7.1</title>
-            <pubDate>Sat, 22 Nov 2025 22:14:41 +0000</pubDate>
-            <link>https://github.com/TheBoredTeam/boring.notch/releases</link>
-            <sparkle:version>260</sparkle:version>
-            <sparkle:shortVersionString>2.7.1</sparkle:shortVersionString>
-            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
-            <description><![CDATA[<h2>🚀 v2.7.1 — Flying Rabbit 🐇🪽</h2>
-<h3> Fixes: </h3>
-<ul>
-    <li><strong>Fixed update signing</strong></li>
-    <li><strong>Improved animations</strong></li>
-     <li><strong>Fixed shadow clipping</strong></li>
-     <h3>📄 Full Changelog</h3>
-      <p><a href="https://github.com/TheBoredTeam/boring.notch/compare/v2.7...v2.7.1">Compare v2.7 → v2.7.1</a></p>
-</ul>
-
-<h2>🚀 v2.7 — Flying Rabbit 🐇🪽</h2>
-<h3>Shelf 2.0</h3>
-<p>Major update with improved stability, enhanced functionality, and a refreshed UI.</p>
-<ul>
-    <li><strong>New Context Menu</strong> – Right-click in the notch to access various file actions</li>
-    <li><strong>Multi-Item Selection</strong> – Hold <kbd>⇧</kbd> for consecutive or <kbd>⌘</kbd> for non-consecutive
-        selections</li>
-    <li><strong>Double-Click to Open</strong> – Double-click on selected files to open them</li>
-    <li><strong>Move by Default</strong> – Dragging files now moves them; hold <kbd>⌥</kbd> to copy</li>
-    <li><strong>Simplified Removal</strong> – Files can be removed after dragging (configurable in Settings)</li>
-    <li><strong>Expanded Drag Detection</strong> – The shelf opens when files are dragged into the notch area</li>
-    <li><strong>Expanded Sharing</strong> – More sharing services available in Settings</li>
-</ul>
-<h3>Complete HUD Replacement</h3>
-<p>Full support for macOS system controls:</p>
-<ul>
-    <li><strong>Screen Brightness</strong>, <strong>Keyboard Brightness</strong>, and <strong>System Volume</strong>
-    </li>
-    <li><strong>Keyboard Brightness Controls:</strong> <kbd>⌘ + Brightness Down/Up</kbd></li>
-    <li><strong>Option (<kbd>⌥</kbd>)</strong> – Triggers alternate action configured in Settings</li>
-    <li><strong>Option + Shift (<kbd>⌥</kbd> <kbd>⇧</kbd>)</strong> – Adjustments in smaller increments</li>
-</ul>
-<h3>Music Enhancements</h3>
-<ul>
-    <li><strong>YouTube Music Support Rewritten</strong> – Now powered by WebSocket for better accuracy and performance
-    </li>
-</ul>
-<blockquote>
-    <p><strong>Note:</strong> Requires version <strong>3.11+</strong> of <a
-            href="https://github.com/pear-devs/pear-desktop">YouTube Music/Pear Desktop</a>. Updating is strongly
-        recommended.</p>
-</blockquote>
-<ul>
-    <li><strong>Redesigned Music Controls</strong> – Fully customizable:
-        <ul>
-            <li>Skip backward/forward by 15 seconds</li>
-            <li>Adjust music app volume</li>
-            <li>Mark favorite songs  (Apple Music &amp;
-        YouTube MusiZ</li>
-            <li>Rearrange or remove existing controls</li>
-        </ul>
-    </li>
-    <li><strong>Optimized Spotify Artwork Cache</strong> – Significantly reduced storage usage with automatic cleanup
-    </li>
-    <li><strong>Lyrics (Beta)</strong> – View synchronized lyrics for currently playing songs</li>
-</ul>
-<h3>Calendar Improvements</h3>
-<ul>
-    <li>New setting to hide all-day events</li>
-    <li>New setting to auto-scroll to next current or upcoming event</li>
-    <li>New setting to prevent truncation of long event names</li>
-</ul>
-<h3>Improved Window Behavior</h3>
-<ul>
-    <li><strong>Enhanced Fullscreen Detection</strong> – Significantly more reliable</li>
-    <li><strong>Better Edge Handling</strong> – Fixed top edge cursor issues</li>
-    <li><strong>Reduced Title Bar Interference</strong> – Less intrusive during fullscreen</li>
-    <li><strong>Lock Screen Support</strong> – Notch now appears on lock screen</li>
-    <li><strong>Screenshot Privacy</strong> – Hide notch from screenshots and recordings</li>
-</ul>
-<h3>Advanced Settings</h3>
-<ul>
-    <li>Cleaner interface with lesser-used settings moved to Advanced</li>
-    <li>Accent color override reintroduced</li>
-</ul>
-<h3>General Enhancements</h3>
-<ul>
-    <li>Numerous UI fixes and polish</li>
-    <li>Localization updates across all supported languages</li>
-</ul>
-<hr>
-<h2>👋 New Contributors</h2>
-<p>@azhao4227 · @bueckerlars · @TheMalenia · @Corentin132 · @SupKittyMeow · @M7T5M3P · @charshith · @Decryptu ·
-    @EnesCinr · @lambegraham</p>
-<hr>
-<h3>📄 Full Changelog</h3>
-<p><a href="https://github.com/TheBoredTeam/boring.notch/compare/v2.7-rc.3...v2.7">Compare v2.7-rc.3 → v2.7</a></p>]]></description>
-            <enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/v2.7.1/boringNotch.dmg" length="9684624" type="application/octet-stream" sparkle:edSignature="d+5NbhE7/CjLdcwOyPmxKSC7r3BAFG1Fe6t9voGwT/w6yUfaTMn6d30pUFhPqWihWFhT4cwtPOPztzEV35XBAQ=="/>
-        </item>
-        <item>
-            <title>2.7-rc.1 Flying Rabbit 🐇🪽</title>
-            <pubDate>Sun, 27 Jul 2025 09:41:40 +0530</pubDate>
-            <sparkle:version>2.7-rc.1+3</sparkle:version>
-            <sparkle:shortVersionString>2.7-rc.1</sparkle:shortVersionString>
-            <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
-            <description><![CDATA[
-                    <div>
-                        <h1>🐇 boring.notch v2.7 – Flying Rabbit RC 1</h1>
-                        <p>Release Candidate - July 27, 2025</p>
-                            <h2>✨ What's New & Improved</h2>
-                            <ul>
-                            <li><b>🛠️ Fixed hanging issues:</b> Resolved stability concerns by addressing test instability. (by @Alexander5015)</li>
-                            <li><b>📅 Calendar Settings Resolved:</b> Calendar settings now update correctly with authorization; proper show/hide.</li>
-                            <li><b>🎵 YouTube Music Controller:</b>
-                                <ul>
-                                <li>Improved shuffle and repeat UX, beta features for shuffle/repeat now available.</li>
-                                <li>Fixed seek control bugs and added forced polling.</li>
-                                </ul>
-                                (by @pranav1st & @Alexander5015)
-                            </li>
-                            <li><b>🔲 MediaRemoteAdapter.Framework updated</b></li>
-                            <li><b>🔃 Button order and repeat toggle improved:</b> Better player button logic and new repeat toggle.</li>
-                            <li><b>🐞 Now Playing Controller Beta:</b> Beta enhancements and settings (known bugs remain for testing).</li>
-                            <li><b>♻️ Shuffle is now always enabled.</b></li>
-                            <li><b>💡 Refactored Shuffle & Repeat:</b> toggleShuffle/toggleRepeat refactored for improved experience.</li>
-                            </ul>
-                        <p>— The Boring Team</p>
-                    </div>
-                ]]></description>
-            <enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/v2.7-rc.1/Flying_Rabbit.dmg" length="9033202" type="application/octet-stream" sparkle:edSignature="z1SbQHDCg1D+6m811f4ubdinUiXvoYF4Ra2xlzS3NSAlUqmmIpdzCp1MHMv5J9ddlxTws3rG48OCJfZRAXHHAw=="/>
-        </item>
-        <item>
-            <title>2.7-rc.0 Flying Rabbit 🐇🪽</title>
-            <pubDate>Sat, 26 Jul 2025 12:45:19 +0530</pubDate>
-            <sparkle:version>2.7-rc.0+1</sparkle:version>
-            <sparkle:shortVersionString>2.7-rc.0</sparkle:shortVersionString>
-            <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
-            <description><![CDATA[
-                    <h1 id="-release-v2-7-flying-rabbit-rc-0-boring-notch">🎉 Release v2.7 Flying Rabbit RC 0 — Boring Notch</h1>
-                    <p>We're thrilled to announce <strong>Boring Notch v2.7: Flying Rabbit RC 0</strong>, packed with powerful new features, polish, and community contributions!</p>
-                    <h2 id="-highlights">🚀 Highlights</h2>
-                    <ul>
-                    <li><strong>🔋 Enhanced Battery Status \&amp; Charging Experience</strong>
-                    Thanks to @AlexLemus-Dev<ul>
-                    <li>More informative battery menu: percentage, max capacity, charging, low power, and status icons</li>
-                    <li>Configurable battery indicators, notifications, and display options</li>
-                    <li>Interactive battery icon with detailed info and instant System Preferences access</li>
-                    <li>Visual alignment and consistent styling (macOS-like bolt/plug icons, dark mode, etc.)</li>
-                    <li>Optimized and documented code, robust error handling, and improved performance</li>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/437">Details \&amp; Demo</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>🖥️ Fullscreen Detection \&amp; Playback Management Fixes</strong>
-                    @Alexander5015 improved reliability of media controls during fullscreen transitions<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/449">PR #449</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>🦷 Allow 0 Height Notch</strong>
-                    Now supports notches with zero height for enhanced layout flexibility<ul>
-                    <li>Thanks, @yaxarat! <a href="https://github.com/TheBoredTeam/boring.notch/pull/397">PR #397</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>🎛️ Multiple Media Controllers</strong>
-                    Control and display several media controllers at once<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/460">PR #460</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>👀 Sneak Peek \&amp; Jiggle Fixes</strong>
-                    Re-added sneak peek and improved animation stability<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/409">PR #409</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>🗓️ New Calendar Service</strong>
-                    Seamlessly integrates your calendar into Boring Notch<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/589">PR #589</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>📄 Updated LICENSE</strong>
-                    Keeping compliance and clarity up to date<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/590">PR #590</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>🆕 Onboarding \&amp; Better Settings Window</strong>
-                    Streamlined onboarding and redesigned settings for easy configuration<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/600">PR #600</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>📸 Camera Toggle Feature</strong>
-                    New camera quick toggle, privacy-first!<ul>
-                    <li>Added by @Steve-sy <a href="https://github.com/TheBoredTeam/boring.notch/pull/598">PR #598</a></li>
-                    </ul>
-                    </li>
-                    <li><strong>🎵 MediaRemote Adapter Support</strong>
-                    Improved compatibility with MediaRemote devices<ul>
-                    <li><a href="https://github.com/TheBoredTeam/boring.notch/pull/631">PR #631</a></li>
-                    </ul>
-                    </li>
-                    </ul>
-                    <h2 id="-welcoming-first-time-contributors-">🆕 Welcoming First-Time Contributors!</h2>
-                    <table>
-                    <thead>
-                    <tr>
-                    <th style="text-align:left">Contributor</th>
-                    <th style="text-align:left">PR Link</th>
-                    </tr>
-                    </thead>
-                    <tbody>
-                    <tr>
-                    <td style="text-align:left">@sancho1952007</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/431">https://github.com/TheBoredTeam/boring.notch/pull/431</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@Ein-Tim</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/405">https://github.com/TheBoredTeam/boring.notch/pull/405</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@AlexLemus-Dev</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/437">https://github.com/TheBoredTeam/boring.notch/pull/437</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@yaxarat</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/397">https://github.com/TheBoredTeam/boring.notch/pull/397</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@ShirakawaMio</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/399">https://github.com/TheBoredTeam/boring.notch/pull/399</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@divyanshu0469</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/454">https://github.com/TheBoredTeam/boring.notch/pull/454</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@oorischubert</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/409">https://github.com/TheBoredTeam/boring.notch/pull/409</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@Al3Gr</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/493">https://github.com/TheBoredTeam/boring.notch/pull/493</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@ChemicalChaos-Fabian42</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/509">https://github.com/TheBoredTeam/boring.notch/pull/509</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@Davetheword</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/501">https://github.com/TheBoredTeam/boring.notch/pull/501</a>)</td>
-                    </tr>
-                    <tr>
-                    <td style="text-align:left">@Steve-sy</td>
-                    <td style="text-align:left">(<a href="https://github.com/TheBoredTeam/boring.notch/pull/598">https://github.com/TheBoredTeam/boring.notch/pull/598</a>)</td>
-                    </tr>
-                    </tbody>
-                    </table>
-                    <h2 id="-other-improvements">🛠️ Other Improvements</h2>
-                    <ul>
-                    <li>Visual and animation refinements for battery/media indicators</li>
-                    <li>Enhanced error handling, code reorganization, and extensive documentation</li>
-                    <li>Optimizations for consistent performance across all system conditions</li>
-                    </ul>
-                    <p>Thank you 🌟 to everyone—new and returning—for their effort in making this release feature-rich, steady, and super fun!</p>
-                    <p><strong>Try Boring Notch v2.7 — Flying Rabbit RC 0 and let us know what you think!</strong></p>
-                    <p><em>— The Boring Notch Team</em></p>
-                ]]></description>
-            <enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/v2.7-rc.0/Flying_Rabbit.dmg" length="9000118" type="application/octet-stream" sparkle:edSignature="G5D2zsLFBR0Ua9b1EkLD8jjdkpMA10P1C9KmEL2Drg1WNwCnNAY+lGmljx1UQ+qDyqpjjMrOoGClevHd/276BQ=="/>
-        </item>
-        <item>
-            <title>2.6 🎉 Wolf Painting 🐺</title>
-            <pubDate>Sun, 23 Feb 2025 22:02:47 +0530</pubDate>
-            <sparkle:version>2.6+1</sparkle:version>
-            <sparkle:shortVersionString>2.6</sparkle:shortVersionString>
-            <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
-            <description><![CDATA[
-                <h1>🎉 v2.6 🚀 Wolf Painting 🐺</h1>
-                <p>We're thrilled to announce the release of Wolf Painting version 2.6! 🎊 This major update brings numerous improvements and new features that will make your experience even more enjoyable.</p><br />
-                <a href="https://github.com/TheBoredTeam/boring.notch/releases/download/wolf.painting/WolfPainting.dmg"><h1>Download from here</h1></a>
-                <h2>🤔 What's Changed? 🤓</h2>
-                <ul>
-                <li>🧠 Improved memory management and thread safety across the app</li>
-                <li>🎥 Enhanced webcam handling with better session lifecycle management</li>
-                <li>🎨 Added option to choose between classic and modern notch animations</li>
-                <li>⚡️ Improved fullscreen detection with Finder exclusion</li>
-                <li>🔄 Better hover state handling and reduced animation flicker</li>
-                <li>🔋 Enhanced power status notifications and battery indicators</li>
-                <li>⚙️ Improved screen lock and display change handling</li>
-                <li>🎵 Better music playback state tracking and elapsed time accuracy</li>
-                <li>✨ Added "Buy us a coffee" option in Welcome screen</li>
-                <li>⚠️ Added warning badges for unsupported extensions</li>
-                <li>🐛 Various bug fixes and stability improvements</li>
-                <li>For more details, check out <a href="https://theboring.name">our website</a></li>
-                </ul>
-            ]]></description>
-            <enclosure url="https://github.com/TheBoredTeam/boring.notch/releases/download/wolf.painting/WolfPainting.dmg" length="8722621" type="application/octet-stream" sparkle:edSignature="j2Wp9e23UvN7yx2NztYfGbUiKfCU4qc2xpsPwBPx/ERUz01pJTfJlf8oN0Wri8gcho42/xfcfnWNwChfMPzrCQ=="/>
-        </item>
-    </channel>
-</rss>
\ No newline at end of file
