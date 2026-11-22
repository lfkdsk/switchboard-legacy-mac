# Switchboard Legacy Mac v0.1.0

First prerelease for **macOS 10.15 Catalina on Intel x86_64**.

This port is based on upstream Switchboard commit
`a00cd56a8ee765f9f695a58b66dc67732f0b7ca1`. It replaces the macOS 13 SwiftUI
menu and `SMAppService` login item with Catalina-compatible AppKit and a user
LaunchAgent. The embedded runtime remains Node.js v20.18.0, and CLI hot updates
remain enabled. Sparkle app self-update has been removed.

## Important prerelease notes

- Built and inspected on GitHub's Intel macOS runner; **not yet verified on a
  physical macOS 10.15.7 machine**.
- Intel x86_64 only; there is no arm64 slice.
- Ad-hoc signed and not notarized. No Apple signing secrets are used.

## Install

1. Download and open `Switchboard-0.1.0-Catalina-x64.dmg`.
2. Drag `Switchboard.app` to `/Applications`.
3. Control-click the app in Finder, select **Open**, and confirm.

If Gatekeeper still blocks the app:

```bash
xattr -dr com.apple.quarantine /Applications/Switchboard.app
open /Applications/Switchboard.app
```

Please treat login flow, LaunchAgent behavior, Full Disk Access, and real relay
sessions as needing Catalina hardware validation before relying on this build.
