#!/bin/bash
# Сбросить флаг первого запуска — чтобы снова увидеть онбординг (SetupView).
# Bundle ID: com.scrinsjater.app (из ScreenShoter.xcodeproj)
set -e
BUNDLE_ID="com.scrinsjater.app"
defaults delete "$BUNDLE_ID" hasCheckedSetup 2>/dev/null || true
echo "Готово. Запустите ScreenShoter — откроется окно «Установка»."
