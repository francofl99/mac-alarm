#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/MacAlarm.app"

swift build -c release --package-path "$ROOT" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/MacAlarm" "$APP/Contents/MacOS/MacAlarm"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacAlarm</string>
    <key>CFBundleDisplayName</key><string>MacAlarm</string>
    <key>CFBundleIdentifier</key><string>com.franco.macalarm</string>
    <key>CFBundleExecutable</key><string>MacAlarm</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

IDENTITY="${MACALARM_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier com.franco.macalarm "$APP" >/dev/null 2>&1

# Con firma ad-hoc el cdhash cambia en cada build y TCC deja de reconocer la app: la
# autorización vieja queda encendida pero muerta. Resetearla fuerza un prompt limpio.
if [ "$IDENTITY" = "-" ]; then
    HASH_FILE="$ROOT/.build/last_cdhash"
    NEW_HASH="$(codesign -dvvv "$APP" 2>&1 | awk -F= '/^CDHash/{print $2}')"
    if [ "$NEW_HASH" != "$(cat "$HASH_FILE" 2>/dev/null)" ]; then
        pkill -x MacAlarm 2>/dev/null || true
        tccutil reset Accessibility com.franco.macalarm >/dev/null 2>&1 || true
        echo "⚠ Firma nueva: hay que volver a dar Accesibilidad (la app lo pide al activarse)."
    fi
    echo "$NEW_HASH" > "$HASH_FILE"
fi

echo "✔ $APP"
