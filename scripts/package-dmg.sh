#!/usr/bin/env bash
# Package a built KeyCastr.app into a distributable DMG.
#
# Usage:
#   scripts/package-dmg.sh [version]
#
# If [version] is omitted, MARKETING_VERSION from keycastr/project.yml is used.
# Produces dist/KeyCastr-<version>.dmg.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/keycastr"
APP_PATH="$PROJECT_DIR/build/DD/Build/Products/Release/KeyCastr.app"
DIST_DIR="$REPO_ROOT/dist"

if [[ ! -d "$APP_PATH" ]]; then
  echo "KeyCastr.app not found at $APP_PATH" >&2
  echo "Run a Release build first, e.g.:" >&2
  echo "  cd keycastr && xcodebuild -project KeyCastr.xcodeproj -scheme KeyCastr -configuration Release -derivedDataPath build/DD build" >&2
  exit 1
fi

VERSION="${1:-$(awk '/^    MARKETING_VERSION:/ {gsub(/"/,"",$2); print $2; exit}' "$PROJECT_DIR/project.yml")}"
if [[ -z "$VERSION" ]]; then
  echo "Could not determine version" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG_PATH="$DIST_DIR/KeyCastr-$VERSION.dmg"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "KeyCastr $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
