# Nudge

Glanceable "raise hand" signal between Ontora founders that pierces noise-cancelling
headphones without forcing anyone to physically get up.

## Backstory

Ontora is a 3-founder YC X26 startup (Max, Leon, David) sharing a room in
San Francisco. Leon and David both wear noise-cancelling headphones for deep
work. Slack and WhatsApp don't pierce headphones. Calling someone in the same
room feels insane. So the only way to get their attention has been to stand
up and tap them on the shoulder, which kills your own focus too.

Nudge fixes that: a glanceable signal in the MacBook notch. Click your notch,
pick a teammate, their notch expands for ~6 seconds with `{sender} is waving`.
A backup macOS notification fires in case the notch is off-screen (external
monitor, full-screen window). No backend, no accounts, just an encrypted
hand-wave over a public pub/sub.

The friction of "I have to move the cursor to my notch to ping you" is a
feature, not a bug. It filters out interruptions that aren't worth the cost.

Nudge is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch).
Everything that doesn't serve the team-ping flow is disabled in this build;
see `TODO_V2_CLEANUP.md` for the dormant code still on disk.

## The team password

The transport is [ntfy.sh](https://ntfy.sh) — a public, free, no-account pub/sub
service. Anyone can subscribe to or post to any topic if they know its name.
So we use a shared **team password** to do two things:

1. **Derive the team topic** — `nudge-team-<12 hex chars of HKDF(password, info="topic")>`.
   One topic for the whole team. Without the password you can't compute it,
   so you can't find the pub/sub stream to listen on or send to.
2. **Encrypt every payload** — message bodies are AES-GCM encrypted with a
   key derived from the same password (HKDF with a different `info` tag).
   Even if someone learns the topic, they see ciphertext.

The password is entered on first launch and stored only in the macOS
Keychain — never in the repo, never sent over the network. Everyone on
your team types the same one. To rotate it: change it in Settings →
Team password and have your teammates do the same.

If two people enter different passwords they're silently on different
topics and won't reach each other — there's no backend to warn you, so
nudge yourself to test after any change.

## How teammates discover each other

There's no roster file. When you launch the app with a name and password
set, you post a tiny encrypted `{type:"hello", sender:"<you>"}` to the
shared team topic, and refresh it every ~30 minutes. Teammates already on
the team see your hello and add you to their local roster — that's what
populates the ping buttons in their notch and the leaderboard rows in
their Settings. Onboarding a new teammate is just "install app → type
your name → type the team password." Within a couple of seconds the team
has discovered you, and you've discovered them.

## Build & run

**Requirements:** macOS 14 (Sonoma) or later, Xcode 16 or later.

```bash
git clone <this repo>
cd <repo>
open boringNotch.xcodeproj
# In Xcode, hit ⌘R
```

On first launch:

1. A 400×600 window appears asking "What's your name?" — type whatever
   you want your teammates to see (1–32 chars, no colons).
2. Nudge asks for notification permission. Grant or skip.
3. Enter the **team password** (the same string everyone else types).
4. The window closes and your notch becomes the Nudge surface.

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
- **Team password** — status + "Change password…" button.
- **Receive behavior** — sound on/off, backup notification on/off.

## Local testing without a teammate

Run the app, pick "Max", set a team password. From the same Mac, you can
ping yourself as if you were Leon — but you'd need to compute the
encrypted payload, which is fiddly from a terminal. Easier: temporarily
switch your identity to Leon in Settings, then back to Max — the
subscription resubscribes immediately, and you can also send pings to
yourself by switching back and forth.

(With v0.2.x's plaintext payload this was a one-line `curl`; now that
payloads are AES-GCM encrypted, terminal pinging would need a small
script. Out of scope for v1 of the encryption work.)

## What's intentionally not in this build

- Reply / ack channel ("on my way" / "5 min")
- Custom message text per ping
- Urgency tiers
- More than 3 users
- App Store distribution, Sparkle auto-update

## Credits

This is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch)
by The Boring Team — their notch overlay window plumbing, expand/collapse
animations, and menu bar wiring are doing the heavy lifting here. Nudge keeps
their `LICENSE` intact and credits them in
[`THIRD_PARTY_LICENSES`](./THIRD_PARTY_LICENSES).

The notch idea, the team-ping flow, and the surgery to strip Boring Notch
down to it are ours.
