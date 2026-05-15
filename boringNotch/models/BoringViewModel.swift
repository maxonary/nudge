//
//  BoringViewModel.swift
//  Nudge
//

import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published private(set) var notchState: NotchState = .closed
    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation
        super.init()
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize
    }

    var effectiveClosedNotchHeight: CGFloat {
        closedNotchSize.height
    }

    var chinHeight: CGFloat {
        guard Defaults[.hideTitleBar],
              let screen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }),
              notchState != .open else {
            return 0
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight
        guard currentHeight > 0 else { return 0 }
        return max(0, menuBarHeight - currentHeight)
    }

    func open() {
        notchSize = openNotchSize
        notchState = .open
    }

    func close() {
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize
        notchState = .closed
    }
}
