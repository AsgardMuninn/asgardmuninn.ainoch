#!/bin/bash
# build_app_bundle.sh <out-dir> — empaqueta Ainoch.app (APPBUNDLE_SPEC v1).
# Compila desde Sources/, dibuja el ícono desde código, firma ad-hoc y verifica.
# Uso: Scripts/build_app_bundle.sh /tmp/ainoch-bundle
set -euo pipefail

OUT="${1:-}"
[ -n "$OUT" ] || { echo "uso: build_app_bundle.sh <out-dir>" >&2; exit 64; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$OUT/Ainoch.app"
CONTENTS="$APP/Contents"
SOURCES=(main views IslandGeometry ContentState SoundSpec StackLogic KeyboardSpec TextFit)

echo "== build: binario =="
mkdir -p "$OUT"
FILES=()
for s in "${SOURCES[@]}"; do FILES+=("$ROOT/Sources/$s.swift"); done
swiftc -O "${FILES[@]}" -o "$OUT/ainoch"
echo "   $(stat -f%z "$OUT/ainoch") bytes"

echo "== build: ícono (PNG en código -> iconset -> icns) =="
swiftc -O "$ROOT/Tools/make_icon.swift" -o "$OUT/make_icon"
"$OUT/make_icon" "$OUT/icon-1024.png" 1024 >/dev/null
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
            256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" "$OUT/icon-1024.png" --out "$ICONSET/icon_${name}.png" >/dev/null
done

echo "== build: bundle =="
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
cp "$OUT/ainoch" "$CONTENTS/MacOS/ainoch"
chmod +x "$CONTENTS/MacOS/ainoch"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ainoch.notch</string>
    <key>CFBundleExecutable</key>
    <string>ainoch</string>
    <key>CFBundleName</key>
    <string>Ainoch</string>
    <key>CFBundleDisplayName</key>
    <string>Ainoch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist" >/dev/null

codesign --force --deep --sign - "$APP" 2>/dev/null
echo "== verify =="
"$ROOT/Tools/verify_app_bundle.sh" "$APP"
