# Changelog

All notable changes to Pock Community are documented here.

This repository is an unofficial community-maintained fork of Pock. It preserves the original MIT license and attribution.

## Unreleased

- Documentation refresh for public community presentation.
- Added release, security, build, and issue reporting guidance.

## 0.10.1-8 Community

- Hid the Touch Bar system modal close button when Pock is presented.
- Restored Pock's Touch Bar presentation after switching to another app.

## 0.10.0-7 Community

- Added local code signing for installed release builds so macOS can preserve existing permissions across updates.
- Updated the local installer to sign `/Applications/Pock.app` with `Pock Local Code Signing` by default.
- Removed accidental nested `Pock.app` bundles during signing to keep a single stable app identity on disk.

## 0.10.0-6 Community

- Reduced idle widget resource usage by stopping scrolling-text timers when views leave the hierarchy.
- Fixed scrolling text loop accounting so finite widget animations stop as intended.
- Reduced queued drag-location updates during high-frequency Touch Bar drag events.
- Avoided blocking the main thread during widget update checks and Touch Bar reloads.
- Reused the menu bar update badge instead of stacking duplicate badge views.

## 0.10.0-5 Community

- Removed telemetry, analytics, and crash-reporting dependencies from the app and CocoaPods setup.
- Fixed Touch Bar customization flow so Pock widget identifiers are available in the customization palette.
- Saved custom Touch Bar item ordering through user preferences.
- Added a customization host Touch Bar to improve `Customize Pock...` behavior.
- Improved empty Touch Bar handling to avoid nil view crashes.
- Repaired installed widget framework symlinks, including Better Now Playing dependencies.
- Added onboarding setup for Accessibility permission and launch at login.
- Reduced the menu bar icon size.
- Added `scripts/install_app.sh` for local Release builds and installation.
- Added `.idea/` to `.gitignore`.
- Updated community documentation and removed stale telemetry references.

## Attribution

Original Pock project, authors, contributors, copyright notices, and MIT license remain credited and preserved.
