# Pock Community 0.10.1-19

Pock Community is an unofficial community-maintained fork of Pock. This release is not an official Pock release and is not endorsed by the original authors.

## Highlights

- Added **AWS Status** to **Manage widgets…**. Enable it, choose a local AWS CLI profile and region, then place it in either Touch Bar menu with **Organize Widgets…**.
- Tap AWS Status for details such as a missing profile, expired AWS session, insufficient read permissions, or an unreachable endpoint.
- The widget can display a local job result or cost snapshot. See the [AWS Status setup guide](https://github.com/kalech7/pock-community/blob/v0.10.1-19/docs/aws-status.md) for the formats and required permissions.

## Installation

1. Download `Pock-Community-0.10.1-19.zip`.
2. Unzip it.
3. Move `Pock.app` to `/Applications`.
4. Open Pock Community.
5. Grant Accessibility permission only if it has not already been granted.

## Compatibility

This release targets macOS 10.15 and later and is intended for MacBook models with a physical Touch Bar. AWS Status and menu switching were tested on a MacBook Pro (13-inch, 2020, two Thunderbolt 3 ports) running macOS 15.8.3 with Better Now Playing Community 1.05.5. The reported case on macOS Tahoe 26.7.1 still needs confirmation on that hardware.

If the issue persists, please report your macOS build, MacBook model, widget versions, and whether the entire Pock menu or only the Now Playing widget disappears. Check whether the native Touch Bar returns after quitting Pock.

## Security And Privacy

This fork does not include telemetry, analytics, or tracking. AI Activity records are stored on your Mac. The weather widget requests forecasts and public holidays from Open-Meteo and Nager.Date. Next Meeting reads your chosen calendars locally through macOS after you grant access. When enabled, AWS Status uses your locally configured AWS CLI for EC2 and RDS read operations. Billing estimates come from locally supplied or cached data.

This binary is locally signed but not notarized. macOS may show a security prompt on first launch. Users may need to allow the app from **System Settings > Privacy & Security**.

## Attribution

Original Pock copyright notices, contributors, and MIT license are preserved. The archive includes `LICENSE.md`. Provider marks identify their respective integrations and belong to their owners.
