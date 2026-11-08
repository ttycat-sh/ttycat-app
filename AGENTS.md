# Working on the ttycat app

The menu bar app: it runs the daemon (the `daemon/` submodule, [ttycat-daemon](https://github.com/ttycat-sh/ttycat-daemon)) and shows what it knows. The rules in [ttycat-firmware's AGENTS.md](https://github.com/ttycat-sh/ttycat-firmware/blob/main/AGENTS.md) hold here too:

- **Nothing approves by itself, and nothing rewards approving.** No auto-allow, no "allow all"; Deny always takes effect. Bit never reacts to an answer.
- **Allow only where the whole prompt can be read.** Never on a notification.
- **Never answer a prompt yourself**, on someone's real sessions. To test, use `demo`.
- **Don't touch their setup without asking:** no flashing, no changes to `~/.claude/settings.json`, no pushing, without a yes for that one action.

Build with `./build.sh`; see the look without opening the menu with `build/ttycat.app/Contents/MacOS/ttycat --preview out.png SCENE`. Tests: see `README.md`. This code never depends on Pro: it joins only through `Extensions.swift`.
