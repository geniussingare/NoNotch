# noNotch™

**Your notch, reimagined.** noNotch turns the MacBook notch into a living Dynamic Island: music and video, notifications, live activities, quick controls, notes, a file shelf and more. It uses real Liquid Glass and iPhone-style motion, and idles at about 0% CPU.

A GeniusSoft™ product.

## Features

- **Now Playing:** Spotify, Apple Music, YouTube, Netflix, VLC, IINA and anything else that reports to macOS Now Playing. Artwork, scrubbing, AirPlay, ±15 s skips for video, live synced lyrics.
- **Notifications in the notch:** system banners appear as iOS-style banners growing out of the island, with a history.
- **Live activities:** charging, low battery, AirPods and Bluetooth, downloads, meetings, focus timer, 20-20-20 eye-break reminders.
- **Volume & brightness HUD:** replaces the system overlay with a slim bar in the notch.
- **Quick controls:** Wi‑Fi, Bluetooth, Focus, Dark Mode, Keep Awake, sliders, screenshot, lock and a camera mirror.
- **Productivity:** file shelf with AirDrop, clipboard history, quick notes, calendar grid with Join buttons, weather.
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

## Project layout

- `noNotch/App`: app lifecycle, menu bar, hotkey, demo mode
- `noNotch/Window`: notch panel, screen geometry, hover and gesture tracking
- `noNotch/Core`: view model, live-activity queue, services, settings, permissions
- `noNotch/UI`: island shape, Liquid Glass background, design system, views
- `noNotch/Features`: Media, Live, QuickSettings, Productivity, Widgets
- `noNotchTests`: unit and snapshot tests
- `website`: landing page
- `scripts`: signing, release, DMG artwork, icon, visual checks
- `Vendor/MediaRemoteAdapter`: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause), used for Now Playing on macOS 15.4+

## License

© 2026 GeniusSoft™. All rights reserved. noNotch™ is a trademark of GeniusSoft.
Bundled third-party code keeps its own license (see `Vendor/MediaRemoteAdapter/LICENSE`).
