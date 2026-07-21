# Pock Community

Pock Community is an unofficial community-maintained fork of [Pock](https://github.com/pock/pock), a macOS app for MacBook models with a physical Touch Bar.

This fork is not the official Pock project and is not endorsed by the original authors. The purpose of this repository is to keep Pock usable for Touch Bar Mac users while preserving the original MIT license, copyright notices, and attribution.

## Status

- App name used by this repository: **Pock Community**
- Distributed app bundle: `Pock.app`
- Current app version in the Xcode project: `0.10.1` build `11`
- Telemetry: none. Analytics and crash-reporting dependencies have been removed.
- Primary platform: macOS on MacBook models with a physical Touch Bar
- License: MIT, with original attribution preserved in [LICENSE.md](LICENSE.md)

## Visible Disclaimer

Pock Community is an unofficial fork. Do not present this repository, its releases, or its builds as the official Pock project. If you redistribute builds, keep the original license and attribution intact and make the community-maintained status clear.

## Installation

Download the latest zip from this repository's GitHub Releases page, unzip it, and move `Pock.app` to `/Applications`.

On first launch, Pock Community shows an onboarding flow that:

- Prompts for the Accessibility permission needed for Touch Bar control behavior.
- Enables launch at login by default.
- Lets users open Preferences and adjust startup behavior.

If macOS blocks the app because the release is unsigned or not notarized, open **System Settings > Privacy & Security** and allow the app manually. Future notarized releases should reduce this warning.

## Local Install From Source

For a local community build:

```sh
./scripts/install_app.sh
```

The script runs `pod install`, builds the Release configuration, copies `Pock.app` to `/Applications`, and opens it.

## Build Instructions

Requirements:

- macOS with full Xcode installed, not only Command Line Tools.
- CocoaPods installed.
- Network access for CocoaPods dependencies.

Recommended commands:

```sh
pod install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -workspace Pock.xcworkspace
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pock.xcworkspace -scheme "Pock (Pock project)" -configuration Release build CODE_SIGNING_ALLOWED=NO
```

Open `Pock.xcworkspace`, not `Pock.xcodeproj`, when working in Xcode.

## Verified Build

The Release build was verified locally on June 29, 2026 with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pock.xcworkspace -scheme "Pock (Pock project)" -configuration Release build CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED`.

The local installer was also verified:

```sh
./scripts/install_app.sh
```

Result: built Release, installed `/Applications/Pock.app`, and opened the app.

## Compatibility

Compatibility depends on macOS version, hardware, and whether the Mac has a physical Touch Bar.

| macOS | MacBook model | Processor | Touch Bar | Status |
| --- | --- | --- | --- | --- |
| macOS 26.0 / 26.2 SDK local build environment | Local development machine | Apple Silicon / universal build output | Not physically verified by automation | Build succeeds |
| macOS 14 Sonoma | MacBook Pro with Touch Bar | Intel or Apple Silicon | Yes | Needs community reports |
| macOS 13 Ventura | MacBook Pro with Touch Bar | Intel or Apple Silicon | Yes | Needs community reports |
| macOS 12 Monterey | MacBook Pro with Touch Bar | Intel | Yes | Needs community reports |
| macOS 11 Big Sur | MacBook Pro with Touch Bar | Intel | Yes | Needs community reports |

Please use the compatibility issue template to report exact macOS version, Mac model, processor type, Touch Bar availability, installed release, and results.

## Permissions

Pock Community may need Accessibility permission to interact smoothly with macOS controls and Touch Bar behavior. Grant it in:

```text
System Settings > Privacy & Security > Accessibility
```

The app does not include telemetry, analytics, or tracking.

## Updates And Releases

Source changes pushed to `main` do not automatically update user installations. Users receive updates only when maintainers publish a release artifact and update the version catalog used by the app.

Release process documentation lives in [RELEASES.md](RELEASES.md).

## Reporting Issues

Use the GitHub issue templates. Useful reports include:

- macOS version and build number.
- Mac model and year.
- Intel or Apple Silicon.
- Whether a physical Touch Bar is available.
- Pock Community release, commit, or build source.
- Installed widgets.
- Clear reproduction steps.
- Logs or crash reports with private information removed.

## Security

Do not report sensitive security issues in public issues. See [SECURITY.md](SECURITY.md).

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Keep changes small, reviewable, and scoped. Do not add paid services, telemetry, analytics, or tracking.

## Maintainers

Maintainer expectations and release responsibilities are documented in [MAINTAINERS.md](MAINTAINERS.md).

## Dependencies

- [PockKit](https://github.com/pock/pockkit)
- [Magnet](https://github.com/Clipy/Magnet)
- [Zip](https://github.com/marmelroy/Zip)
- [Sauce](https://github.com/Clipy/Sauce)
- [TinyConstraints](https://github.com/roberthein/TinyConstraints)

## Original Attribution

This fork is based on the original Pock project by Pierluigi Galdi and contributors. Original copyright notices and the MIT license are preserved.

Special thanks from the original project are preserved for:

- BrokenSt0rm
- sveinbjornt
- boyvanamstel
- Minebomber

## License

MIT. See [LICENSE.md](LICENSE.md).
