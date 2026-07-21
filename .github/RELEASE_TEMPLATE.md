# Pock Community 0.10.1-11

Pock Community is an unofficial community-maintained fork of Pock. This release is not an official Pock release and is not endorsed by the original authors.

## Highlights

- Keeps the same local signing requirement when installing over an existing Pock Community build, so already-granted Accessibility permission is preserved whenever macOS permits it.
- Refuses an unsafe in-place replacement when its signing requirement differs from the installed app.
- Improves switching between Pock and the native Touch Bar after lock/unlock, reload, and customization flows.
- Avoids blank Touch Bar and nil widget-view failures during presentation changes.

## Installation

1. Download `Pock-Community-0.10.1-11.zip`.
2. Unzip it.
3. Move `Pock.app` to `/Applications`.
4. Open Pock Community.
5. Grant Accessibility permission only if it has not already been granted.

## Compatibility

This release targets macOS 10.15 and later and is intended for MacBook models with a physical Touch Bar. Please report exact macOS version, Mac model, processor type, Touch Bar availability, and results through the compatibility report template.

## Security And Privacy

This fork does not include telemetry, analytics, or tracking.

This binary is locally signed but not notarized. macOS may show a security prompt on first launch. Users may need to allow the app from **System Settings > Privacy & Security**.

## Attribution

Original Pock copyright notices, contributors, and MIT license are preserved.
