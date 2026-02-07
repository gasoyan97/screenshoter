#!/bin/bash
# Добавляет SPARKLE_PRIVATE_KEY в GitHub Secrets (требует gh CLI)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRET_FILE="$SCRIPT_DIR/../.sparkle-secrets/SPARKLE_PRIVATE_KEY_BASE64.txt"
if [ ! -f "$SECRET_FILE" ]; then
  echo "Файл $SECRET_FILE не найден. Сначала запустите scripts/setup-sparkle-keys.sh"
  exit 1
fi
echo "Добавление SPARKLE_PRIVATE_KEY в GitHub Secrets..."
gh secret set SPARKLE_PRIVATE_KEY --body "$(cat "$SECRET_FILE")"
echo "Готово. Секрет SPARKLE_PRIVATE_KEY добавлен."
