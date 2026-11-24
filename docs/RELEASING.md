# Releasing

How to cut a GitHub release of Agents Usage Watch, and how it is signed and notarized.

## Current state

- Releases are published at https://github.com/agentstrack/agents-usage-watch/releases. The website and README link to the stable name `releases/latest/download/Agents-Usage-Watch.zip`, so keep that asset name.
- Since 0.2.1 the app is signed with **Developer ID** (hardened runtime) and **notarized and stapled**, so it opens with a double-click.

## Cut a release

Prerequisites: Xcode with command line tools, the *Developer ID Application* certificate for the team in `Config/Local.xcconfig` in the login keychain, the App Store Connect notary key at `secrets/AuthKey_4H425Z87ML.p8` (git-ignored; or set `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER`), `xcodegen` (Homebrew), `gh` logged in with write access to `agentstrack/agents-usage-watch`, and `Config/Local.xcconfig` (git-ignored, holds the signing team) present in the checkout.

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`. Commit and push to `master`. Releases are built from committed code only.
2. Build and package. The script refuses uncommitted changes to tracked files, so it works from a clean checkout:
   ```
   scripts/release.sh
   ```
   It runs a clean Release build into `build-release/` (the installed app and `build/` are not touched), copies the app as `Agents Usage Watch.app`, re-signs the widget and the app with Developer ID and the hardened runtime (each keeps its own entitlements, without `get-task-allow`; the team-prefixed App Group needs no provisioning profile), notarizes and staples it, checks it with `spctl`, and writes to `dist/`:
   - `Agents-Usage-Watch.zip` (the stable asset name)
   - `Agents-Usage-Watch-<version>.zip` (versioned copy)
   - `SHA256SUMS.txt`
   - `RELEASE_NOTES.md` (commit subjects since the last tag)
3. Check the package before publishing: `shasum -a 256 -c dist/SHA256SUMS.txt`, and unzip into an empty directory and run `codesign --verify --deep --strict` on the app.
4. Publish. This creates tag `v<version>` at HEAD on GitHub and uploads the three files:
   ```
   scripts/release.sh --publish
   ```
   Publishing refuses if the tag already exists locally or on origin, or if HEAD is not on `origin/master`. To redo a release, delete the GitHub release and its tag first and bump nothing else.
5. Confirm the public link:
   ```
   curl -sIL https://github.com/agentstrack/agents-usage-watch/releases/latest/download/Agents-Usage-Watch.zip | grep '^HTTP' | tail -1   # expect 200
   gh release view v<version> -R agentstrack/agents-usage-watch
   ```
   Download the zip and compare its SHA-256 with `SHA256SUMS.txt`.

The release notes are generated from commit subjects. Edit them on the GitHub release page if needed (`gh release edit v<version> --notes-file <file>`).

## Checking a build

`spctl -a -vv -t exec "Agents Usage Watch.app"` prints `accepted` with `source=Notarized Developer ID`. On a rejected
notarization, read the log: `xcrun notarytool log <submission-id> --key secrets/AuthKey_4H425Z87ML.p8 --key-id 4H425Z87ML --issuer 3ca2f207-d7a0-48bc-bf4f-f28ab1bb553e`.

## Known limits of the current build

- The build is arm64 only (Apple silicon). Intel Macs cannot run it until a universal build is made (`ARCHS="arm64 x86_64"`, `ONLY_ACTIVE_ARCH=NO`).
- The release is not tested on a Mac other than the developer's. Test a fresh install on a second Mac before announcing it.
