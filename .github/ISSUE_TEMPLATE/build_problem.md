---
name: Build problem
about: Report a local setup, dependency, Xcode, CocoaPods, or build failure
title: "[Build]: "
labels: build
assignees: ""
---

## Disclaimer

Pock Community is an unofficial community-maintained fork of Pock, not the official Pock project.

## Summary

Describe the build or setup failure.

## Environment

| Field | Value |
| --- | --- |
| macOS version |  |
| Xcode version |  |
| `xcode-select -p` output |  |
| CocoaPods version |  |
| Ruby version |  |
| Mac model |  |
| Processor | Intel / Apple Silicon |

## Commands Run

```sh
pod install
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pock.xcworkspace -scheme "Pock (Pock project)" -configuration Release build CODE_SIGNING_ALLOWED=NO
```

## Error Output

```text
Paste the relevant error output here.
```

## Dependency State

- Did `pod install` complete successfully? yes / no
- Did `Podfile.lock` or `Pods/` exist before building? yes / no / unknown
- Any local signing changes? yes / no

## Additional Context

Add any other details that may help reproduce the build failure.
