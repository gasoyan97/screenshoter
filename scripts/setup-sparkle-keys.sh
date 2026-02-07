#!/bin/bash
# Настройка EdDSA ключей для Sparkle OTA-обновлений
# Генерирует ключи, обновляет Info.plist, сохраняет приватный ключ для GitHub Secrets
set -e
cd "$(dirname "$0")/.."
SPARKLE_DIR=".sparkle-tools"
SPARKLE_VERSION="2.8.1"
KEYS_DIR=".sparkle-secrets"
mkdir -p "$KEYS_DIR"

echo "Загрузка Sparkle $SPARKLE_VERSION..."
if [ ! -f "$SPARKLE_DIR/Sparkle/bin/generate_keys" ]; then
  mkdir -p "$SPARKLE_DIR"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" -o "$SPARKLE_DIR/sparkle.tar.xz"
  tar -xf "$SPARKLE_DIR/sparkle.tar.xz" -C "$SPARKLE_DIR"
fi

SEED_FILE="$KEYS_DIR/ed25519_seed.b64"
if [ ! -f "$SEED_FILE" ]; then
  echo "Генерация нового ключа..."
  dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d '\n' > "$SEED_FILE"
fi

echo "Импорт ключа..."
"$SPARKLE_DIR/Sparkle/bin/generate_keys" -f "$SEED_FILE"

echo "Экспорт приватного ключа для GitHub Secrets..."
"$SPARKLE_DIR/Sparkle/bin/generate_keys" -x "$KEYS_DIR/private_key.pem"

base64 -i "$KEYS_DIR/private_key.pem" | tr -d '\n' > "$KEYS_DIR/SPARKLE_PRIVATE_KEY_BASE64.txt"

PUBKEY=$("$SPARKLE_DIR/Sparkle/bin/generate_keys" -p)
echo ""
echo "Публичный ключ добавлен в Info.plist: $PUBKEY"
# Обновляем Info.plist
if [[ "$OSTYPE" == "darwin"* ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBKEY" ScreenShoter/Info.plist
  echo "Info.plist обновлён."
fi

echo ""
echo "Готово. Добавьте секрет в GitHub:"
echo "  gh secret set SPARKLE_PRIVATE_KEY < $KEYS_DIR/SPARKLE_PRIVATE_KEY_BASE64.txt"
echo "Или: ./scripts/add-sparkle-secret-to-github.sh"
