# Maintainers

This repository is an unofficial community-maintained fork of Pock. It exists to keep Pock usable for Touch Bar Mac users on newer macOS versions while preserving the original project's license, attribution, and history.

This fork must not be presented as the official Pock project.

## Maintainer Responsibilities

Maintainers should:

- Preserve the original MIT license and copyright notices.
- Keep original authors and upstream contributors credited.
- Prefer small, focused, reviewable changes.
- Avoid broad rewrites unless they are necessary for compatibility or maintainability.
- Avoid adding new paid services, telemetry, analytics, or tracking.
- Require compatibility-impacting changes to be documented.
- Avoid changes to bundle identifiers, signing settings, app identity, or release assets unless explicitly planned and reviewed.
- Keep issue templates, contribution docs, build status, and release notes current.

## Issue Triage

Use these guidelines when triaging issues:

- Confirm whether the report is about this community fork, the original upstream project, or a third-party dependency.
- Ask for macOS version, hardware model, Touch Bar availability, Pock version/commit, and reproduction steps when missing.
- Label build failures separately from runtime bugs.
- Label compatibility reports by macOS version when useful.
- Close duplicates with a link to the canonical issue.
- Do not close valid compatibility reports only because the original upstream project is inactive.
- For security-sensitive reports, avoid requesting secrets, certificates, provisioning profiles, or private crash data in public issues.

## Pull Request Review

Before merging, maintainers should verify:

- The change is scoped and understandable.
- Original attribution and MIT licensing are preserved.
- The PR does not claim official project status.
- Build/test commands were run, or the reason they could not be run is documented.
- Compatibility implications are documented.
- No new telemetry, analytics, paid service, or tracking dependency was introduced.

## Release Process Outline

1. Confirm the target branch is up to date and CI/manual build status is understood.
2. Review merged changes since the previous release.
3. Update `CHANGELOG.md` and `BUILD_STATUS.md` as needed.
4. Build from a clean checkout after `pod install`.
5. Verify behavior on a Touch Bar Mac whenever possible.
6. Create an unofficial GitHub release from this fork with clear release notes.
7. State clearly that the release is community-maintained and unofficial.
8. Preserve upstream credits and license references in release notes.

If distributing binaries, maintainers must not use the original authors' signing identity. Any signing, notarization, bundle identifier, or app identity plan should be discussed before changes are made.

## Upstream Preservation

When possible, preserve useful upstream contributions, issue references, and attribution. If upstream becomes active again, prefer contributing general fixes upstream as well, while keeping this fork's community status clear.
