#!/bin/bash
# Локальная сборка DMG для ScreenShoter
# Использование: ./scripts/build-dmg.sh [версия]
#   ./scripts/build-dmg.sh         — версия из Info.plist
#   ./scripts/build-dmg.sh 0.0.2   — указать версию
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw ScreenShoter/Info.plist)}"
BUILD="${2:-$(plutil -extract CFBundleVersion raw ScreenShoter/Info.plist)}"
echo "Сборка ScreenShoter $VERSION ($BUILD)..."

# Archive
xcodebuild -scheme ScreenShoter -configuration Release \
  -archivePath build/ScreenShoter.xcarchive \
  archive

# Export
xcodebuild -exportArchive \
  -archivePath build/ScreenShoter.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist .github/ExportOptions.plist

# DMG
DMG_NAME="ScreenShoter-$VERSION.dmg"
rm -rf dmg_root
mkdir -p dmg_root
cp -R build/export/ScreenShoter.app dmg_root/
ln -s /Applications dmg_root/Applications
hdiutil create -volname "ScreenShoter $VERSION" -srcfolder dmg_root -ov -format UDZO "$DMG_NAME"
rm -rf dmg_root

# ZIP для Sparkle
ZIP_NAME="ScreenShoter-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent build/export/ScreenShoter.app "$ZIP_NAME"

echo ""
echo "Готово:"
echo "  DMG: $DMG_NAME"
echo "  ZIP: $ZIP_NAME"
echo ""
echo "Дальше:"
echo "  1. Нотаризовать: xcrun notarytool submit $DMG_NAME --apple-id YOUR_ID --password PASS --team-id TEAM --wait"
echo "  2. Подшить: xcrun stapler staple $DMG_NAME"
echo "  3. Создать Release на GitHub и загрузить $DMG_NAME и $ZIP_NAME"
