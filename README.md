# Nudge

A lightweight macOS notch app for getting a teammate's attention, with optional text and GIFs. Nudge uses a shared team password and ntfy.sh to exchange encrypted nudges without separate user accounts.

## Install and join a team

1. Download the latest signed and notarized app from [Releases](https://github.com/maxonary/nudge/releases).
2. Unzip it and drag **Nudge.app** into **Applications**.
3. Open Nudge, choose a unique name, and enter the same team password as your teammates.
4. Allow notifications if you want backup macOS banners.

Share the app and team password privately to invite another teammate. Settings → Team password → **Copy password** copies your current password from Keychain. Teammates appear automatically after their apps announce themselves; discovery can take up to 30 minutes. Restarting existing teammates' apps after a new teammate joins speeds up discovery.

## Send a nudge

Hover or click the notch, optionally type a message, and click **Ping [name]**.

For a GIF, click the image button. The notch expands into a GIF browser and updates results as you type. Clicking a GIF attaches it immediately and returns to a preview. Click the remove button to discard it, or choose a teammate to send it.

For text nudges, a spinner waits for a delivery receipt. The animated checkmark appears only when the recipient's app confirms receipt. Both apps need version 0.5.2 or later for receipts; an older recipient can still receive the nudge. A receipt confirms app delivery, not that a person has read it. If no receipt arrives within eight seconds, Nudge shows **Sent — receipt not confirmed**.

Press **Escape** while interacting with the notch, or click outside it, to close it. Unsent text and attached GIFs remain available when you reopen it.

## Settings and updates

The hand-wave menu includes Settings, sound and notification toggles, launch at login, **Check for Updates**, and Quit. Settings also contains your identity, team password, known teammates, all-time statistics, and an optional GIF API key override.

Check for Updates compares the installed version with the latest GitHub release and opens the download page when an update is available. To install it, quit Nudge and replace Nudge.app in Applications. Existing nudge counts, leaderboard totals, identity, and the team password are retained.

See [CHANGELOG.md](CHANGELOG.md) for release changes.

## Build

Requires macOS 14 or later and a compatible Xcode installation. Open `Nudge.xcodeproj` and run the Nudge scheme. Local development builds need a Klipy API key in Settings → GIFs to search GIFs; release builds receive a shared key through CI.

## Transport

Every team member derives the same ntfy topic and encryption key from the shared password. Names, messages, GIF links, and receipts travel inside AES-GCM-encrypted payloads. Each recipient filters pings by name, so use unique names within a team. The public ntfy service carries the traffic; GIF search and images come from Klipy and its media hosts.

## Credits

Nudge is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) by The Boring Team. Its notch window plumbing and animations underpin the team-ping interface. See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) and [LICENSE](LICENSE).
