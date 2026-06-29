# Contributing To Pock Community

Pock Community is an unofficial community-maintained fork of Pock. It is not the official Pock project. Original authors, copyright notices, and the MIT license must remain credited and preserved.

## Ground Rules

- Keep changes small, focused, and reviewable.
- Avoid unrelated formatting or generated-file churn.
- Do not add paid services, telemetry, analytics, or tracking.
- Do not change app identity, bundle identifiers, signing settings, provisioning profiles, entitlements, or release assets unless a maintainer explicitly approves the change.
- Document compatibility impacts.
- Prefer fixes that preserve existing behavior for Touch Bar users.

## Local Setup

Requirements:

- macOS with full Xcode installed.
- CocoaPods installed.
- Network access for CocoaPods dependencies.
- Optional: SwiftLint for the existing Xcode build phase.

Setup:

```sh
git clone git@github.com:kalech7/pock-community.git
cd pock-community
pod install
open Pock.xcworkspace
```

Open `Pock.xcworkspace`, not `Pock.xcodeproj`.

## Verified Build Commands

```sh
pod install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -workspace Pock.xcworkspace
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pock.xcworkspace -scheme "Pock (Pock project)" -configuration Release build CODE_SIGNING_ALLOWED=NO
```

For a local install smoke test:

```sh
./scripts/install_app.sh
```

If `xcodebuild` reports that the active developer directory is Command Line Tools, set full Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Reporting Bugs

Use the GitHub issue templates. Include:

- macOS version and build number.
- Mac model and year.
- Intel or Apple Silicon.
- Whether the Mac has a physical Touch Bar.
- Pock Community version, commit, or release.
- Installed widgets.
- Clear reproduction steps.
- Expected and actual behavior.
- Logs or crash reports with private information removed.

For build failures, use the build problem template and include full command output.

## Pull Requests

1. Create a branch from `main`.
2. Keep the PR scoped to one bug, feature, compatibility fix, or documentation update.
3. Run the relevant build command before opening the PR.
4. Update docs when setup, release, compatibility, or permission behavior changes.
5. Explain any command that could not be run.

## Release Changes

Release-impacting changes include:

- Version changes.
- Signing, notarization, or entitlement changes.
- Bundle identifier or app identity changes.
- Release scripts, catalog updates, or installer changes.
- Changes that affect first-run permissions or launch-at-login behavior.

Mark these clearly in the PR.

## Security

Do not report sensitive issues in public issues. See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contribution is licensed under the repository's MIT license. See [LICENSE.md](LICENSE.md).
