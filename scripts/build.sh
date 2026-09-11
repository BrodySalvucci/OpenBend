#!/bin/zsh
# Builds OpenBend with SwiftPM and assembles build/OpenBend.app.
# Usage: scripts/build.sh            (release)
#        CONFIG=debug scripts/build.sh
#        CODESIGN_IDENTITY="Developer ID Application: ..." scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
# Prefer an explicit identity, then the self-signed "OpenBend Dev" cert (scripts/make-signing-cert.sh),
# then ad-hoc. A stable identity keeps macOS's Screen Recording grant valid across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "OpenBend Dev"; then
    IDENTITY="OpenBend Dev"
  else
    IDENTITY="-"
  fi
fi
APP="build/OpenBend.app"

echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG" --product OpenBend
BIN="$(swift build -c "$CONFIG" --show-bin-path)/OpenBend"
[[ -x "$BIN" ]] || { echo "build failed: $BIN missing"; exit 1; }

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenBend"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f build/AppIcon.icns ]]; then
  echo "▸ rendering app icon"
  swift scripts/make-icon.swift build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Finder can attach directory metadata in synced workspaces; codesign rejects it.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true

echo "▸ codesign ($IDENTITY)"
codesign --force --deep --sign "$IDENTITY" --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign "$IDENTITY" "$APP"

echo "✓ $APP"
