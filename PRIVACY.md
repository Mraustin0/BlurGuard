# Privacy Policy

Last updated: 2026-04-29

BlurGuard is a privacy tool, so it would be hypocritical of it to collect data about you. The short version is: it does not.

This document explains exactly what data BlurGuard touches, where that data lives, and what it never does.

## What BlurGuard accesses on your Mac

### Camera (only when you turn the feature on)

If you enable **Camera protection** in the settings panel, BlurGuard activates the front-facing camera at low resolution and samples one video frame per second.

Each frame is processed by Apple's **Vision** framework on your Mac to count how many face rectangles appear. The result of that processing is an integer (the number of faces). The frame itself is then immediately released by the operating system.

- Frames are never saved to disk.
- Frames are never sent over the network.
- Faces are never identified, recognized, or compared against any database.
- The Vision request runs entirely on-device using Apple's CoreML models.

When you turn **Camera protection** off, the camera session is stopped immediately and is not reactivated until you turn it on again.

### Keyboard and mouse activity (idle detection only)

BlurGuard reads the system-wide idle time from `CGEventSource.secondsSinceLastEventType` once per second. This API only returns the number of seconds since the last input event. It does not return the content of those events, nor what application received them.

While the screen is blurred, BlurGuard installs a `CGEventTap` in **listen-only** mode. This means the tap observes when input occurs but the events are not modified, recorded, or suppressed. They flow through to the active application unchanged. The tap is removed as soon as the screen is unblurred.

### Running applications

BlurGuard reads the list of currently running application bundle identifiers via `NSWorkspace.runningApplications`. It checks this list against your **Auto-Pause Apps** allowlist to decide whether to skip a blur trigger. The list is read into memory only when a trigger fires and is not stored.

### Authentication

If you have **Require auth** enabled, BlurGuard uses Apple's `LocalAuthentication` framework to verify your Touch ID or account password. This entire process is handled by macOS. BlurGuard receives only a success or failure result.

## What BlurGuard stores

| Setting | Stored in | Notes |
|---------|-----------|-------|
| Idle timeout, hotkey, response actions, sensitivity, walk-away delay, ignored apps, peek count | `UserDefaults` (a plist on your Mac) | Standard preferences. Lives in `~/Library/Preferences/com.blurguard.app.plist`. |
| `requireAuth` flag | macOS Keychain | Stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so it cannot be backed up to another device or read while the Mac is locked. |
| Peek counter | `UserDefaults` | A single integer plus the date it was last updated. Resets at midnight. |

That is the complete list of persisted data.

## What BlurGuard never does

- It does not connect to the internet. The application has no network entitlements and makes no network calls.
- It does not collect telemetry, analytics, crash reports, or usage statistics.
- It does not have a server. There is no BlurGuard backend.
- It does not include any third-party SDKs that could collect data.
- It does not write camera frames, screenshots, keystrokes, or input events to disk.
- It does not share any information with the developer, Apple, or anyone else.

## Permissions you grant

You may grant BlurGuard up to two macOS-level permissions:

1. **Accessibility** — used so the event tap can detect input while the screen is blurred and so the global hotkey can fire from any frontmost app.
2. **Camera** — used only if you enable the camera-based detection feature.

You can revoke either permission at any time in **System Settings** > **Privacy and Security**. The app will degrade to a less responsive fallback (in the case of Accessibility) or disable the corresponding feature (in the case of Camera).

## Source code

BlurGuard is open source. You can verify every claim in this document by reading the source at https://github.com/Mraustin0/BlurGuard.

The relevant files for this policy are:

- `BlurGuard/CameraPresenceMonitor.swift` — camera capture and face counting
- `BlurGuard/IdleMonitor.swift` — idle time polling
- `BlurGuard/BlurStateManager.swift` — event tap and ignored-app checks
- `BlurGuard/SettingsManager.swift` — what is stored and where
- `BlurGuard/UnlockHandler.swift` — authentication
- `BlurGuard/BlurGuard.entitlements` — list of granted entitlements (sandbox off, no network)

## Contact

Issues and questions: https://github.com/Mraustin0/BlurGuard/issues
