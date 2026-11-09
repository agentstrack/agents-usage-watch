# Releasing

How to cut a GitHub release of Agents Usage Watch, what users see when they open it, and what changes once Apple notarization is possible.

## Current state

- Releases are published at https://github.com/agentstrack/agents-usage-watch/releases. The website and README link to the stable name `releases/latest/download/Agents-Usage-Watch.zip`, so keep that asset name.
- The app is signed with an **Apple Development** certificate and is **not notarized**. There is no Developer ID certificate yet: the Apple Developer Program License Agreement is pending, which blocks Developer ID certificates and notarization.
- Users must approve the first launch manually (see [Gatekeeper](#gatekeeper-what-users-see)).

## Cut a release

Prerequisites: Xcode with command line tools, `xcodegen` (Homebrew), `gh` logged in with write access to `agentstrack/agents-usage-watch`, and `Config/Local.xcconfig` (git-ignored, holds the signing team) present in the checkout.

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`. Commit and push to `master`. Releases are built from committed code only.
2. Build and package. The script refuses uncommitted changes to tracked files, so it works from a clean checkout:
   ```
   scripts/release.sh
   ```
   It runs a clean Release build into `build-release/` (the installed app and `build/` are not touched), copies the app as `Agents Usage Watch.app`, verifies its signature, and writes to `dist/`:
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

## Gatekeeper: what users see

Because the app is not notarized, macOS blocks a double-click on first launch. Users should:

1. Right-click (or Control-click) **Agents Usage Watch.app** and choose **Open**, then **Open** again in the dialog.
2. If only "cannot be opened" appears, open **System Settings › Privacy & Security**, scroll to the message about Agents Usage Watch, and click **Open Anyway**, then confirm.

Requires macOS 14 or later. Assessment with `spctl -a -vv` is expected to say `rejected` with `origin=Apple Development: …` until notarization is in place. Do not tell users to disable Gatekeeper or clear the quarantine attribute with `xattr` in general instructions; the Open flow above is the supported path.

## Switching to Developer ID and notarization (not implemented)

Do this once the Developer Program License Agreement is accepted by the account holder.

1. **Certificate.** Create a *Developer ID Application* certificate (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application) and confirm it is in the login keychain: `security find-identity -v -p codesigning` should list it.
2. **Build settings.** Release signing must be manual Developer ID with the hardened runtime. Options to add to the `xcodebuild` call in `scripts/release.sh`, or to `project.yml` for the Release configuration:
   - `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="Developer ID Application"`, `DEVELOPMENT_TEAM` from `Config/Local.xcconfig`
   - `ENABLE_HARDENED_RUNTIME=YES` (required for notarization; the app is unsandboxed and reads Claude Code's files in the home folder, so check that it still runs and that no new privacy prompts block it)
   - Keep `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` so the release has no `get-task-allow`.
   - Developer ID provisioning profiles may be needed for the app-group entitlement. Check the built bundle with `codesign -d --entitlements :- <app>` and `security cms -D -i <app>/Contents/embedded.provisionprofile` if the build complains.
3. **Notary credentials, once.** Create an app-specific password at appleid.apple.com and store it in the keychain. Never commit it or put it in the script:
   ```
   xcrun notarytool store-credentials AGENTS_USAGE_NOTARY --apple-id <apple-id> --team-id K2D27GW5GM
   ```
4. **Sign, zip, notarize, staple, re-zip.** The stapled app must be zipped again, because stapling changes the bundle:
   ```
   ditto -c -k --keepParent "dist/stage/Agents Usage Watch.app" dist/notary-submit.zip
   xcrun notarytool submit dist/notary-submit.zip --keychain-profile AGENTS_USAGE_NOTARY --wait
   xcrun stapler staple "dist/stage/Agents Usage Watch.app"
   xcrun stapler validate "dist/stage/Agents Usage Watch.app"
   ditto -c -k --keepParent --noextattr --norsrc --noqtn --noacl "dist/stage/Agents Usage Watch.app" dist/Agents-Usage-Watch.zip
   ```
   On a rejected submission, read the log: `xcrun notarytool log <submission-id> --keychain-profile AGENTS_USAGE_NOTARY`.
5. **Verify.** `spctl -a -vv -t exec "Agents Usage Watch.app"` should print `accepted` with `source=Notarized Developer ID`. Then rebuild the checksums from the final zip and publish.
6. **Docs.** Remove the Open Anyway steps from the release notes template in `scripts/release.sh` and from `README.md` and `docs/installation.md`.

## Known limits of the current build

- Apple Development signing ties the signature to the developer's name and team ID, both visible to anyone who inspects the app (`codesign -dv`).
- The build is arm64 only (Apple silicon). Intel Macs cannot run it until a universal build is made (`ARCHS="arm64 x86_64"`, `ONLY_ACTIVE_ARCH=NO`).
- The release is not tested on a Mac other than the developer's. Test a fresh install on a second Mac before announcing it.
