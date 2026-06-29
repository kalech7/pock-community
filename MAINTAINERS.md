# Maintainers

Pock Community is an unofficial community-maintained fork of Pock. It exists to keep Pock usable for Touch Bar Mac users while preserving the original project's license, attribution, and history.

This fork must not be presented as the official Pock project.

## Responsibilities

Maintainers should:

- Preserve the original MIT license and copyright notices.
- Keep original authors and upstream contributors credited.
- Keep the name **Pock Community** consistent in documentation and releases.
- Prefer small, focused, reviewable changes.
- Avoid broad rewrites unless required for compatibility or maintainability.
- Avoid paid services, telemetry, analytics, or tracking.
- Require compatibility-impacting changes to be documented.
- Avoid app identity, bundle identifier, signing, entitlement, or release asset changes unless explicitly planned and reviewed.
- Keep issue templates, contribution docs, build status, security policy, changelog, and release notes current.

## Issue Triage

Ask for missing environment details:

- macOS version and build number.
- MacBook model and year.
- Intel or Apple Silicon.
- Physical Touch Bar availability.
- Pock Community release, commit, or build source.
- Installed widgets.
- Reproduction steps and logs.

Use compatibility reports to update the README compatibility table when enough evidence is available.

## Pull Request Review

Before merging, verify:

- The change is scoped and understandable.
- Original attribution and MIT licensing are preserved.
- The PR does not claim official project status.
- Build/test commands were run, or the reason they could not be run is documented.
- Compatibility implications are documented.
- No telemetry, analytics, paid service, or tracking dependency was introduced.
- Release-impacting changes are called out clearly.

## Release Process

Follow [RELEASES.md](RELEASES.md). A public binary release should include:

- A Git tag matching the documented version.
- Clear release notes with the unofficial-fork disclaimer.
- A zipped `Pock.app` artifact.
- Updated `CHANGELOG.md`.
- Updated catalog metadata when maintainers want users to see the update from inside the app.

Signed and notarized binaries are recommended for public users, but maintainers must not use the original authors' signing identity.

Never commit certificates, passwords, Apple Developer credentials, provisioning profiles, or private release keys.

## Security

Follow [SECURITY.md](SECURITY.md). Do not ask users to post secrets, certificates, provisioning profiles, private crash dumps, tokens, or personal data in public issues.

## Upstream Preservation

When possible, preserve useful upstream contributions, issue references, and attribution. If upstream becomes active again, prefer contributing general fixes upstream as well while keeping this fork's community status clear.
