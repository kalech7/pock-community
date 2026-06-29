# Changelog

All notable changes to Pock Community are documented here.

This repository is an unofficial community-maintained fork of Pock. It preserves the original MIT license and attribution.

## Unreleased

- Documentation refresh for public community presentation.
- Added release, security, build, and issue reporting guidance.

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
