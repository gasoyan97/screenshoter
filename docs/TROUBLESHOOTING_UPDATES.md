# Ошибка «An error occurred in retrieving update information»

## Причина
Sparkle не может загрузить appcast.xml по адресу SUFeedURL. Обычно это 404 — файл недоступен.

## Решение

### 1. Включить GitHub Pages
1. Репозиторий → **Settings** → **Pages**
2. **Build and deployment** → **Source**: выберите **GitHub Actions**
3. Сохраните (если нужно)

### 2. Запустить деплой
Workflow `Deploy appcast` деплоит минимальный appcast при каждом push в main. Сделайте пустой коммит и push:

```bash
git commit --allow-empty -m "Trigger appcast deploy"
git push origin main
```

### 3. Проверить URL
Откройте в браузере:
https://gasoyan97.github.io/screnshoter/appcast.xml

Должен открыться XML. Если 404 — подождите 1–2 минуты после push.

### 4. После релиза
При создании Release (например, `git tag v0.0.4 && git push origin v0.0.4`) workflow **Release** сгенерирует полный appcast из .zip и перезапишет страницу. Убедитесь, что секрет `SPARKLE_PRIVATE_KEY` настроен.
