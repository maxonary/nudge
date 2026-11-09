//
//  BundleInfos.swift
//  nudge
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
    var releaseVersionNumberPretty: String {
        return "v\(releaseVersionNumber ?? "1.0.0")"
    }
    
    var iconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }
}

struct BundleAppIcon: View {
    var body: some View {
        Bundle.main.iconFileName
            .flatMap { NSImage(named: $0) }
            .map { Image(nsImage: $0) }
    }
}

func isNewVersion() -> Bool {
    let defaults = UserDefaults.standard
    let currentVersion = Bundle.main.releaseVersionNumber ?? "1.0"
    let savedVersion = defaults.string(forKey: "LastVersionRun") ?? ""
    
    if currentVersion != savedVersion {
        defaults.set(currentVersion, forKey: "LastVersionRun")
        return true
    }
    return false
}

func isExtensionRunning(_ bundleID: String) -> Bool {
    if let _ = NSWorkspace.shared.runningApplications.first(where: {$0.bundleIdentifier == bundleID}) {
        return true
    }
    
    return false
}


/// Checks this fork's signed GitHub releases; installation stays user-initiated.
@MainActor
final class NudgeUpdateChecker: ObservableObject {
    static let shared = NudgeUpdateChecker()
    @Published private(set) var isChecking = false

    private static let releasesURL = URL(string: "https://github.com/maxonary/nudge/releases")!

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }

    private init() {}

    /// Numeric comparison avoids treating 0.5.10 as older than 0.5.9.
    nonisolated static func isNewer(_ tag: String, than installed: String) -> Bool? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let installedParts = installed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !installedParts.isEmpty,
              (parts + installedParts).allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else {
            return nil
        }
        // Pad trailing zeroes so 1.0 and 1.0.0 compare equally.
        let count = max(parts.count, installedParts.count)
        let latest = (parts.map(String.init) + Array(repeating: "0", count: count - parts.count)).joined(separator: ".")
        let current = (installedParts.map(String.init) + Array(repeating: "0", count: count - installedParts.count)).joined(separator: ".")
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/maxonary/nudge/releases/latest")!)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease,
                  release.html_url.scheme == "https",
                  release.html_url.host == "github.com",
                  release.html_url.path.hasPrefix("/maxonary/nudge/releases/tag/"),
                  let installed = Bundle.main.releaseVersionNumber,
                  let newer = Self.isNewer(release.tag_name, than: installed) else {
                throw URLError(.cannotParseResponse)
            }
            let alert = NSAlert()
            if newer {
                alert.messageText = "Nudge \(release.tag_name) is available"
                alert.informativeText = "You have version \(installed). Download the new release and replace Nudge in Applications. Your nudge counts and settings will be kept."
                alert.addButton(withTitle: "View Download")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(release.html_url)
                }
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "You're running Nudge \(installed). The latest published release is \(release.tag_name)."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "Check your internet connection and try again, or view the releases on GitHub."
            alert.addButton(withTitle: "Try Later")
            alert.addButton(withTitle: "View Releases")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(Self.releasesURL)
            }
        }
    }
}
