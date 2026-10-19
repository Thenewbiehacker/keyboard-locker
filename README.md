# Keyboard Locker

A tiny macOS utility that **locks your keyboard so you can clean it** — wipe the keys, blow out crumbs, dust between them — without your Mac reacting to every press. Your mouse and trackpad keep working the whole time.

Press a button, the keyboard goes quiet for 3 seconds of countdown, and then stay as rough as you like with the keys. **Hold Space for 5 seconds to unlock**, and the app quits itself. If you forget about it, it **auto-exits after 60 seconds**.

## Features

- **Swallows every key press** while locked (`keyDown` / `keyUp`) through a session-level `CGEventTap`. Pointer movement and clicks are never blocked.
- **Locks the Fn / Globe key too** — and Shift, Command, Option, Control and Caps Lock along with it — so you can clean right around them.
- **Blocks media & brightness keys** (play/pause, volume, brightness) with a second HID-level tap.
- **3-second countdown** before the lock engages, with **Esc to cancel**.
- **Unlock from the keyboard: hold Space for 5 seconds** (adjustable 2–10 s). The app unlocks and quits itself.
- **60-second auto-exit.** Forget about it and the lock lifts and the app closes on its own.
- **Mouse-only emergency unlock.** Hold the on-screen pill for 3 seconds.
- **Fails open.** If macOS keeps disabling the event tap, the app releases the keyboard instead of trapping you.
- **Releases stuck modifiers** on unlock, so nothing comes back as "held down".
- Keeps the display awake while the keyboard is locked.

## Requirements

- macOS 13 (Ventura) or newer
- **Accessibility** and **Input Monitoring** permission for the app (it walks you through both)

## Install

```bash
git clone https://github.com/Thenewbiehacker/keyboard-locker.git
cd keyboard-locker
./build.sh              # build + install into /Applications + launch
./build.sh --no-open    # build + install, do not launch
```

The script builds the release binary with SwiftPM, assembles `Keyboard Locker.app`, gives it an icon, signs it, installs it into `/Applications` (falling back to `~/Applications`) and refreshes Launch Services so it shows up in **Launchpad**, **Spotlight** and the **Applications** folder.

Then grant the two permissions when asked:

- System Settings › Privacy & Security › **Accessibility**
- System Settings › Privacy & Security › **Input Monitoring**

If no Developer ID certificate is present the app is signed ad-hoc, so macOS may ask for the permissions again after a rebuild — just re-enable them.

Building manually also works:

```bash
swift build -c release
# the binary is .build/release/KeyboardLocker (needs the app bundle for permissions)
```

## Usage

1. Open **Keyboard Locker** from Launchpad, Spotlight or `/Applications`. It lives in the menu bar (keyboard icon) and has no Dock icon.
2. Click **Lock Keyboard**. Take your hands off the keys — the lock engages after a 3-second countdown (press **Esc** to cancel).
3. Clean the keyboard. The pointer still works normally.
4. Unlock by **holding Space for 5 seconds**, or by holding the on-screen pill with the mouse for 3 seconds. Either way the app then quits itself; it never stays running after unlocking.
5. If you walk away, it **auto-exits 60 seconds** after the lock engaged.

The main window lets you change the hold duration (2–10 s), and toggle Fn/Globe-key and media-key blocking.

## How it works

`KeyboardLock` installs a `CGEventTap` at `cgSessionEventTap` and returns `nil` for every keyboard event, which swallows it. A second tap at `cghidEventTap` scoped to `NX_SYSDEFINED` catches media and brightness keys that are consumed below the session tap. Mouse events are never in the event mask, so the pointer keeps working.

Hold timing uses `ProcessInfo.systemUptime` (monotonic), so it can't be disturbed by clock changes. The space-hold is tracked inside the tap callback, which is why it works even though the very events it needs are being swallowed.

`LockController` owns the UI and the lifecycle: permission checks, the 3-second countdown, the full-screen overlay on every display, the auto-exit timer, and the terminate-on-unlock flow.

| File | Role |
|---|---|
| `Sources/KeyboardLocker/KeyboardLock.swift` | Event taps, space-hold detection, auto-unlock timer |
| `Sources/KeyboardLocker/LockController.swift` | App state, overlays, countdown, quit-on-unlock |
| `Sources/KeyboardLocker/Views/` | SwiftUI main window and full-screen lock overlay |
| `Sources/KeyboardLocker/Permissions.swift` | Accessibility / Input Monitoring checks and settings deep links |
| `Sources/KeyboardLocker/PowerAssertion.swift` | Keeps the display awake while locked |
| `build.sh` | Builds, signs and installs the `.app` |
| `tools/make-icon.swift` | Generates the app icon |

## Safety

- Only the keyboard is blocked — the pointer is never blocked.
- There are always three ways out: hold **Space**, hold the mouse **pill**, or wait for the **60-second auto-exit**.
- `pkill -x KeyboardLocker` from Terminal also releases the keyboard instantly, because the tap dies with the process.

## License

Released under the MIT License — see [LICENSE](LICENSE).
