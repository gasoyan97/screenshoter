# OAuth Яндекс.Диска: локальная разработка и CI

Credentials для Яндекс.Диска берутся из Secrets.xcconfig (локально) или GitHub Secrets (CI). Никогда не храните их в репозитории.

## Локальная разработка

1. Скопируйте шаблон:
   ```bash
   cp ScreenShoter/Secrets.xcconfig.example ScreenShoter/Secrets.xcconfig
   ```

2. Получите Client ID и Client Secret:
   - https://oauth.yandex.ru → создать приложение
   - Тип: «Веб-сервисы» или «Установленное приложение»
   - Права: `cloud_api:disk.write`, `cloud_api:disk.app_folder`

3. Заполните `ScreenShoter/Secrets.xcconfig`:
   ```
   YANDEX_CLIENT_ID = ваш_client_id
   YANDEX_CLIENT_SECRET = ваш_client_secret
   ```

4. `Secrets.xcconfig` в `.gitignore` — не коммитьте его.

При сборке скрипт `scripts/generate-oauth-secrets.sh` читает Secrets.xcconfig и генерирует `YandexOAuthSecrets.generated.swift`.

## CI (GitHub Actions)

Добавьте в репозиторий секреты:

- **YANDEX_CLIENT_ID** — Client ID из oauth.yandex.ru
- **YANDEX_CLIENT_SECRET** — Client Secret

**Быстро (если есть локальный Secrets.xcconfig):**
```bash
./scripts/add-yandex-secrets-to-github.sh
```

**Вручную:** Settings → Secrets and variables → Actions → New repository secret.

Workflow `build-dmg.yml` создаёт `Secrets.xcconfig` из этих секретов перед сборкой — credentials попадут в собранное приложение.

## Без credentials

Если не указать credentials, OAuth-подключение Яндекс.Диска в приложении будет недоступно (кнопка «Подключить» покажет сообщение о необходимости настройки).
