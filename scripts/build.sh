#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
APP="$OUTPUT_DIR/Insomnia.app"
mkdir -p "$APP/Contents/MacOS"
"${COMPILER[@]}" -target arm64-apple-macosx13.0 "$PROJECT_ROOT/Source/Shared.swift" "$PROJECT_ROOT/Source/ReadyAcknowledgement.swift" "$PROJECT_ROOT/Source/Guardian.swift" -framework IOKit -o "$APP/Contents/MacOS/InsomniaGuardian"
"${COMPILER[@]}" -target arm64-apple-macosx13.0 "$PROJECT_ROOT/Source/Shared.swift" "$PROJECT_ROOT/Source/NetworkPolicy.swift" "$PROJECT_ROOT/Source/Hotspot.swift" "$PROJECT_ROOT/Source/App.swift" -framework AppKit -framework IOKit -framework ServiceManagement -framework CoreWLAN -framework CoreLocation -framework Network -framework Security -o "$APP/Contents/MacOS/Insomnia"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.insomnia</string>
<key>CFBundleName</key><string>Insomnia</string>
<key>CFBundleDisplayName</key><string>Insomnia</string>
<key>CFBundleExecutable</key><string>Insomnia</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSLocationUsageDescription</key><string>Для чтения имени Wi‑Fi и подключения к выбранной раздаче iPhone. Приложение не запрашивает координаты.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Для чтения имени Wi‑Fi и подключения к выбранной раздаче iPhone. Приложение не запрашивает координаты.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key><string>Для чтения имени Wi‑Fi в активном режиме раздачи. Приложение не запрашивает координаты.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/MacOS/InsomniaGuardian"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built Apple Silicon preview: $APP"
