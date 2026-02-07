#!/bin/bash
# Локальная сборка DMG для ScreenShoter
# Использование: ./scripts/build-dmg.sh [версия]
#   ./scripts/build-dmg.sh         — версия из Info.plist
#   ./scripts/build-dmg.sh 0.0.2   — указать версию
#
# Работает без Apple Developer — DMG для размещения на своём сайте.
# При первом запуске: правый клик по приложению → Открыть (Gatekeeper).
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw ScreenShoter/Info.plist)}"
echo "Сборка ScreenShoter $VERSION..."

xcodebuild -project ScreenShoter.xcodeproj -scheme ScreenShoter -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  build

mkdir -p build/export
APP_PATH="build/DerivedData/Build/Products/Release/ScreenShoter.app"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH=$(find build/DerivedData -name "ScreenShoter.app" -type d | head -1)
fi
cp -R "$APP_PATH" build/export/

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
