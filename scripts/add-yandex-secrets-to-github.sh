#!/bin/bash
# Добавляет YANDEX_CLIENT_ID и YANDEX_CLIENT_SECRET в GitHub Secrets из локального Secrets.xcconfig
# Требует: gh CLI, Secrets.xcconfig (cp ScreenShoter/Secrets.xcconfig.example ScreenShoter/Secrets.xcconfig)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_XCCONFIG="$SCRIPT_DIR/../ScreenShoter/Secrets.xcconfig"
CLIENT_ID=""
CLIENT_SECRET=""

if [ ! -f "$SECRETS_XCCONFIG" ]; then
  echo "Файл $SECRETS_XCCONFIG не найден."
  echo "Скопируйте шаблон: cp ScreenShoter/Secrets.xcconfig.example ScreenShoter/Secrets.xcconfig"
  echo "Заполните YANDEX_CLIENT_ID и YANDEX_CLIENT_SECRET из https://oauth.yandex.ru"
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%//*}"
  line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$line" ] && continue
  if [[ "$line" == *=* ]]; then
    key="${line%%=*}"
    key=$(echo "$key" | sed 's/[[:space:]]*$//')
    value="${line#*=}"
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$key" in
      YANDEX_CLIENT_ID) CLIENT_ID="$value" ;;
      YANDEX_CLIENT_SECRET) CLIENT_SECRET="$value" ;;
    esac
  fi
done < "$SECRETS_XCCONFIG"

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
  echo "YANDEX_CLIENT_ID или YANDEX_CLIENT_SECRET пусты в Secrets.xcconfig"
  exit 1
fi

echo "Добавление YANDEX_CLIENT_ID и YANDEX_CLIENT_SECRET в GitHub Secrets..."
echo "$CLIENT_ID" | gh secret set YANDEX_CLIENT_ID
echo "$CLIENT_SECRET" | gh secret set YANDEX_CLIENT_SECRET
echo "Готово. Секреты YANDEX добавлены."
