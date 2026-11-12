# Pock Community 0.10.1-12

Pock Community is an unofficial community-maintained fork of Pock. This release is not an official Pock release and is not endorsed by the original authors.

## Highlights

- Adds a compact weather widget with current conditions, a day and night palette, and applicable public holidays.
- Shows running Codex, Claude Code, and Gemini CLI sessions with provider icons in AI Activity. Review the Pock Community hooks in Codex to enable its integration. See the [setup guide](https://github.com/kalech7/pock-community/blob/main/docs/agent-activity.md) for other providers.
- Uses the same dot-and-arrow control in Pock, AI Activity, and the native Touch Bar.
- Restores the installed widgets list in Pock's widget manager.

## Installation

1. Download `Pock-Community-0.10.1-12.zip`.
2. Unzip it.
3. Move `Pock.app` to `/Applications`.
4. Open Pock Community.
5. Grant Accessibility permission only if it has not already been granted.

## Compatibility

This release targets macOS 10.15 and later and is intended for MacBook models with a physical Touch Bar. Please report exact macOS version, Mac model, processor type, Touch Bar availability, and results through the compatibility report template.

## Security And Privacy

This fork does not include telemetry, analytics, or tracking. AI Activity records are stored on your Mac. The weather widget requests forecasts and public holidays from Open-Meteo and Nager.Date.

This binary is locally signed but not notarized. macOS may show a security prompt on first launch. Users may need to allow the app from **System Settings > Privacy & Security**.

## Attribution

Original Pock copyright notices, contributors, and MIT license are preserved. The archive includes `LICENSE.md`. Provider marks identify their respective integrations and belong to their owners.
