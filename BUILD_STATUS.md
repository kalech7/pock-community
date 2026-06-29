# Build Status

Last verified: 2026-06-29

## Summary

Pock Community builds successfully in the local development environment with full Xcode selected through `DEVELOPER_DIR`.

## Detected Project Setup

- Language: Swift, with Objective-C bridging/private framework code.
- Platform: macOS app for Touch Bar Macs.
- Build system: Xcode workspace.
- Dependency manager: CocoaPods.
- Main project files: `Pock.xcodeproj`, `Pock.xcworkspace`, `Podfile`.
- Deployment target: macOS 10.15.
- App version: `0.10.0` build `6`.
- App bundle identifier: `io.github.kalech7.pock-community`.

## Dependencies

Declared in `Podfile`:

- `PockKit` from `git@github.com:pock/pockkit.git`
- `Magnet`
- `Zip`

CocoaPods also installs transitive dependencies including `Sauce` and `TinyConstraints`.

Telemetry, analytics, and crash-reporting dependencies are not used by this fork.

## Verified Commands

```sh
pod install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -workspace Pock.xcworkspace
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pock.xcworkspace -scheme "Pock (Pock project)" -configuration Release build CODE_SIGNING_ALLOWED=NO
```

## Results

- `pod install`: succeeded.
- `xcodebuild -list -workspace Pock.xcworkspace`: succeeded.
- Release build with `CODE_SIGNING_ALLOWED=NO`: succeeded.
- `./scripts/install_app.sh`: not run during this verification because it replaces `/Applications/Pock.app`; use it for a local smoke test when that is intended.

## Known Warnings

CocoaPods reports that the `Pock` Debug and Release targets override `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES` from the Pods xcconfig files. This warning is existing project configuration and did not block the verified Release build.

Xcode reports that some run script phases do not specify outputs and therefore run during every build. This did not block the verified Release build.

## Notes For Contributors

Use full Xcode, not Command Line Tools only. If `xcodebuild` reports that the active developer directory is Command Line Tools, either set:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

or run:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Do not commit local signing, provisioning, developer team, or certificate changes unless a maintainer explicitly requests them.
