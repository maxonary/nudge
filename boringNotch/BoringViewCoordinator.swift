//
//  BoringViewCoordinator.swift
//  Nudge
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @AppStorage("firstLaunch") var firstLaunch: Bool = true

    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    private init() {
        if preferredScreenUUID == nil {
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
    }
}
