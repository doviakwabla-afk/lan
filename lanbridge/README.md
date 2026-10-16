# LanBridge — Windows + Android LAN sharing starter

This is a Flutter starter project inspired by local-network sharing apps. It includes a Material UI, UDP LAN discovery, a receiving HTTP endpoint, file picking, and file transfer between devices on the same trusted network.

## Important security status

**This is a development starter, not a production-secure LocalSend replacement.** Transfer traffic uses plain HTTP, discovery is unauthenticated, and the pairing code is a simple shared secret rather than a cryptographically bound session. Use only on a trusted test network. Do not send sensitive files. Before production use, implement HTTPS with certificate fingerprint verification, authenticated discovery/pairing, an explicit receiver approval dialog before writing each file, replay protection, robust quotas, and automated security tests.

## Requirements

- Flutter SDK (stable)
- Android Studio / Android SDK for APK builds
- Windows with Flutter desktop support enabled for Windows `.exe` builds

## Setup

```bash
flutter doctor
flutter config --enable-windows-desktop
flutter create . --platforms=windows,android
flutter pub get
flutter analyze
flutter run -d windows
```

On Android, enable developer options and USB debugging, connect a device, then run:

```bash
flutter run -d <device-id>
```

## Build artifacts

Build Windows on Windows:

```bash
flutter build windows --release
```

The app's executable and runtime files will be in:
`build\windows\x64\runner\Release\`

Build Android APK:

```bash
flutter build apk --release
```

APK output:
`build/app/outputs/flutter-apk/app-release.apk`

A Windows executable is not a single self-contained file in a typical Flutter build; distribute the full Release directory or wrap it in an installer. Android APK builds should be signed with your own release key before public distribution.

## First LAN test

1. Install/run LanBridge on two devices connected to the same Wi-Fi.
2. On the receiving device, select **Enable receiving** and keep the displayed pairing code private.
3. On the sending device, select **Find devices**.
4. Select a device, choose a file, and enter the receiver's code.
5. The receiving device stores files in its application documents folder under `LanBridge Received`.

## Current MVP limitations

- HTTP is not encrypted (test use only).
- Receiver approval is not yet interactive per file.
- UDP broadcast may be blocked by guest Wi-Fi, client isolation, VPNs, or firewalls.
- This first version transfers one file at a time, with a 100 MiB limit.
- Clipboard synchronization, QR pairing, transfer cancellation/progress, history persistence, and installer packaging are not implemented yet.
- Android and Windows builds must be compiled on a machine with the appropriate SDK/toolchain. The current source-generation environment does not have Flutter installed.
