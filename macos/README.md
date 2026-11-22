# macOS implementation

This directory contains the Catalina-compatible AppKit menu-bar application.
The package deployment target is macOS 10.15 and the release build is x86_64
only.

## Build from source

Requirements: an Intel Mac, Xcode with the macOS 10.15 deployment target, Node
20/npm, and internet access for the fixed Node v20.18.0 archive and npm
dependencies.

```bash
cd macos
swift test --arch x86_64
CONFIG=release VERSION=0.1.0 BUILD_VERSION=0.1.0 scripts/make-app.sh
scripts/check-minos.sh build/Switchboard.app
```

`make-app.sh` always sets `MACOSX_DEPLOYMENT_TARGET=10.15`, compiles only
x86_64, embeds Node v20.18.0, rebuilds `node-pty` from source for the same
deployment target, and signs all Mach-O files ad hoc. It does not include
Sparkle, Developer ID signing, or notarization.

## Architecture

- `SwitchboardApp.swift`: `NSApplicationDelegate` entry and headless checks.
- `MenuContent.swift`: native `NSStatusItem` and `NSMenu` controller.
- `Prefs.swift`: settings plus the `~/Library/LaunchAgents` login item.
- `DaemonSupervisor.swift`: Node child-process lifecycle and live status.
- `DaemonUpdater.swift`: integrity-checked npm CLI hot updates. Its networking
  uses Catalina-compatible URLSession completion handlers.
- `scripts/check-minos.sh`: fails unless the app, Node, and every `pty.node` are
  x86_64 with `minos <= 10.15`.

For day-to-day source development, `run-dev.sh` points the app at `../cli` and
the Node executable on `PATH`. Launch-at-login intentionally refuses a bare
SwiftPM executable; install the packaged app first.
