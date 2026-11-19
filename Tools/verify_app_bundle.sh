#!/bin/bash
# verify_app_bundle.sh <ruta/Ainoch.app> — verificador del nodo APPBUNDLE_SPEC v1.
# Exit 0 = bundle válido. Exit 1 = inválido (imprime el primer fallo).
set -uo pipefail

BUNDLE="${1:-}"
fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "  ok  $*"; }

[ -n "$BUNDLE" ] || fail "uso: verify_app_bundle.sh <ruta/Ainoch.app>"
BUNDLE="${BUNDLE%/}"
[ -d "$BUNDLE" ] || fail "no existe el bundle: $BUNDLE"
case "$BUNDLE" in *.app) ;; *) fail "no termina en .app: $BUNDLE" ;; esac

CONTENTS="$BUNDLE/Contents"
PLIST="$CONTENTS/Info.plist"
EXEC="$CONTENTS/MacOS/ainoch"
ICNS="$CONTENTS/Resources/AppIcon.icns"

[ -d "$CONTENTS" ] || fail "falta Contents/"
[ -f "$PLIST" ] || fail "falta Info.plist"
[ -f "$EXEC" ] || fail "falta Contents/MacOS/ainoch"
[ -x "$EXEC" ] || fail "Contents/MacOS/ainoch sin bit de ejecución"
[ -f "$ICNS" ] || fail "falta Contents/Resources/AppIcon.icns"
ok "estructura Contents/{MacOS,Resources,Info.plist}"

plutil -lint "$PLIST" >/dev/null || fail "plutil -lint falló"
ok "plutil -lint"

check_key() { # clave valor_esperado
    local got
    got=$(plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null)
    [ "$got" = "$2" ] || fail "Info.plist $1 = '$got' (esperado '$2')"
}
check_key CFBundleIdentifier com.ainoch.notch
check_key CFBundleExecutable ainoch
check_key CFBundleName Ainoch
check_key CFBundlePackageType APPL
check_key CFBundleIconFile AppIcon
check_key CFBundleShortVersionString 1.0.0
check_key CFBundleVersion 1
check_key LSUIElement true
check_key NSHighResolutionCapable true
check_key LSMinimumSystemVersion 13.0
ok "10 claves de Info.plist"

DIMS=$(sips -g pixelWidth -g pixelHeight "$ICNS" 2>/dev/null | awk '/pixel/{print $2}' | tr '\n' 'x')
case "$DIMS" in 1024x1024x) ;; *) fail ".icns ilegible (sips: ${DIMS:-sin salida})" ;; esac
ok ".icns legible (pixelWidth 1024)"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
iconutil -c iconset "$ICNS" -o "$TMPD/rt.iconset" >/dev/null 2>&1 || fail "iconutil round-trip falló"
N=$(ls "$TMPD/rt.iconset" | wc -l | tr -d ' ')
[ "$N" -eq 10 ] || fail "round-trip devolvió $N representaciones (esperado 10)"
ok "iconutil round-trip: 10 representaciones"

codesign --verify --strict "$BUNDLE" >/dev/null 2>&1 || fail "codesign --verify --strict falló"
SIG=$(codesign -dv "$BUNDLE" 2>&1 | awk -F= '/^Signature/{print $2}')
ok "codesign verificado (Signature=${SIG:-adhoc})"

echo "PASS: $BUNDLE"
