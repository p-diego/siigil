# Developing Siigil

Notes for building, testing and releasing Siigil. The README is for people who use the app; working documents (specs,
plans, the roadmap) live in the private `siigil-docs` repository.

## Requirements

- macOS 26 and Xcode with Swift 6.2 or later (the package's tools version; developed with Xcode 27 and Swift 6.4); the
  package uses language mode 5.
- An Apple Development certificate in your keychain (Xcode creates one with your Apple ID; `make` finds it by itself).
  Without one the build is signed ad-hoc: macOS then ties permissions to the binary's hash, so Location and Full Disk
  Access must be granted again after every `make install` or update (remove Siigil from the list and add it back).
- AeroSpace is optional (`brew install --cask nikitabobko/tap/aerospace`).

## Build and run

    make run        # build, assemble .build/Siigil.app and launch it (development)
    make cpu        # like run, then print the bar's average CPU at rest
    make test       # swift test; make release runs it before tagging
    make install    # copy to ~/Applications and launch (it registers itself as a login item)
    make uninstall  # remove the app
    make dist       # .build/Siigil-<version>.zip, for scripts
    make dmg        # .build/Siigil-<version>.dmg, for people (drag-to-Applications window)
    make release    # tests, zip and DMG, tag v<version>, GitHub release
    pkill -x Siigil

`swift build` alone does not update `.build/Siigil.app`: use `make run` to try a change. After `make run` the development
build is running; at the next login the last `make install` starts again (System Settings › General › Login Items).

Errors (discarded hooks, CLI timeouts, …) go to the unified log, not to stderr:
`/usr/bin/log stream --predicate 'subsystem == "com.siigil.app"'` (full path: in zsh `log` is a builtin), or Console.app.

## Layout

One SwiftPM executable target, `Siigil`, and one test target, `SiigilTests`.

| Area | Files |
|---|---|
| App, panels, the bar | `main.swift`, `BarPanel.swift`, `BarState.swift`, `Views/BarView.swift`, `Views/WorkspacePill.swift`, `Views/Rearrange.swift`, `Views/IconDrag.swift` |
| Refresh loop, AeroSpace | `Poller.swift`, `Aerospace.swift`, `Model.swift`, `Apps.swift`, `WindowEvents.swift` |
| Widgets | `Views/Widgets.swift`, `System.swift`, `WiFi.swift`, `Bluetooth.swift`, `NowPlaying.swift`, `Focus.swift`, `ClockApp.swift` |
| AI agents and limits | `AgentServer.swift`, `Integrations.swift`, `Usage.swift`, `QuotaCache.swift`, `Resources/siigil-hook` |
| Mascots | `Mascot.swift` (model, migration), `NewMascot.swift`, `MascotShapes.swift`, `MascotDrawing.swift`, `MascotLife.swift`, `Views/MascotView.swift`, `Views/BarMascot.swift` (bar item and menu), `Sounds.swift` |
| System monitor | `Watchdog.swift`, `WatchdogReader.swift` |
| Settings and Welcome | `Settings.swift`, `SettingsWindow.swift`, `Views/SettingsView.swift`, `Views/MascotsPage.swift`, `Views/AppearanceView.swift`, `Theme.swift`, `Setup.swift`, `Views/WelcomeView.swift` |
| Updates | `Updater.swift` |

Code comments are in Italian.

## Settings storage

Everything is in `defaults read com.siigil.app`, keys `siigil.*`; deleting them restores the defaults. Mascots are a
JSON array in `siigil.mascots` (in order of addition); the bar's order is in `siigil.bar.left` and `siigil.bar.right`
(tokens: widget ids and `mascot:<uuid>`). The keys of 0.31 and earlier are only read, once, to migrate the old cat and
Watchdog into two mascots; they are never written, so an older version still finds its settings.

## Languages

English text is the localization key itself, written in the code (`String(localized:)`, `Text("…")`): there is no English
strings file. Italian lives in `Resources/it.lproj/Localizable.strings`; add every new key there (`plutil -lint` after
editing). `Credits.rtf` exists in both `en.lproj` and `it.lproj`. Dates and times follow the locale.

## AeroSpace

Siigil talks to AeroSpace over its documented socket (`/tmp/bobko.aerospace-$USER.sock`, AeroSpace 0.21 and later): one
connection for requests, one subscribed to events (focus, workspace, monitor, new window, binding). The bar refreshes on
every event, when an app quits and when the mouse is released, plus a check every 60 seconds; `~/.aerospace.toml` needs
nothing for Siigil. With AeroSpace older than 0.21 it uses the CLI every 5 seconds; without AeroSpace it shows the open
apps in a single pill.

With several screens, give the external ones a top gap: on the built-in display the notch already reserves the space, on
external screens (no notch, hidden menu bar) windows would end up under the 38 pt bar:

    gaps.outer.top = [{ monitor."built-in" = 5 }, 43]

## Agents

Agent sessions report their state to a per-user Unix socket, `/tmp/siigil-<uid>.sock`, one JSON line per event:

    {"agent": "claude" | "codex", "state": "working" | "waiting" | "done" | "end", "bundle": "<host app bundle id>",
     "payload": {"session_id": "…", "cwd": "…", …}}

`end` removes the session. `Resources/siigil-hook <state>` builds the line from the hook's stdin and sends it with `nc`;
it never prints anything and always exits 0, and it only writes to a socket owned by the current user. The bundle is the
app hosting the terminal (`__CFBundleIdentifier`), or `$SIIGIL_BUNDLE`.

**Claude Code** — Settings › AI accounts writes this block into `~/.claude/settings.json`, with the path of the app as
installed (here `~/Applications`), merged with your hooks, backup in `settings.json.bak`; "Update" if the app moved:

```json
"hooks": {
  "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook working"}]}],
  "PreToolUse":       [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook working"}]}],
  "PostToolUse":      [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook working"}]}],
  "PermissionRequest":[{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook waiting"}]}],
  "Notification":     [{"matcher": "permission_prompt|idle_prompt|elicitation_dialog", "hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook waiting"}]}],
  "Elicitation":      [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook waiting"}]}],
  "StopFailure":      [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook waiting"}]}],
  "Stop":             [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook done"}]}],
  "SessionEnd":       [{"hooks": [{"type": "command", "command": "$HOME/Applications/Siigil.app/Contents/Resources/siigil-hook end"}]}]
}
```

`Elicitation` (a question from an MCP server) and `StopFailure` (a turn that ended in an error) are `waiting`: the agent
has stopped and it's your turn. `PostToolUse` sends `working` again after an approved permission. It works in the
terminal and in the VS Code extension. With several windows of the same app, Siigil picks the one whose title contains
the working directory's name; otherwise the ring goes on that app's icon in every workspace.

**Codex** (the ChatGPT app's Work section and the CLI) — the same script in `~/.codex/hooks.json`, with
`SIIGIL_AGENT=codex SIIGIL_BUNDLE=com.openai.codex` in front, on `UserPromptSubmit`, `PreToolUse`, `PostToolUse`
(`working`), `PermissionRequest` (`waiting`), `Stop` (`done`), `SessionEnd` and `Interrupt` (`end`). Codex doesn't run a new
hook until you approve it once (`codex` → `/hooks` → Trust), and the app reads it only after a restart; Settings › AI
accounts has buttons for both. ChatGPT's Chat runs on OpenAI's servers and can't be followed.

**Usage limits** — Claude: the usage and profile endpoints of `api.anthropic.com/api/oauth`, with the token Claude Code keeps
in the Keychain (`Claude Code-credentials`, read with `/usr/bin/security`, so there is no password prompt). ChatGPT:
`chatgpt.com/backend-api/wham/usage` with the token in `~/.codex/auth.json`. Both endpoints are undocumented: if they
change, the menu says "Not available". They are read at launch and then every 5 minutes by default (5, 10, 15 or 30 in
Settings › AI accounts), only while a mascot in the bar shows them (or has the "Session renewed!" bubble on) or the AI accounts page is open. "Session renewed!"
appears for 30 s when an exhausted 5-hour window (≥ 95 %) resets.

## Network

Every outbound connection: the usage limits above (`api.anthropic.com`, `chatgpt.com`); the update check and download
(`api.github.com`, the release zip on GitHub, `Updater.swift`); the public IP shown in the Wi-Fi menu (`api.ipify.org`, on
opening the menu, remembered 5 minutes per network, `WiFi.swift`); Spotify's album artwork (the URL Spotify gives over
AppleScript, `NowPlaying.swift`). Keep this list and the README's privacy section in sync.

## System monitor

Every 10 s Siigil reads the Mac's total load from the kernel, which is free; it runs `ps` (about 17 ms) only when the Mac
used at least one full core, when there is a culprit, or once a minute. Without a system monitor in the bar it reads
nothing. An app counts as a culprit above 100 % CPU (more than a whole core, helpers included) averaged over the last
minute; heat is "fair" thermal state or worse; memory is the kernel's memory pressure.

## Sounds

The three sounds (waits for you, done, alarm) are synthesized by the app the first time they're needed, in two voices;
there are no audio files. At most one agent sound every 5 s and one alarm a minute; each fact sounds on its own mascot,
only if it's in the bar with sound effects on. Outside the app bundle (in tests) sounds are always silent.

## Tests and image generators

    swift test

Some tests only write images, when an environment variable asks for them:

    SETTINGS_SHOTS=<dir> swift test --filter settingsShots     # Settings pages, light and dark
    MASCOT_VIDEO=<dir> swift test --filter mascotVideo         # 40 s of two mascots, PNG frames at 60 fps
    SPIN_VIDEO=<dir> swift test --filter spinVideo             # the eye spin of all nine shapes

`images/settings-mascot-*.png` are the top 1030 px of `mascot-ai-*.png` from `SETTINGS_SHOTS`; `images/bar-*.png` are
screenshots of the running app (the two sides of the notch, one above the other).

## Demo mode and the README videos

`--demo <workspaces|mascots|widgets>` starts Siigil with the real bar but its own in-memory data and a script
(`Sources/Siigil/Demo.swift`): settings in a separate `com.siigil.demo` domain wiped at every start, no AeroSpace, network,
permissions, agent socket, menus or Settings window; clicking and dragging pills only moves the sample apps (whose icons
come from the installed bundles); in the mascots scene the eye spin comes every 4–8 s instead of 25–45. An unknown scene
exits instead of starting a normal Siigil. Without `--demo` nothing changes.

`scripts/demo-video.sh <scene>` makes `images/<scene>.webp`: it builds the app, notes your settings and which Siigil is
running, quits it, launches the demo with English texts, records the bar's strip with `screencapture -v` while
`scripts/demo-pointer.swift` moves the real pointer (clicks, drags, hovers), then — even after an error or Ctrl-C — quits
the demo, checks that your settings are unchanged and reopens the Siigil that was running; finally it turns the frames
into a looping WebP. Needs `ffmpeg` and `img2webp` (Homebrew `ffmpeg`, `webp`), and Screen Recording and Accessibility
for the terminal that runs it (without Accessibility the clicks are silently lost). It moves the pointer, so leave the
Mac alone while it runs. The recorded rectangles and pointer coordinates are measured for one screen (1710 pt with the
notch): on another screen, measure them again from a still capture of the demo bar. The widgets scene puts the widgets
left of the notch, because macOS draws its screen-recording indicator over the top-right corner.

## The launch video

The launch video (28 s, 1920×1080, with music and the mascots' sounds) is made with [Remotion](https://www.remotion.dev)
in a separate local project, `~/Git/siigil-video`: `scripts/assets.sh` gathers the pieces, `npm run render` writes
`out/siigil-launch.mp4`. The README shows it from GitHub: drag the MP4 into an issue comment of this repo and put
the `https://github.com/user-attachments/assets/…` link it gets on its own line. The mascots are drawn by the app itself:
`LAUNCH_ASSETS=<dir> swift test --filter launchAssets` writes the three mascots of the video as transparent PNG
sequences (12×, 30 fps) and the sounds as WAV. The bar footage is the demo recordings that `scripts/demo-video.sh
workspaces` and `widgets` leave in `.build/demo-video/`; every text is in SF Mono, loaded from the system font file. The
music is "Creative Technology Showreel" by Pumpupthemind (Pixabay Content License, kept with its license in the
project), cut so that its drop lands on the big mascots and its last beat on the final mascot.

## Releasing

1. Raise `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Commit on `main`; the subject of this commit becomes the public release notes.
3. `make release`: runs the tests, builds, tags `v<version>`, pushes the tag and publishes the release with the zip and
   the DMG on `p-diego/siigil`, the notes being the commit subject (installed apps update from there). It stops on
   uncommitted changes, an existing tag or an ad-hoc signature (an ad-hoc release couldn't update itself).

For scripts, the zip without quarantine:

    gh release download -R p-diego/siigil -p 'Siigil-*.zip'
    unzip Siigil-*.zip && xattr -dr com.apple.quarantine Siigil.app
    mv Siigil.app ~/Applications/ && open ~/Applications/Siigil.app

## Settings icons

Each Settings icon is an Icon Composer file in `Resources/settings-icons/<name>.icon`, compiled by `actool` during the
build into a 256 px PNG, plus a dark variant from the file's dark appearance. `scripts/settings-icons/make.sh` regenerates
them from SF Symbols in the style of `template.json` (see `Resources/settings-icons/README.md`).

## Licenses

`LICENSE` is copied into the app as `Licenses/Siigil.txt`, next to the third-party licenses in `Resources/Licenses/`
(theme palettes). The credits shown in Siigil › About Siigil are `Credits.rtf`; the copyright line comes from
`NSHumanReadableCopyright` in `Info.plist`.
