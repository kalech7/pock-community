# Changelog

All notable changes to Pock Community are documented here.

This repository is an unofficial community-maintained fork of Pock. It preserves the original MIT license and attribution.

## Unreleased

- Documentation refresh for public community presentation.
- Added release, security, build, and issue reporting guidance.

## 0.10.1-16 Community

- Added a compact audio output selector to the AI Activity menu on the Touch Bar.
- Highlighted the active output and placed the close button on the right. Selecting an output returns to AI Activity after macOS confirms the change.
- Removed the session ID suffix from Codex cards while preserving chat navigation.

## 0.10.1-15 Community

- Added an optional Next Meeting reminder with a compact join action five minutes before an event. Configure it in Widgets Manager.
- Weather schedules updates when data is due, pauses its display updates while hidden, and draws fewer frames while scrolling long details.
- Meeting reminders skip unnecessary work when disabled and query only the calendar window needed for the next reminder.

## 0.10.1-14 Community

- Fixed an unexpected quit during Touch Bar dimming in Release builds.
- AI Activity watches for changes and checks less often when its list is empty.
- Weather redraws only the changing detail while scrolling text.

## 0.10.1-13 Community

- Shows the built-in Weather and AI Activity entries alongside installed widgets in Widgets Manager.
- Opens Weather settings, Pock customization, and the Touch Bar's AI Activity view directly from the manager.

## 0.10.1-12 Community

- Added a compact weather widget with current conditions, day and night colors, and applicable public holidays.
- Added AI Activity for running sessions, with provider icons and a shared control for switching between Pock, AI Activity, and the native Touch Bar.
- Made installed widgets available in Pock's widget manager and customization menu.

## 0.10.1-11 Community

- Preserve the local code-signing requirement during installation, preventing unnecessary Accessibility permission prompts after an update.
- Refuse unsafe replacements when the existing installation has a different signing requirement.
- Keep Pock and the native Touch Bar switch responsive through lock/unlock, reload, and customization flows.
- Avoid blank Touch Bar and nil widget-view failures during presentation changes.

## 0.10.1-10 Community

- Avoided prompting for Accessibility again when macOS already trusts Pock Community.
- Kept the Accessibility prompt available from onboarding only when permission is still missing.

## 0.10.1-9 Community

- Fixed the native Touch Bar toggle so switching away from Pock reloads Control Strip when macOS does not restore it automatically.
- Routed direct Touch Bar handle taps through the button click path to keep native/Pock switching reliable.

## 0.10.1-8 Community

- Hid the Touch Bar system modal close button when Pock is presented.
- Restored Pock's Touch Bar presentation after switching, launching, or closing apps.

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
