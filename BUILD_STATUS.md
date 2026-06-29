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
- App version: `0.10.0` build `7`.
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
./scripts/sign_app.sh "$HOME/Library/Developer/Xcode/DerivedData/Pock-fgcdlnkhwvjnuwbrhagpqbmhbpcs/Build/Products/Release/Pock.app"
open /Applications/Pock.app
```

## Results

- `pod install`: succeeded.
- `xcodebuild -list -workspace Pock.xcworkspace`: succeeded.
- Release build with `CODE_SIGNING_ALLOWED=NO`: succeeded.
- `./scripts/sign_app.sh`: succeeded with `Pock Local Code Signing`.
- Installed `/Applications/Pock.app`: version `0.10.0` build `7`, signed with the same local certificate requirement as build `5`.
- Local launch from `/Applications/Pock.app`: stayed running for 1 minute 33 seconds with no new crash reports and low sampled CPU.
- `./scripts/install_app.sh`: updated to sign installed builds; use it when replacing `/Applications/Pock.app` is intended.

## Known Warnings

CocoaPods reports that the `Pock` Debug and Release targets override `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES` from the Pods xcconfig files. This warning is existing project configuration and did not block the verified Release build.

Xcode reports that some run script phases do not specify outputs and therefore run during every build. This did not block the verified Release build.

## Permission Preservation

macOS permissions such as Accessibility are tied to the app identifier and code-signing requirement. To preserve already-granted permissions between local community builds, keep the bundle identifier as `io.github.kalech7.pock-community`, install over `/Applications/Pock.app`, and sign with the same `Pock Local Code Signing` identity.

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
