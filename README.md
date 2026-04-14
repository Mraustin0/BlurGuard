# BlurGuard

A macOS menu bar app that automatically blurs your screen when idle, protecting privacy in public places like cafes or co-working spaces. No camera required — idle time detection only.

## Features

- Fullscreen blur overlay on all displays after configurable idle timeout
- 10-second countdown warning before blur activates
- Touch ID or password authentication to unlock
- Covers all connected screens simultaneously
- Runs silently in the menu bar, no Dock icon
- Configurable timeout: 15 sec, 30 sec, 1 min, 2 min, 5 min, 10 min

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later (to build from source)

## Installation

### Option 1 — DMG Installer

1. Download `BlurGuard-1.0.dmg` from the [Releases](https://github.com/Mraustin0/BlurGuard/releases) page
2. Open the DMG file
3. Drag `BlurGuard.app` into the `Applications` folder
4. Open BlurGuard from Applications or Spotlight

### Option 2 — Build from Source

1. Clone the repository

```bash
git clone https://github.com/Mraustin0/BlurGuard.git
cd BlurGuard
```

2. Open the project in Xcode

```bash
open BlurGuard.xcodeproj
```

3. Select your Mac as the run destination and press `Cmd+R`

## First Launch

When BlurGuard first runs, macOS may ask for **Accessibility** permission. This is required for the app to detect keyboard and mouse input while the screen is blurred.

To grant permission:

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Enable **BlurGuard** in the list
3. If BlurGuard is not in the list, click the `+` button and add it from Applications

Without this permission, BlurGuard will fall back to polling-based detection, which still works but is less responsive.

## Usage

After launching, a shield icon appears in the menu bar.

- **Enabled** — toggle blur protection on or off
- **Settings** — configure idle timeout and authentication requirement
- **Quit** — exit the app

The screen will blur automatically after the configured idle period. Move the mouse or press any key to trigger the unlock prompt.

## Settings

| Option | Description |
|--------|-------------|
| Idle timeout | How long the system must be idle before the screen blurs (15 sec – 10 min) |
| Require authentication | If enabled, Touch ID or password is required to unlock. If disabled, any input unlocks immediately |

## Security Notes

- The `requireAuth` setting is stored in the system Keychain, not in a plain preferences file
- The idle timeout value is clamped between 10 seconds and 10 minutes regardless of manual edits
- App Sandbox is disabled because `CGEventTap` and `AXIsProcessTrusted` require direct system access; these APIs are unavailable in a sandboxed environment

## License

MIT
