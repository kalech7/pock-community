# Contributing to Pock Community Fork

This repository is an unofficial community-maintained fork of Pock. It is not the official Pock project. The original project, authors, copyright notices, and MIT license must remain credited and preserved.

## Local Setup

Requirements:

- A Mac with full Xcode installed, not only Command Line Tools.
- CocoaPods installed (`pod --version`).
- Git access to the dependency repositories declared in `Podfile`, including `git@github.com:pock/pockkit.git`.
- Optional: SwiftLint (`swiftlint`) for the existing Xcode build phase.

Setup steps:

```sh
git clone git@github.com:kalech7/pock-community.git
cd pock-community
pod install
open Pock.xcworkspace
```

If `xcodebuild` reports that the active developer directory is Command Line Tools, select full Xcode before building:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Opening in Xcode

Open `Pock.xcworkspace`, not `Pock.xcodeproj`, after running `pod install`. The workspace is generated/updated by CocoaPods and includes both the app project and the Pods project.

Shared schemes currently include:

- `Pock`
- `QLPockWidget`
- `Relaunch`

## Building and Running

Recommended local build command:

```sh
xcodebuild -workspace Pock.xcworkspace -scheme Pock -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

For day-to-day development, open `Pock.xcworkspace` in Xcode, select the `Pock` scheme, and run/build from Xcode.

Do not commit local signing changes, developer team changes, provisioning profile changes, or bundle identifier changes unless a maintainer explicitly asks for them.

## Reporting Bugs

Use the appropriate GitHub issue template. Include:

- macOS version and hardware model.
- Whether the Mac has a physical Touch Bar.
- Pock version, commit, or build source.
- Clear reproduction steps.
- Expected behavior and actual behavior.
- Screenshots or Touch Bar screenshots when useful.
- Crash reports from Console.app when applicable.

For build failures, use the build problem template and include the full command output.

## Submitting Pull Requests

Pull requests should be small, focused, and reviewable.

1. Create a branch from `main`.
2. Keep the change scoped to one bug, feature, or documentation update.
3. Avoid unrelated formatting churn.
4. Run `pod install` if dependencies changed.
5. Run the relevant build/test command before opening the PR.
6. If a command cannot be run, explain why in the PR.
7. Update documentation or `BUILD_STATUS.md` when compatibility or setup assumptions change.

## Coding Style

- Follow the existing Swift and Xcode project style.
- Prefer straightforward fixes over large rewrites.
- Avoid architecture changes unless they are necessary and documented.
- Preserve original copyright notices and license headers.
- Do not add new paid services, telemetry, analytics, or tracking.
- Document any macOS compatibility impact.
- Keep UI changes consistent with the existing app behavior unless the PR explicitly proposes a UI change.

## License

By contributing, you agree that your contribution is licensed under the repository's MIT license. See `LICENSE.md`.
