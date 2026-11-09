#!/bin/bash
# Builds the Release app and packages the GitHub Release assets into dist/.
#   scripts/release.sh            clean Release build + dist/ zips and SHA256SUMS.txt
#   scripts/release.sh --publish  also create the GitHub release v<version> (tag at HEAD) with the assets
# Refuses uncommitted changes to tracked files, so the zips match the commit they are tagged at.
# Builds into build-release/ so the installed app (install.sh, build/) is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=agentstrack/agents-usage-watch
APP=AgentsUsageWatch          # build product name
DEST="Agents Usage Watch"     # name inside the zip: what users see in Finder
ASSET=Agents-Usage-Watch      # zip name: the latest/download link depends on it
DERIVED=build-release
DIST=dist

PUBLISH=0
case "${1:-}" in
  "") ;;
  --publish) PUBLISH=1 ;;
  *) echo "usage: $0 [--publish]" >&2; exit 2 ;;
esac

[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || { echo "error: tracked files have uncommitted changes; commit or stash them first" >&2; exit 1; }
[ -f Config/Local.xcconfig ] || { echo "error: Config/Local.xcconfig is missing (signing team)" >&2; exit 1; }

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\([^"]*\)".*/\1/p' project.yml)
[ -n "$VERSION" ] || { echo "error: MARKETING_VERSION not found in project.yml" >&2; exit 1; }
TAG=v$VERSION

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
  && { echo "error: local tag $TAG already exists" >&2; exit 1; }
REMOTE_TAG=$(git ls-remote --tags origin "refs/tags/$TAG") \
  || { echo "error: cannot reach origin to check for tag $TAG" >&2; exit 1; }
[ -z "$REMOTE_TAG" ] || { echo "error: tag $TAG already exists on origin; bump MARKETING_VERSION" >&2; exit 1; }

if [ "$PUBLISH" -eq 1 ]; then
  git fetch --quiet origin
  git merge-base --is-ancestor HEAD origin/main \
    || { echo "error: HEAD is not on origin/main; push it before publishing" >&2; exit 1; }
fi

echo "Building $DEST $VERSION (HEAD $(git rev-parse --short HEAD))"
xcodegen -q
rm -rf "$DERIVED"
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO drops the get-task-allow (debugger attach) entitlement that
# Xcode adds to development-signed builds. The app group and sandbox entitlements are unaffected.
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

PRODUCT="$DERIVED/Build/Products/Release/$APP.app"
[ -d "$PRODUCT" ] || { echo "error: build product not found at $PRODUCT" >&2; exit 1; }

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/agents-usage-watch-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
# No extended attributes or resource forks: they would be zipped as ._ AppleDouble files.
ditto --noextattr --norsrc --noqtn --noacl "$PRODUCT" "$STAGE/$DEST.app"
codesign --verify --deep --strict "$STAGE/$DEST.app"

rm -rf "$DIST" && mkdir -p "$DIST"
# --noextattr etc.: the provenance attribute would otherwise be zipped as ._ AppleDouble entries.
ditto -c -k --keepParent --noextattr --norsrc --noqtn --noacl "$STAGE/$DEST.app" "$DIST/$ASSET.zip"
cp "$DIST/$ASSET.zip" "$DIST/$ASSET-$VERSION.zip"
(cd "$DIST" && shasum -a 256 "$ASSET.zip" "$ASSET-$VERSION.zip" > SHA256SUMS.txt)

# Release notes: commits since the last tag (all commits if there is no tag yet).
PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
RANGE=${PREV:+$PREV..}HEAD
CHANGES=$(git log -n 30 --no-merges --pretty='- %s' "$RANGE")
NOTES="$DIST/RELEASE_NOTES.md"
cat > "$NOTES" <<EOF
## Agents Usage Watch $VERSION

### What's new
$CHANGES

### Install
1. Download \`$ASSET.zip\` and unzip it.
2. Move **Agents Usage Watch.app** to \`/Applications\` or \`~/Applications\`.
3. Open it. This build is signed with a development certificate and is **not notarized by Apple**, so a normal double-click is blocked.
   Right-click the app, choose **Open**, then click **Open** again. If macOS only shows "cannot be opened", go to System Settings › Privacy & Security and click **Open Anyway**.
4. Requires macOS 14 or later.

### Checksum
Compare the download with \`SHA256SUMS.txt\`:
\`\`\`
shasum -a 256 $ASSET.zip
\`\`\`
EOF

echo
echo "Built $DIST/$ASSET.zip"
echo "Built $DIST/$ASSET-$VERSION.zip"
echo "Wrote $DIST/SHA256SUMS.txt and $NOTES"
cat "$DIST/SHA256SUMS.txt"

if [ "$PUBLISH" -eq 1 ]; then
  gh release create "$TAG" -R "$REPO" --target "$(git rev-parse HEAD)" \
    --title "Agents Usage Watch $VERSION" --notes-file "$NOTES" \
    "$DIST/$ASSET.zip" "$DIST/$ASSET-$VERSION.zip" "$DIST/SHA256SUMS.txt"
  echo "Published $TAG: $(gh release view "$TAG" -R "$REPO" --json url -q .url)"
else
  echo "Not published. Re-run with --publish to create release $TAG."
fi
