# Rsync 纪

Rsync 纪 is a native macOS SwiftUI app for creating, editing, and running `rsync` profiles with live logs, grouped option presets, script generation, and Finder integration.

## Download

- Project: https://github.com/olojiang/rsync_gui
- Latest release: https://github.com/olojiang/rsync_gui/releases/latest
- All releases: https://github.com/olojiang/rsync_gui/releases

Download `RsyncJi-macOS.zip` from the latest release, unzip it, and move `Rsync 纪.app` to `/Applications`.

## Build Locally

```bash
swift build
```

To build a macOS app bundle with the project icon:

```bash
./scripts/build_app.sh
```

To build and launch:

```bash
./run-app.sh
```

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later
- `rsync` installed at `/usr/bin/rsync`, `/usr/local/bin/rsync`, or `/opt/homebrew/bin/rsync`

## Highlights

- Live stdout/stderr logs, including `rsync` carriage-return progress updates.
- Per-run log files under `~/Library/Logs/RsyncGUI`.
- App diagnostics under `~/Library/Logs/RsyncGUI/app.log`.
- True process cancellation from the UI.
- Closing the app window or quitting the app terminates active rsync child processes.
- The profile editor opens in an independent AppKit panel centered on the main window.
- Refuses to start rsync when the source or destination directory does not exist.
- Grouped classic presets, including `-a --human-readable --info=progress2`.
- Prefers newer Homebrew rsync at `/opt/homebrew/bin/rsync` or `/usr/local/bin/rsync`; falls back to `/usr/bin/rsync`.
- Automatically downgrades `--info=progress2` to `--progress` when only an old rsync is available.
- Full command wrapping in the execution panel.
- Configurable generated-script directory with automatic directory creation.
- Generated scripts are revealed and selected in Finder after saving.
