# OTA-обновления: настройка выполнена

## Что сделано

1. **Info.plist** — добавлены SUFeedURL, SUPublicEDKey, SUAllowsAutomaticUpdates
2. **EdDSA-ключи** — сгенерированы, публичный ключ в Info.plist
3. **SUFeedURL** — `https://gasoyan97.github.io/screnshoter/appcast.xml`

## Осталось сделать вручную

### 1. Добавить GitHub Secret

Приватный ключ сохранён в `.sparkle-secrets/` (папка в .gitignore).

**Через веб-интерфейс:**
1. Откройте https://github.com/gasoyan97/screnshoter/settings/secrets/actions
2. New repository secret
3. Name: `SPARKLE_PRIVATE_KEY`
4. Value: содержимое файла `.sparkle-secrets/SPARKLE_PRIVATE_KEY_BASE64.txt`

**Через gh CLI:**
```bash
gh secret set SPARKLE_PRIVATE_KEY < .sparkle-secrets/SPARKLE_PRIVATE_KEY_BASE64.txt
```

### 2. Включить GitHub Pages

1. https://github.com/gasoyan97/screnshoter/settings/pages
2. Source: **GitHub Actions**

### 3. Первый релиз

1. Соберите приложение (Product → Archive)
2. Экспортируйте .app, упакуйте: `ditto -c -k --sequesterRsrc --keepParent ScreenShoter.app ScreenShoter-0.0.1.zip`
3. Нотаризуйте
4. Создайте Release на GitHub, загрузите .zip
5. Workflow сгенерирует appcast и задеплоит на Pages

## Важно

- Папка `.sparkle-secrets/` содержит приватный ключ — **не коммитить**
- Резервная копия ключа: сохраните `.sparkle-secrets/` в надёжное место
- При потере ключа потребуется смена ключей (см. Sparkle docs)
