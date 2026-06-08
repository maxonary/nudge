//
//  NudgeNotifier.swift
//  Nudge
//

import Foundation
import UserNotifications
import Defaults
import os

enum NudgeNotifier {
    private static let log = Logger(subsystem: "com.ontora.nudge", category: "notifier")

    static func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .timeSensitive])
            log.info("notification permission granted=\(granted)")
        } catch {
            log.error("notification auth error: \(error.localizedDescription)")
        }
    }

    static func postBackup(sender: String, message: String? = nil) {
        guard Defaults[.nudgeShowBackupNotification] else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(sender) wants you"
        if let message, !message.isEmpty {
            content.body = message
        } else {
            content.body = "Open Nudge to acknowledge"
        }
        content.interruptionLevel = .timeSensitive
        if Defaults[.nudgePlaySoundOnReceive] {
            content.sound = .default
        }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                log.error("backup notification failed: \(error.localizedDescription)")
            }
        }
    }
}
