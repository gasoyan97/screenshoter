# OTA-обновления ScreenShoter (Sparkle)

Документация по настройке и публикации обновлений по воздуху через [Sparkle](https://sparkle-project.org/).

## Первоначальная настройка

### 1. Генерация EdDSA-ключей

Sparkle требует Ed25519-подпись для безопасной доставки обновлений.

```bash
# Клонировать Sparkle
git clone https://github.com/sparkle-project/Sparkle.git
cd Sparkle

# Сгенерировать ключи
./bin/generate_keys
```

Сохраните вывод:
- **Публичный ключ** → в `Info.plist` как `SUPublicEDKey`
- **Приватный ключ** → храните секретно (например, в 1Password, GitHub Secrets). Используется для подписи архивов при релизе.

### 2. Обновить Info.plist

Замените в `ScreenShoter/Info.plist`:

- `SUFeedURL` — URL вашего appcast.xml (GitHub Pages или свой сервер)
- `SUPublicEDKey` — публичный Ed25519 ключ из шага 1

Пример для GitHub Pages:
```xml
<key>SUFeedURL</key>
<string>https://YOUR_USERNAME.github.io/scrinsjater/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>BASE64_PUBLIC_KEY_ИЗ_GENERATE_KEYS</string>
```

---

## Ручной релиз

### Шаг 1: Сборка и архивация

1. В Xcode: **Product → Archive**
2. В Organizer: **Distribute App** → **Developer ID** → экспорт `.app`
3. Упаковать в ZIP (симлинки должны сохраниться):

```bash
ditto -c -k --sequesterRsrc --keepParent ScreenShoter.app ScreenShoter-1.0.0.zip
```

### Шаг 2: Нотаризация

```bash
xcrun notarytool submit ScreenShoter-1.0.0.zip \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

xcrun stapler staple ScreenShoter.app
# Затем пересоздать ZIP после stapler
ditto -c -k --sequesterRsrc --keepParent ScreenShoter.app ScreenShoter-1.0.0.zip
```

### Шаг 3: Подпись Sparkle

```bash
# Из папки Sparkle (или artifacts Sparkle после SPM)
./bin/sign_update /path/to/ScreenShoter-1.0.0.zip
```

Вывод:
```
sparkle:edSignature="..." length="1234567"
```

### Шаг 4: Обновить appcast.xml

Добавить новый `<item>` в `appcast.xml`:

```xml
<item>
    <title>Version 1.0.0 — исправления и улучшения</title>
    <link>https://github.com/your/repo/releases</link>
    <sparkle:version>3</sparkle:version>
    <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
    <sparkle:releaseNotesLink>https://github.com/your/repo/releases/tag/v1.0.0</sparkle:releaseNotesLink>
    <pubDate>Sat, 08 Feb 2025 12:00:00 +0000</pubDate>
    <enclosure
        url="https://your-domain.com/screenShoter/ScreenShoter-1.0.0.zip"
        sparkle:edSignature="ВСТАВИТЬ_ИЗ_SIGN_UPDATE"
        length="РАЗМЕР_ФАЙЛА_В_БАЙТАХ"
        type="application/octet-stream" />
</item>
```

- `sparkle:version` = `CFBundleVersion` (build number)
- `sparkle:shortVersionString` = `CFBundleShortVersionString`
- `length` = размер ZIP в байтах (`ls -l ScreenShoter-1.0.0.zip`)

### Шаг 5: Публикация

Загрузить на сервер:
- `appcast.xml`
- `ScreenShoter-1.0.0.zip`

Для GitHub Pages: включить Pages в настройках репозитория, положить файлы в ветку `gh-pages` или папку `docs/` (в зависимости от настроек).

---

## GitHub Actions (автоматический релиз)

См. `.github/workflows/release.yml` — workflow запускается при публикации GitHub Release. Скачивает .zip/.dmg из релиза, генерирует appcast.xml и публикует на GitHub Pages.

**Использование:**
1. Соберите и нотаризуйте приложение локально
2. Подпишите архив: `./bin/sign_update ScreenShoter.zip` (или generate_appcast подпишет автоматически)
3. Создайте Release на GitHub, загрузите .zip как asset
4. Workflow сгенерирует appcast и задеплоит на Pages

**Требуемые секреты:**
- `SPARKLE_PRIVATE_KEY` — приватный Ed25519 ключ в base64:
  ```bash
  ./bin/generate_keys -x private_key.pem
  base64 -i private_key.pem  # Скопировать вывод в секрет
  ```

**Настройки репозитория:**
- GitHub Pages: Settings → Pages → Source: GitHub Actions
- SUFeedURL в Info.plist уже настроен: `https://gasoyan97.github.io/screnshoter/appcast.xml`

**Добавление секрета вручную:**
1. Скопируйте содержимое `.sparkle-secrets/SPARKLE_PRIVATE_KEY_BASE64.txt`
2. GitHub → Settings → Secrets and variables → Actions → New repository secret
3. Name: `SPARKLE_PRIVATE_KEY`, Value: вставьте скопированное

---

## Формат appcast.xml

Шаблон полного appcast см. в `docs/appcast.xml.example`.
