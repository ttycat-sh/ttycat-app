# ttycat for the Mac

The menu bar app of [ttycat](https://github.com/ttycat-sh/ttycat-firmware): every coding agent, what it's doing, and Allow or Deny for the ones waiting on you, with or without the board. It carries [ttycat-daemon](https://github.com/ttycat-sh/ttycat-daemon), as the `daemon/` submodule, and runs it.

| Repo | What |
|---|---|
| [ttycat-firmware](https://github.com/ttycat-sh/ttycat-firmware) | the board's firmware, and the protocol |
| [ttycat-daemon](https://github.com/ttycat-sh/ttycat-daemon) | the daemon this app carries |
| **ttycat-app** | this: the menu bar app |

## What it does

A SwiftUI menu bar app in the board's look. It keeps the daemon running, restarts it if it dies, and shows every agent, the board's link and Bit's stats. You can answer prompts in it, and click a row to see what that agent has been doing. It needs macOS 14 and the command line tools, not Xcode:

```sh
git submodule update --init   # the daemon, once
./build.sh                    # builds build/ttycat.app
./build.sh install            # also copies it to /Applications and starts it
```

**Setup** in the panel has start at login (off until you tick it; use the copy in /Applications), the permission hook, update checks, notifications, the board's firmware and the daemon's log.

**The first time**, the panel opens by itself, and asks for start at login, the permission hook and notifications, each once. A release opened from its disk image or from Downloads first offers to move itself into Applications: it can only update itself from there.

**Uninstalling:** Setup > Uninstall ttycat takes its hook out of Claude's settings and removes its login item, then moves the app to the Trash. Ticking the box also deletes `~/.ttycat`, with Bit in it. An app dragged to the Trash instead leaves a hook that does nothing: Claude asks in the terminal, as before.

- **Notifications** say when an agent needs you, and when one finishes after 30 s or more of work. Clicking one opens the panel on that prompt, or the terminal if there's nothing to answer there.
  - A prompt waits 3 s, so one you answer straight away never shows a banner. Nothing is posted for the agent whose pane is focused in your terminal while that terminal is in front and you've touched the Mac in the last 2 minutes, nor while the panel is open. A prompt is posted when you move away; a finished turn isn't.
  - Allow is never on a notification. A prompt's notification offers Deny, and a click opens the panel to read and answer it. A single question with one answer gets its options and "Type an answer" as buttons. Several questions, or pick-any, open the panel.
  - Buttons don't work from a locked screen, and a click within 600 ms of a notification appearing doesn't count. A notification goes away once its prompt is settled anywhere, and when the app quits.
  - Commands, questions and the agent's last words appear in Notification Center, so they can be seen by anyone looking at the screen. macOS's "Show previews" setting hides them.
  - The app asks macOS for permission only when you click **Turn on notifications** in Setup. If it was refused, it's System Settings > Notifications > ttycat.
  - macOS holds notifications back during a Focus, without any error, unless you allow this app in that Focus. Setup always says so, because this build can't tell whether a Focus is on. Time Sensitive wouldn't get through either: it needs an entitlement this build doesn't have, and macOS ignores it without one.
- **Answers work as they do on the board.** Allow, Deny and questions (typed answers here can be up to 1000 characters and aren't limited to ASCII) go only to the hook process that asked, and only for the exact prompt on screen. Buttons wait 600 ms after a prompt appears, and a new prompt waits its turn instead of replacing the one on the card.
- **Anything running as you can reach the daemon's socket,** so a program you run could answer a prompt. That was already true of `ttycatd.py tap` and `herdr agent send-keys`.
- **The app carries what it needs:** the daemon, Python and esptool, so a Mac needs nothing installed. The hook points into the app, and repairs itself at launch if the app has moved. `vendor.sh` prepares Python and esptool (pinned, from GitHub and PyPI), once. Without it the app still builds and uses the system's Python, for working on it. `TTYCAT_DAEMON_DIR=daemon` runs a build's daemon from this checkout instead. Apple silicon only, for now.
- **The board is optional.** Nothing mentions it until one has been connected.
- **A release** is `TTYCAT_VERSION=X.Y.Z ./release.sh`: signed with your Developer ID, in a disk image, notarized by Apple. See the script for the one-time setup. A version ending in `-dev.N` is a dev release, which trusts dev's release key too and asks dev's update server. A release ignores `TTYCAT_TRUST_KEY` and `TTYCAT_UPDATES_URL`, which only work in a developer's build (`daemon/build_info.py`). A release updates itself with Sparkle (`Sources/TTYCat/AppUpdater.swift`), from its update server's `/v1/appcast`, and installs only a disk image signed by its environment's app update key (`tools/release_app.py`). A developer's build never does. Licenses of what it carries are in `THIRD_PARTY.md`.
- **The panel is its own window, not SwiftUI's `MenuBarExtra`,** which grows its window but never shrinks it (`StatusPanel.swift`). Its top stays under the icon, its height follows the page, and a page too tall for the screen scrolls under the tabs. It takes the keyboard without making this the active app, like Spotlight, so what you were in stays in front. A click elsewhere, Esc, or switching app closes it. Its content is built new on each open, so a prompt's buttons always get their full delay.
- **One daemon at a time.** A second one exits with status 3. If one's already running, from a terminal say, the app uses it, and leaves it running when it quits. One the app started stops with it.
- Plain `@State` doesn't build here: in current SDKs it's a macro, and its plugin comes only with Xcode. Panel.swift has a small stand-in.
- To check the look without opening the menu: `"build/ttycat.app/Contents/MacOS/ttycat" --preview out.png needs` (`busy`, `needs`, `diff`, `long`, `question`, `questions`, `terminal`, `detail`, `done`, `idle`, `setup`, `setup-new`, `setup-denied`, `setup-short`, `welcome`, `noboard`, `pet`, `pet-asleep`, `pet-needs`, `pet-level`, `pet-hello`, `pet-birthday`, `pet-old`, `pet-work`, `fw-update`, `fw-write`, `fw-back`, `fw-fail`, `fw-unknown`, `fw-custom`, `fw-custom-on`, `fw-custom-old`, `fw-core`, `fw-core-new`, `fw-core-again`, `fw-core-newest`, `fw-core-read`, `fw-core-blocked`, `fw-core-moved`, `fw-core-build`, `fw-core-write`, `fw-core-back`, `fw-core-fail`, `stopped`, `unplugged`).

## What it carries

- **The daemon** at the commit `daemon/` pins.
- **The firmware**: a developer's build takes the last build from a [ttycat-firmware](https://github.com/ttycat-sh/ttycat-firmware) checkout beside this one (`../ttycat-firmware`, or `TTYCAT_FIRMWARE_DIR`). A release carries the signed release that `firmware.json` names, for the official board.

## Tests

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
python3 -m unittest discover -s tools/tests
```

The first needs no Xcode, only to be told where the command line tools keep the test macros. The second checks what a release's daemon is told (`tools/app_build.py`), and that the app's colours are the daemon's.

## Open source, and Pro

Everything here is free and open source: seeing your agents, answering their prompts, notifications, the board and its firmware, and Bit. It's complete without anything else.

Pro will add paid features to the official download. It isn't on sale yet. They're kept in a separate private repository: usage and limits, a log of what agents did, other machines, and skins. They join through two small interfaces, `Sources/TTYCat/Extensions.swift` here and `plugins.py` in the daemon, and this code never depends on them.

## License

Apache-2.0: see `LICENSE` and `NOTICE`. What the app carries from others, and under which license, is in `THIRD_PARTY.md`. The license doesn't grant use of the product's name or logo.
