# Releases

This document describes how Pock Community releases are prepared. Pock Community is an unofficial community-maintained fork and must not be presented as the official Pock project.

## Release Types

- Source-only release: tag and release notes only.
- Binary release: zipped `Pock.app` attached to a GitHub Release.
- Signed and notarized binary release: preferred for public distribution, but requires an Apple Developer Program account and Developer ID certificate.

## Versioning

Use the app version from the Xcode project. The current project version is:

- Marketing version: `0.10.1`
- Build version: `10`
- Release label: `0.10.1-10`

Use tags such as:

```text
v0.10.1-10
```

## Pre-Release Checklist

1. Confirm the repository is on `main` and up to date.
2. Confirm `git status` is clean.
3. Review merged changes since the previous release.
4. Update `CHANGELOG.md`.
5. Update `BUILD_STATUS.md` if build assumptions changed.
6. Run `pod install`.
7. Run the verified Release build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pock.xcworkspace -scheme "Pock (Pock project)" -configuration Release build CODE_SIGNING_ALLOWED=NO
```

8. Sign the app with the local identity used for previous permission-preserving builds:

```sh
./scripts/sign_app.sh "$HOME/Library/Developer/Xcode/DerivedData/Pock-fgcdlnkhwvjnuwbrhagpqbmhbpcs/Build/Products/Release/Pock.app"
```

9. Run the local installer smoke test:

```sh
./scripts/install_app.sh
```

10. Test on a Touch Bar Mac when available.
11. Review release notes for the visible unofficial-fork disclaimer.

## Build A Zip Artifact

After a successful Release build:

```sh
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/Pock-fgcdlnkhwvjnuwbrhagpqbmhbpcs/Build/Products/Release/Pock.app"
./scripts/sign_app.sh "$APP_PATH"
(cd "$(dirname "$APP_PATH")" && zip -qry -X --symlinks "Pock-Community-0.10.1-10.zip" "Pock.app")
```

If the DerivedData path differs, locate the newest Release app:

```sh
find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Build/Products/Release/Pock.app" -type d -print
```

## Create A GitHub Release

```sh
git tag v0.10.1-10
git push origin v0.10.1-10
gh release create v0.10.1-10 Pock-Community-0.10.1-10.zip \
  --title "Pock Community 0.10.1-10" \
  --notes-file .github/RELEASE_TEMPLATE.md
```

## Update Catalog

The app checks this catalog for update metadata:

```text
https://kalech7.github.io/pock-community-widgets/catalog/latestVersions.json
```

Publishing to `main` does not update users automatically. Maintainers must publish a release artifact and update the catalog with the new version and download URL.

## Signing And Notarization

Unsigned builds may show macOS security warnings and may cause macOS to ask for Accessibility permissions again. Local maintainer builds should be signed with `Pock Local Code Signing` to preserve the same code-signing requirement across versions.

For local permission-preserving builds:

```sh
./scripts/sign_app.sh /Applications/Pock.app
codesign -d -r- /Applications/Pock.app
```

The designated requirement should keep the same bundle identifier and local certificate hash across updates.

Signed and notarized releases are recommended for public users.

Requirements:

- Apple Developer Program membership.
- Developer ID Application certificate.
- Notary credentials configured with `xcrun notarytool`.

Basic flow:

```sh
codesign --force --deep --options runtime --sign "Developer ID Application: NAME (TEAMID)" /Applications/Pock.app
(cd /Applications && zip -qry -X --symlinks Pock-Community-0.10.1-10.zip Pock.app)
xcrun notarytool submit Pock-Community-0.10.1-10.zip --keychain-profile "PockCommunityNotary" --wait
xcrun stapler staple /Applications/Pock.app
xcrun stapler validate /Applications/Pock.app
(cd /Applications && zip -qry -X --symlinks Pock-Community-0.10.1-10-notarized.zip Pock.app)
```

Do not commit certificates, passwords, provisioning profiles, or signing identities.
