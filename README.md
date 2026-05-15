# Nudge

Glanceable "raise hand" signal between Ontora founders that pierces noise-cancelling
headphones without forcing anyone to physically get up.

<img width="1300" height="710" alt="Nudge Giff" src="https://github.com/user-attachments/assets/63198e78-cd57-4d78-873b-60f4fef360e2" />

## Backstory

Ontora is a 3-founder YC P26 startup (Max, Leon, David) sharing a room in
San Francisco. Leon and David both wear noise-cancelling headphones for deep
work. Slack and WhatsApp don't pierce headphones. Calling someone in the same
room feels insane. So the only way to get their attention has been to stand
up and tap them on the shoulder, which kills your own focus too.

<img width="687" height="440" alt="Bildschirmfoto 2026-05-14 um 22 55 04" src="https://github.com/user-attachments/assets/afe4e9ac-8836-48b6-a04a-db084491adbb" />

Nudge fixes that: a glanceable signal in the MacBook notch. Click your notch,
pick a teammate, their notch expands for ~6 seconds with `{sender} wants you`.
A backup macOS notification fires in case the notch is off-screen (external
monitor, full-screen window). No backend, no accounts, no message text —
just the ping.

The friction of "I have to move the cursor to my notch to ping you" is a
feature, not a bug. It filters out interruptions that aren't worth the cost.

Nudge is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch).
Everything that doesn't serve the team-ping flow is disabled in this build;
see `TODO_V2_CLEANUP.md` for the dormant code still on disk.

## The shared topic nonce

The transport is [ntfy.sh](https://ntfy.sh) — a public, free, no-account pub/sub
service. Each user subscribes to a topic derived from their name plus a
shared 12-char lowercase nonce. The nonce is the only thing that keeps random
people on the internet from being able to ping us.

The current nonce (baked into the build, read from `boringNotch/Nudge/NudgeConstants.swift`):

```
k4n9pq7vx2tm
```

**Every Ontora teammate's build MUST have the same nonce.** To rotate it:
edit `nudgeNonce` in `NudgeConstants.swift`, commit, and have everyone pull
and rebuild.

The full topic for a given recipient is:

```
nudge-ontora-<recipient-lowercased>-<nonce>
```

…which you can also poke from a terminal:

```bash
# Ping yourself for testing
curl -d "Max" -H "Title: Max wants you" \
    https://ntfy.sh/nudge-ontora-leon-k4n9pq7vx2tm
```

## Build & run

**Requirements:** macOS 14 (Sonoma) or later, Xcode 16 or later.

```bash
git clone <this repo>
cd <repo>
open boringNotch.xcodeproj
# In Xcode, hit ⌘R
```

On first launch:

1. A 400×600 window appears asking "Who are you? [Max] [Leon] [David]".
2. Pick your name. Nudge asks for notification permission (used for the
   backup banner when the notch isn't visible). Grant or skip.
3. The window closes and your notch becomes the Nudge surface.

That's it. Hover the notch → it expands → tap a teammate's name → they get
pinged.

## Sending a ping

- Hover the notch (or click it).
- Tap `[Ping <teammate>]`.
- You'll feel a trackpad haptic and the notch will briefly highlight the
  pressed button before collapsing.

## Receiving a ping

- Your notch auto-expands and shows the sender's initial + "{sender} wants
  you" for 6 seconds.
- A backup macOS notification fires at the same time (toggleable in
  Settings).
- A soft "Pop" sound plays (toggleable in Settings).

If you happen to be hovering the notch when a ping arrives, it stays open
until you move away.

## Settings

Open via the menu bar icon (the wave 👋) → Settings, or `⌘,` while the notch
has context-menu focus.

The settings window has one pane:

- **Identity** — the three name buttons. Tap to switch identities; the new
  subscription starts immediately.
- **Receive behavior** — sound on/off, backup notification on/off.
- **Shared nonce** — read-only display + copy button. Use this to verify
  every teammate has the same value.

## Local testing without a teammate

1. Pick "Max" on first launch.
2. From another terminal, ping yourself as if you were Leon:
   ```bash
   curl -d "Leon" -H "Title: Leon wants you" \
     https://ntfy.sh/nudge-ontora-max-k4n9pq7vx2tm
   ```
3. Your notch expands within ~1 second showing "Leon wants you".

To verify the send side, run two debug builds (different `DerivedData`
or use two laptops), switch one to Leon via Settings, ping from Max.

## What's intentionally not in v1

- Reply / ack channel ("on my way" / "5 min")
- Custom message text per ping
- Urgency tiers
- Auth, accounts, end-to-end encryption
- More than 3 users
- App Store distribution, code signing, Sparkle auto-update

## Credits

This is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch)
by The Boring Team — their notch overlay window plumbing, expand/collapse
animations, and menu bar wiring are doing the heavy lifting here. Nudge keeps
their `LICENSE` intact and credits them in
[`THIRD_PARTY_LICENSES`](./THIRD_PARTY_LICENSES).

The notch idea, the team-ping flow, and the surgery to strip Boring Notch
down to it are ours.
