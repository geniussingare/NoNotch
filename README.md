# noNotch™

**Your notch, reimagined.** noNotch turns the MacBook notch into a living Dynamic Island: music and video, notifications, live activities, quick controls, notes, a file shelf and more. It uses real Liquid Glass and iPhone-style motion, and idles at about 0% CPU.

A GeniusSoft™ product.

## Features

- **Now Playing:** Spotify, Apple Music, YouTube, Netflix, VLC, IINA and anything else that reports to macOS Now Playing. Artwork, scrubbing, AirPlay, ±15 s skips for video, live synced lyrics.
- **Notifications in the notch:** system banners appear as iOS-style banners growing out of the island, with a history.
- **Live activities:** charging, low battery, AirPods and Bluetooth, downloads, meetings, focus timer, 20-20-20 eye-break reminders.
- **Volume & brightness HUD:** replaces the system overlay with a slim bar in the notch.
- **Quick controls:** Wi‑Fi, Bluetooth, Focus, Dark Mode, Keep Awake, sliders, screenshot, lock and a camera mirror.
- **Tasks:** type naturally ("call mom tomorrow at 5pm every week #family !high") or dictate. Priorities, projects, steps, notes, repeats, an Upcoming planner, and unfinished work rolls forward. When a reminder is due the notch opens with a chime, Snooze and Done.
- **Focus:** countdown or stopwatch, with or without a task, +5 min, pauses while the Mac sleeps. Ring, digital or minimal clock.
- **Notepad & Insights:** a daily page where ⌘↩ turns a line into a task; a week of tasks done, focus time and peak hours.
- **Apple Reminders sync (optional):** two-way with a "noNotch" list, so tasks reach iPhone and Apple Watch.
- **Apple Intelligence (macOS 26+):** suggested priority and project for new tasks, on device.
- **AI agents:** a built-in MCP server. Settings → AI agents connects Claude Code, the Claude app or Cursor in one click.
- **Productivity:** customizable Home cards, file shelf with AirDrop, clipboard history, calendar grid with Join buttons, weather.
- **Any display:** Macs and monitors without a notch get a pull-cord you tug to open the island.

## Requirements

macOS 14 Sonoma or later. Liquid Glass needs macOS 26 or later; older systems get a translucent material. Apple Silicon and Intel.

## Build

```sh
brew install xcodegen
scripts/setup-signing.sh      # once: local signing identity so permissions persist across builds
xcodegen generate
xcodebuild -scheme noNotch -configuration Release -derivedDataPath build build
open build/Build/Products/Release/noNotch.app
```

## Release

```sh
scripts/release.sh            # universal app → dist/noNotch-<version>.dmg + .zip + SHA256SUMS.txt
```

Set `SIGN_IDENTITY` to a Developer ID and `NOTARY_PROFILE` to a `notarytool` keychain profile for a notarized build.

## Test

```sh
xcodebuild test -scheme noNotch -derivedDataPath build/test
scripts/visual-check.sh       # screenshots every notch state (needs Screen Recording for your terminal)
```

## MCP server

Tasks, notes and insights live in `~/Library/Application Support/noNotch/store.json`. The helper reads and writes it directly (under a file lock), so data tools work even when the app is closed. Focus tools need the app running. To set it up by hand:

```sh
claude mcp add --scope user nonotch -- "/Applications/noNotch.app/Contents/Helpers/nonotch-mcp"
```

Tools: `list_tasks`, `add_task`, `update_task`, `complete_task`, `delete_task`, `get_note`, `append_note`, `get_insights`, `focus_start`, `focus_pause`, `focus_resume`, `focus_add_five`, `focus_stop`, `focus_status`.

## Permissions

All permissions are requested together on first launch, and everything stays on your Mac.

| Permission | Used for |
|---|---|
| Accessibility | Notifications in the notch, volume/brightness HUD, media-key fallback |
| Calendar | Next meeting, Join button, month grid |
| Location | Local weather |
| Camera | Mirror |
| Bluetooth | AirPods and device connections |
| Automation | Music/Spotify fallback, dark mode toggle |
| Downloads folder | Download progress |
| Reminders (optional) | Two-way task sync |
| Microphone & Speech (optional) | Dictation, recognised on the Mac |

## Project layout

- `noNotch/App`: app lifecycle, menu bar, hotkey, demo mode
- `noNotch/Window`: notch panel, screen geometry, hover and gesture tracking
- `noNotch/Core`: view model, live-activity queue, services, settings, permissions
- `noNotch/UI`: island shape, Liquid Glass background, design system, views
- `noNotch/Features`: Media, Live, QuickSettings, Productivity, Tasks, Agents, Widgets
- `noNotch/Shared`: task model, store file and parser, shared with the MCP helper
- `noNotchMCP`: `nonotch-mcp`, the stdio MCP server embedded at `noNotch.app/Contents/Helpers`
- `noNotchTests`: unit and snapshot tests
- `website`: landing page
- `scripts`: signing, release, DMG artwork, icon, visual checks
- `Vendor/MediaRemoteAdapter`: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause), used for Now Playing on macOS 15.4+

## License

© 2026 GeniusSoft™. All rights reserved. noNotch™ is a trademark of GeniusSoft.
Bundled third-party code keeps its own license (see `Vendor/MediaRemoteAdapter/LICENSE`).
