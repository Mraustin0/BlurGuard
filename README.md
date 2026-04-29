# BlurGuard

A macOS menu bar app that protects your screen from prying eyes. It blurs your display when you walk away, when someone peeks over your shoulder, when you go idle, or whenever you press a hotkey. Touch ID or password unlocks.

Everything runs on-device. The camera frames never leave your Mac. Nothing is uploaded, logged, or transmitted.

## Features

- Idle blur with a 10-second cancel countdown
- Camera-based walk-away and over-the-shoulder peek detection (off by default, opt in)
- Manual blur via global hotkey (default Shift+Cmd+L)
- Touch ID or password unlock, with a separate setting for camera triggers
- Auto-pause for apps where blur would be disruptive (Zoom, Teams, Webex, FaceTime by default)
- Multi-monitor support
- Live counter of how many peek events were detected today
- Pause for one hour from the menu

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later (only if you want to build from source)

## Installation

### Option 1 — DMG installer

1. Download `BlurGuard-1.0.dmg` from the [Releases page](https://github.com/Mraustin0/BlurGuard/releases).
2. Open the DMG and drag `BlurGuard.app` into your `Applications` folder.
3. The app is not signed with an Apple Developer ID, so the first time you launch it macOS will block it. Right-click `BlurGuard.app` in `Applications` and choose **Open**, then click **Open** again in the dialog. After this one-time approval, it will launch normally.

### Option 2 — Build from source

```bash
git clone https://github.com/Mraustin0/BlurGuard.git
cd BlurGuard
open BlurGuard.xcodeproj
```

Press Cmd+R in Xcode to run.

## Permissions

BlurGuard asks for two macOS permissions. Both are required for full functionality, but the app still works in a degraded mode if you skip them.

### Accessibility (recommended)

Used to detect keyboard and mouse activity while the screen is blurred so it can dismiss the blur the moment you touch the Mac. Also required for the global hotkey to fire from any app.

How to grant:

1. Open **System Settings** > **Privacy and Security** > **Accessibility**.
2. Click the `+` button, navigate to `Applications`, select `BlurGuard.app`, and click **Open**.
3. Make sure the toggle next to BlurGuard is on.
4. Quit and relaunch BlurGuard for the change to take effect.

If you skip this, BlurGuard falls back to a 1-second polling loop. The unlock will still work but feels slightly less snappy, and the global hotkey will not fire.

### Camera (optional, off by default)

Only used if you turn on **Camera protection** in the settings panel. The app processes one video frame per second using Apple's on-device Vision framework to count faces. It does not record video, take stills, or send anything over the network.

How to grant:

1. Open the BlurGuard settings panel from the menu bar icon.
2. Toggle **Camera protection** on.
3. macOS will show the standard camera permission prompt the first time. Click **OK**.
4. If you accidentally clicked **Don't Allow**, open **System Settings** > **Privacy and Security** > **Camera** and toggle BlurGuard on.

If you deny camera access later, the toggle in BlurGuard will switch off automatically.

## Settings

Click the shield icon in the menu bar to open the settings panel.

| Setting | What it does |
|---------|--------------|
| Peek Response | What to do when a second face appears in front of the camera. Blur means just dim the screen; Lock means require Touch ID or password to unlock. |
| Walk-Away Response | Same options, applied when no face is detected for the configured delay. |
| Camera Sensitivity | Higher values trigger from worse angles or further away. Lower values reduce false positives but require the user to be more centered. |
| Camera protection | Master toggle for the camera-based detection. |
| Walk-away delay | How many seconds of no-face detection counts as the user being away. 3, 5, 8, or 15 seconds. |
| Idle lock after | How long of no keyboard or mouse activity triggers the blur. 15 sec to 10 min. |
| Require auth | When on, Touch ID or password is needed to unlock idle and manual blurs. (Camera trigger uses its own setting above.) |
| Instant lock hotkey | Global keyboard shortcut to blur immediately. |
| Auto-Pause Apps | List of apps that suppress all blur triggers while running. Useful for video calls. |

The bottom row has **Pause 1 hour** to disable all detection temporarily, and **Quit** to fully exit.

## Screenshots

Screenshots live under `docs/screenshots/`. Add them there and reference them from this section.

- Menu bar icon and settings popover
- Idle countdown overlay
- Walk-away blur overlay ("You Walked Away")
- Peek blur overlay ("Someone's Watching")
- Touch ID unlock prompt

## How it works

- **Idle detection**: Polls `CGEventSource.secondsSinceLastEventType` once a second across all input types. When idle time exceeds the configured threshold, a 10-second countdown shows; any input cancels it.
- **Camera detection**: Captures the front camera at low resolution, samples one frame per second, runs `VNDetectFaceRectanglesRequest` locally. Two or more faces is a peek; zero faces for N seconds is walk-away.
- **Wake-on-input**: While blurred, a `CGEventTap` (in listen-only mode, so it never suppresses your keystrokes) detects any input and prompts for Touch ID. Without Accessibility permission, the app falls back to polling the same idle clock used for idle detection.
- **State machine**: All state transitions are serialized through a private dispatch queue to avoid races. The published state is mirrored to the main thread for SwiftUI.
- **Storage**: Most settings live in `UserDefaults`. The `requireAuth` flag is stored in the system Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) so it can't be flipped by editing a plist.

## Privacy and security

- All face detection runs locally using Apple's Vision framework. No frames or face data are written to disk or sent anywhere.
- App Sandbox is intentionally disabled because `CGEventTap` and `AXIsProcessTrusted` require non-sandboxed access. The app does not request network entitlements.
- The peek counter is stored only in `UserDefaults` on this Mac. It resets at midnight.
- See [PRIVACY.md](PRIVACY.md) for the full statement.

## Compatibility

The deployment target is macOS 13.0. Every API used is available in macOS 13 and tested with the macOS 14 and 15 SDKs. If you find a regression on a specific OS version, please open an issue with the macOS version and a brief reproduction.

## License

MIT. See [LICENSE](LICENSE).
