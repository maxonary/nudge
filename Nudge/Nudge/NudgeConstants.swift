//
//  NudgeConstants.swift
//  Nudge
//

import Foundation

// Shared 12-char lowercase nonce. Every Ontora teammate's build MUST have the
// same value here. Rotate by changing the constant and shipping a new build.
let nudgeNonce = "k4n9pq7vx2tm"

let nudgeUsers: [String] = ["Max", "Leon", "David"]

func ntfyTopic(for user: String) -> String {
    "nudge-ontora-\(user.lowercased())-\(nudgeNonce)"
}
