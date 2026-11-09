//
//  NudgeViewModel.swift
//  nudge
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class NudgeViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = NudgeViewCoordinator.shared

    let animationLibrary: NudgeAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = false

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    /// Natural height of the agent panel, reported by AgentAttentionView.
    private var agentContentHeight: CGFloat?

    func updateAgentContentHeight(_ height: CGFloat) {
        guard height > 0, abs((agentContentHeight ?? 0) - height) > 0.5 else { return }
        agentContentHeight = height
        guard notchState == .open, AgentAttentionCenter.shared.hasVisibleAgentContent else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            open()
        } else {
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.82, blendDuration: 0)) {
                open()
            }
        }
    }

    func open() {
        // Agent content replaces the send view, including its GIF draft row,
        // and the notch hugs it like the Dynamic Island.
        let contentHeight: CGFloat
        let agentAttention = AgentAttentionCenter.shared
        if agentAttention.hasVisibleAgentContent {
            let panelHeight = agentContentHeight
                ?? AgentAttentionView.estimatedHeight(for: agentAttention.state)
            contentHeight = min(
                effectiveClosedNotchHeight + agentAttentionChromeHeight + panelHeight,
                agentAttentionMaxHeight
            )
        } else {
            contentHeight = openNotchSize.height + (NudgeDraft.shared.gif == nil ? 0 : gifDraftExtraHeight)
        }
        self.notchSize = CGSize(
            width: openNotchSize.width,
            height: contentHeight + (NudgeDraft.shared.isPickingGIF ? gifPickerExtraHeight : 0)
        )
        self.notchState = .open
    }

    func dismiss() {
        NudgeDraft.shared.isPickingGIF = false
        NudgeDraft.shared.isShowingSentConfirmation = false
        NudgeTransport.shared.lastIncoming = nil
        close(force: true)
    }

    func close(force: Bool = false) {
        // Let the successful text-send animation finish before collapsing,
        // including when the pointer leaves or a shortcut requests closing.
        guard force || (!NudgeDraft.shared.isShowingSentConfirmation && !NudgeDraft.shared.isAwaitingReceipt && !NudgeDraft.shared.isPickingGIF) else { return }
        // The next agent panel measures itself again; open it from its estimate.
        agentContentHeight = nil
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.edgeAutoOpenActive = false
        coordinator.currentView = .home
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
