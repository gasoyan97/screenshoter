# Публичная сборка в DMG

## Без Apple Developer Program

Workflow и скрипты работают **без платной подписки** — создают DMG для размещения на своём сайте.

**Ограничение:** при первом запуске пользователю нужно правый клик → Открыть (macOS Gatekeeper). После этого приложение откроется нормально.

## Вариант 1: GitHub Actions (автоматически)

При пуше тега `v*` workflow создаёт ветку `release/X.Y.Z` (trunk base), собирает DMG и создаёт Release.

**Важно:** перед созданием тега обновите версию в `ScreenShoter/Info.plist`:
- `CFBundleShortVersionString` — версия для пользователя (0.0.5)
- `CFBundleVersion` — номер сборки (увеличивайте при каждом релизе)

```bash
git add .
git commit -m "Release 0.0.5"
git tag v0.0.5
git push origin main
git push origin v0.0.5
```

Workflow создаст ветку `release/0.0.5` от тега и соберёт билд из неё.

### Секреты (опционально)

**Без секретов** — сборка работает, создаётся DMG с ad-hoc подписью. **Важно:** после каждого обновления через Sparkle macOS будет запрашивать разрешения (Запись экрана, Уведомления) заново — ad-hoc подпись создаёт новую «личность» приложения при каждой сборке.

**С секретами** — подпись Developer ID и нотаризация. Разрешения сохраняются после обновлений. Без предупреждений Gatekeeper.

| Секрет | Описание |
|--------|----------|
| `BUILD_CERTIFICATE_BASE64` | Сертификат Developer ID Application (.p12) в base64 |
| `P12_PASSWORD` | Пароль от .p12 |
| `KEYCHAIN_PASSWORD` | Любой пароль (для временного keychain) |
| `APPLE_ID` | Apple ID (email) |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password |
| `TEAM_ID` | Team ID (10 символов) |
| `YANDEX_CLIENT_ID` | OAuth Client ID (Яндекс.Диск) для загрузки скриншотов |
| `YANDEX_CLIENT_SECRET` | OAuth Client Secret (Яндекс.Диск) |

### Экспорт сертификата

1. **Keychain Access** → найти «Developer ID Application: …»
2. ПКМ → Export → сохранить как .p12
3. В терминале: `base64 -i certificate.p12 | pbcopy`
4. Вставить в GitHub Secret `BUILD_CERTIFICATE_BASE64`

### App-specific password

1. appleid.apple.com → Sign-In and Security → App-Specific Passwords
2. Создать новый пароль
3. Добавить как секрет `APPLE_APP_SPECIFIC_PASSWORD`

---

## Вариант 2: Локальная сборка

```bash
./scripts/build-dmg.sh [версия]
# Пример: ./scripts/build-dmg.sh 0.0.2
```

Скрипт создаёт `ScreenShoter-X.Y.Z.dmg` и `ScreenShoter-X.Y.Z.zip`.

### Нотаризация (после сборки)

```bash
xcrun notarytool submit ScreenShoter-0.0.2.dmg \
  --apple-id "your@email.com" \
  --password "app-specific-password" \
  --team-id "XKL7SFFS36" \
  --wait

xcrun stapler staple ScreenShoter-0.0.2.dmg
```

### Публикация

1. Создать Release на GitHub (тег v0.0.2)
2. Загрузить `ScreenShoter-0.0.2.dmg` и `ScreenShoter-0.0.2.zip`
3. Workflow Release сгенерирует appcast для OTA

---

## Ссылка для скачивания

После релиза пользователи могут скачать:

- **Страница релизов:** https://github.com/gasoyan97/screnshoter/releases/latest
- **Прямая ссылка DMG:** `https://github.com/gasoyan97/screnshoter/releases/download/vX.Y.Z/ScreenShoter-X.Y.Z.dmg`
