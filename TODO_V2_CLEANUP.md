# v2 cleanup TODO

v1 took the "disable-and-replace" path rather than "delete-and-rewrite"
to ship today. The features below are still on disk and still compile,
but no live code path invokes them. The user-visible app is Nudge-only.

When time permits, delete the following from disk AND remove their
`PBXFileReference` / `PBXBuildFile` / group-children entries from
`boringNotch.xcodeproj/project.pbxproj`:

## Managers (boringNotch/managers/)
- MusicManager.swift
- CalendarManager.swift
- WebcamManager.swift
- BatteryActivityManager.swift
- BrightnessManager.swift
- VolumeManager.swift
- ImageService.swift (used by music album art)

## MediaControllers (boringNotch/MediaControllers/)
- All 4 files (AppleMusic, Spotify, YouTubeMusic, NowPlaying)

## Components (boringNotch/components/)
- Music/ (entire folder)
- Calendar/ (entire folder)
- Webcam/ (entire folder)
- Shelf/ (entire folder)
- Tabs/ (entire folder — Nudge has no tabs)
- Live activities/ (entire folder)
- LottieView.swift, AnimatedFace.swift, EmptyState.swift,
  ProgressIndicator.swift, TestView.swift, Tips/, WhatsNewView.swift

## Observers (boringNotch/observers/)
- DragDetector.swift
- MediaKeyInterceptor.swift
- FullscreenMediaDetection.swift

## XPC + helpers
- boringNotch/XPCHelperClient/ (entire folder)
- BoringNotchXPCHelper/ (entire target — also drop from project)
- mediaremote-adapter/ (entire folder + resource entry)

## Helpers (boringNotch/helpers/)
- AudioPlayer.swift, AppleScriptHelper.swift, MediaChecker.swift,
  ApplicationRelauncher.swift, Clipboard+Content.swift

## Models (boringNotch/models/)
- CalendarModel.swift, EventModel.swift, BatteryStatusViewModel.swift,
  PlaybackState.swift, MusicControlButton.swift, SharingStateManager.swift

## SPM dependencies that can go
- Sparkle (we disabled auto-update)
- LaunchAtLogin (we removed the toggle)
- Lottie (only used by music visualizer)
- SkyLightWindow + AsyncXPCConnection + MacroVisionKit (depend on the
  music/XPC features)

## Other
- `boringNotch/boring.m4a` (welcome sound) + its resource entry
- `boringNotch/Localizable.xcstrings` — orphaned keys for music/calendar/etc.
  Either replace with a tiny Nudge-only string catalog or remove entirely
  (we don't ship localizations in v1).
- `BoringViewCoordinator.swift`: `sneakPeek`, `expandingView`,
  `toggleSneakPeek`, `toggleExpandingView` data + methods still exist for
  data-model reasons but have no callers now.
- `BoringViewModel.swift`: drop the `webcamManager`, `detector`,
  `toggleCameraPreview`, drop-target fields, isHoveringCalendar,
  isBatteryPopoverActive once their consumers are gone.

## Rename internal identifiers
- Xcode target name `boringNotch` → `Nudge` (touches schemes, build
  configurations, file paths, and DerivedData).
- Bundle identifier (likely `com.boring.notch` or similar) → something
  Ontora-owned.
- Top-level `boringNotch/` source folder → `Nudge/`.

These were deferred because each one requires careful pbxproj surgery
and we wanted v1 to build today.
