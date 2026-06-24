# Instructions for AI Coding Agents

This repository is an unofficial community-maintained fork of Pock. Never claim or imply that this fork is the official Pock project.

## Required Constraints

- Preserve the MIT license and original attribution.
- Do not remove original copyright notices.
- Avoid large rewrites.
- Prefer minimal, reviewable patches.
- Do not introduce paid services, telemetry, analytics, or tracking.
- Do not change app identity, bundle identifiers, signing settings, provisioning profiles, entitlements, or release assets unless explicitly requested by a maintainer.
- Do not break compatibility without documenting it.

## Working Practices

- Inspect `git status` before editing.
- Keep changes scoped to the user's request.
- Do not revert user changes or unrelated work.
- Prefer documentation updates over code changes when the task is maintenance setup.
- Avoid generated file churn from Xcode or CocoaPods unless the generated file is intentionally tracked.
- Run available build/test commands before finishing.
- Document any command that cannot be run and include the exact error when possible.

## Build/Discovery Commands

Use safe commands first:

```sh
ls
find . -maxdepth 3 -type f
pod install
xcodebuild -list -workspace Pock.xcworkspace
xcodebuild -workspace Pock.xcworkspace -scheme Pock -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Only run `pod install` when `Podfile` exists. Only run `swift build` when `Package.swift` exists. Do not run destructive commands unless the user explicitly asks for them.

## Project Notes

- This is a macOS Swift/Xcode project using CocoaPods.
- Open `Pock.xcworkspace` after running `pod install`.
- Current shared schemes include `Pock`, `QLPockWidget`, and `Relaunch`.
- The app targets Touch Bar Macs; compatibility reports should include macOS version and hardware model.
