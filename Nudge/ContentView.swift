//
//  ContentView.swift
//  Nudge
//

import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: NudgeViewModel
    @ObservedObject var coordinator = NudgeViewCoordinator.shared
    @ObservedObject var transport = NudgeTransport.shared

    @State private var hoverTask: Task<Void, Never>?
    @State private var autoCloseTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics: Bool = false

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private var topCornerRadius: CGFloat {
        ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    var body: some View {
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            return max(0.6, 1.0 + gestureProgress * 0.01)
        }()

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                            ? (Defaults[.cornerRadiusScaling]
                                ? cornerRadiusInsets.opened.top
                                : cornerRadiusInsets.opened.bottom)
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .animation(
                        vm.notchState == .open
                            ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                            : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0),
                        value: vm.notchState
                    )
                    .animation(.smooth, value: gestureProgress)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view.panGesture(direction: .up) { translation, phase in
                            handleUpGesture(translation: translation, phase: phase)
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(x: gestureScale, y: gestureScale, anchor: .top)
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: transport.lastIncoming) { _, ping in
            handleIncoming(ping)
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The visible "lip" above where the real notch sits — keep it
            // empty (Nudge doesn't show a header bar).
            Rectangle()
                .fill(.clear)
                .frame(
                    width: vm.notchState == .open ? nil : vm.closedNotchSize.width - 20,
                    height: vm.effectiveClosedNotchHeight
                )
                .zIndex(2)

            if vm.notchState == .open {
                NudgeNotchView()
                    .transition(
                        .scale(scale: 0.8, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.smooth(duration: 0.35))
                    )
                    .zIndex(1)
            }
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) { isHovering = true }
            if vm.notchState == .closed && Defaults[.enableHaptics] { haptics.toggle() }
            guard vm.notchState == .closed, Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.vm.notchState == .closed, self.isHovering else { return }
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(animationSpring) { self.isHovering = false }
                    if self.vm.notchState == .open {
                        // Don't auto-close while showing an incoming ping
                        if let ping = self.transport.lastIncoming,
                           Date().timeIntervalSince(ping.receivedAt) < 6 {
                            return
                        }
                        self.vm.close()
                    }
                }
            }
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) { isHovering = false }
            gestureProgress = .zero
            vm.close()
            if Defaults[.enableHaptics] { haptics.toggle() }
        }
    }

    private func handleIncoming(_ ping: NudgePing?) {
        guard let ping else { return }
        autoCloseTask?.cancel()
        NudgeNotifier.postBackup(sender: ping.sender, message: ping.message)
        if Defaults[.nudgePlaySoundOnReceive] {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
        doOpen()
        autoCloseTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !self.isHovering {
                    self.vm.close()
                }
            }
        }
    }
}

#Preview {
    let vm = NudgeViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
