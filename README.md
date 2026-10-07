# BlackTea — menu bar keep-awake for macOS

A tiny native (Swift/AppKit) Amphetamine/Caffeine replacement. Universal (Apple Silicon + Intel), macOS 13+.

## Use

Click the cup in the menu bar (outline = off, filled = keeping the Mac awake):

- **Keep Awake**: on/off. Turning it on uses the remembered duration.
- **Duration ▸** 1, 2, 3, 5, 8, 13 Hours, 1 Day, Indefinitely. Picking one starts (or restarts) the timer from now.
  While on, the time left shows under Keep Awake (and in the cup's tooltip).
- **Keep Display Awake**: also keep the screen on (default off). Otherwise only idle *system* sleep is blocked
  and the display can still dim/sleep.
- **Start at Login** (default on; registered on first launch from an installed location).
- **Quit BlackTea**.

How it works: an IOKit power assertion (`PreventUserIdleSystemSleep`, plus `PreventUserIdleDisplaySleep` when the
display option is on), released when the timer ends, when turned off, or when the app quits/crashes.
Check with `pmset -g assertions`. With the lid closed, macOS still sleeps unless power and an external display are connected.

Remembered across relaunch (UserDefaults `com.beedesk.blacktea`): duration, display option, and on/off.
If it was on **Indefinitely**, it comes back on. If it was on with a **timer**, it resumes with the time that
was left (the original end time; a relaunch or reboot never extends it). A timer that ran out while BlackTea
wasn't running stays off.

## Install

Open `/Users/Shared/BlackTea/BlackTea-<ver>.dmg` and drag **BlackTea** to Applications (or unzip the .zip / copy
`BlackTea.app`), then launch it. It is ad-hoc signed (not notarized); copies from `/Users/Shared` carry no quarantine
flag, so it opens directly. If macOS ever refuses: right-click → Open, or System Settings → Privacy & Security → Open Anyway.
macOS shows a "Login item added" notice on first launch; manage it in System Settings → General → Login Items & Extensions.

## Build

```bash
./build.sh             # .build/BlackTea.app (universal, ad-hoc signed)
./scripts/release.sh   # build + self-test + zip/dmg, published to /Users/Shared/BlackTea
```

CLI: `BlackTea.app/Contents/MacOS/BlackTea --self-test` (timer math, persistence/resume, and real assertions
verified against `pmset -g assertions`; never touches your settings or login item) and `--version`.
