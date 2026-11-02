# Changelog

## 0.5.2 — 2026-11-02

### Added

- Browse GIFs directly inside the notch, with a taller, scrollable grid.
- Search GIFs as you type, with a short debounce and cancellation of outdated searches.
- Click a GIF to attach it immediately, then preview or remove it before choosing a recipient.
- Show an animated checkmark for text nudges only after the recipient's app confirms receipt. While waiting, show a progress indicator; after eight seconds without confirmation, show “Sent — receipt not confirmed.”
- Close the notch with Escape while interacting with it, or by clicking outside it. Unsent text and GIF drafts are retained.
- Copy the shared team password from Settings → Team password.
- Check for Updates from the menu, with a link to the newer GitHub release when available.

### Fixed

- Allow clicking and typing in the notch message field.
- Fit the message field and GIF button to the width of the available Ping buttons.
- Keep the selected GIF preview open while choosing a teammate.
- Keep the notch open for the text delivery confirmation animation; ordinary pings retain their short confirmation.
- Prevent GIF scrolling from moving or scaling the notch.
- Keep GIF previews inside their cells instead of overlapping neighboring results.
- Avoid rebuilding the notch's gesture wrapper when opening or closing the GIF browser, and cancel unused GIF downloads.
- Prevent a later receipt from reopening an explicitly dismissed notch, and block duplicate text sends while awaiting confirmation.

### Compatibility and updates

- Teammates need version 0.5.2 or later to return delivery receipts. Older versions can still receive nudges, but cannot confirm them.
- A receipt confirms delivery to the recipient's app; it does not mean the person has read the nudge.
- Updates preserve existing nudge counts, leaderboard totals, identity, and the team password. Replace the app in Applications; do not delete its saved data.
- Check for Updates opens the release download page; installation remains manual.
