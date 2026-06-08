# Build Status

Last investigated: 2026-06-08

## Summary

The project build could not be verified in this local environment because `xcodebuild` is using Command Line Tools instead of a full Xcode installation. CocoaPods dependency installation succeeded.

## Detected Project Setup

- Language: Swift, with a small amount of Objective-C bridging/private framework code.
- Platform: macOS app targeting Touch Bar Macs.
- Build system: Xcode project/workspace.
- Dependency manager: CocoaPods.
- Swift Package Manager: no `Package.swift` detected.
- Carthage: no `Cartfile` detected.
- Main project files: `Pock.xcodeproj`, `Pock.xcworkspace`, `Podfile`.
- Shared schemes: `Pock`, `QLPockWidget`, `Relaunch`.
- Deployment target detected in project and Podfile: macOS 10.15.

## Dependencies

Declared in `Podfile`:

- `PockKit` from `git@github.com:pock/pockkit.git`
- `AppCenter/Analytics`
- `AppCenter/Crashes`
- `Magnet`
- `Zip`

CocoaPods also installed transitive dependencies including `Sauce` and `TinyConstraints` during this investigation.

## Commands Attempted

```sh
ls -la
find . -maxdepth 3 -type f
xcodebuild -list
pod install
xcodebuild -list -workspace Pock.xcworkspace
xcodebuild -workspace Pock.xcworkspace -scheme Pock -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

`swift build` was not run because there is no `Package.swift`.

## Results

`pod install` succeeded with CocoaPods 1.16.2 and installed:

- AppCenter 5.12.0
- Magnet 3.4.0
- PockKit 0.3.1
- Sauce 2.4.1
- TinyConstraints 4.0.2
- Zip 2.1.2

CocoaPods reported warnings that the `Pock` Debug and Release targets override `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES` from the Pods xcconfig files.

Both `xcodebuild -list` and the explicit build command failed with:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

## Current Build Assumptions

A fresh build likely requires:

- Full Xcode installed and selected with `xcode-select`.
- CocoaPods installed.
- Network/Git access to `git@github.com:pock/pockkit.git`.
- Running `pod install` before opening/building the workspace.
- Building the `Pock` scheme from `Pock.xcworkspace`.
- Local signing adjustments in Xcode if running the app on a developer machine, without committing signing or bundle identifier changes.

## Likely Next Steps

1. Select full Xcode: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
2. Run `pod install` from a clean checkout.
3. Run `xcodebuild -list -workspace Pock.xcworkspace`.
4. Run `xcodebuild -workspace Pock.xcworkspace -scheme Pock -configuration Debug build CODE_SIGNING_ALLOWED=NO`.
5. If compiler or signing errors appear, document the exact errors before attempting targeted fixes.
