# Репозиторий «screnshoter» — фид обновлений для старых установок

Старые версии приложения проверяют обновления по адресу  
`https://gasoyan97.github.io/screnshoter/appcast.xml`.  
После переименования репо в **screenshoter** этот URL перестал работать.  
Здесь — минимальный репозиторий с одним релизом (0.0.9), чтобы старые приложения один раз обновились и перешли на новый фид.

## Шаги

### 1. Создать репозиторий на GitHub

1. [New repository](https://github.com/new)
2. Имя: **screnshoter** (без «t», как было в старом SUFeedURL)
3. Public, без README, .gitignore и лицензии
4. Create repository

### 2. Включить GitHub Pages

- Settings → Pages → Source: **GitHub Actions** (или Deploy from a branch: main, / (root))

### 3. Подготовить appcast.xml

- В `appcast.xml` уже есть один элемент — версия **0.0.9**, ссылка на скачивание ведёт на новый репо:  
  `https://github.com/gasoyan97/screenshoter/releases/download/v0.0.9/ScreenShoter-0.0.9.zip`
- **После** того как соберёте и выложите 0.0.9 в репо **screenshoter**:
  1. Скачайте `ScreenShoter-0.0.9.zip` с Releases
  2. Размер в байтах: `stat -f%z ScreenShoter-0.0.9.zip` (macOS) — подставьте в `length="..."`
  3. Подпись архива (EdDSA): из корня Sparkle выполните  
     `./bin/sign_update path/to/ScreenShoter-0.0.9.zip`  
     (ключ из Keychain или `-f key.pem`). В выводе будет `sparkle:edSignature="..."`
  4. Вставьте значение подписи в атрибут `sparkle:edSignature` в `appcast.xml`
- Подпись самого appcast (рекомендуется):  
  `./bin/sign_update --sign-appcast path/to/appcast.xml`  
  Перезаписать `appcast.xml` подписанным содержимым и закоммитить его.

### 4. Опубликовать appcast в этом репо

**Вариант A: GitHub Actions (рекомендуется)**

- В репо **screnshoter** создайте workflow, который при push в main деплоит `appcast.xml` в Pages (аналогично основному проекту: `actions/configure-pages`, `upload-pages-artifact` с папкой, где лежит appcast, `deploy-pages`).
- Положите готовый (с подставленными length и edSignature и при необходимости подписанный) `appcast.xml` в корень или в папку `pages/`, настройте workflow так, чтобы артефактом для Pages была эта папка/файл.
- После push в main дождитесь деплоя — фид будет доступен по  
  `https://gasoyan97.github.io/screnshoter/appcast.xml`

**Вариант B: Ветка main как источник Pages**

- Включите Pages: Source = branch **main**, folder = **/ (root)**
- В корень main положите один файл: `appcast.xml` (уже с length и edSignature и при желании подписанный)
- После push фид будет по тому же URL

### 5. Проверка

- Откройте в браузере: https://gasoyan97.github.io/screnshoter/appcast.xml  
- Должен отображаться XML с одним `<item>` для 0.0.9 и `enclosure` с URL нового репо.

После обновления до 0.0.9 у приложения в Info.plist будет уже новый SUFeedURL:  
`https://gasoyan97.github.io/screenshoter/appcast.xml` — дальнейшие обновления пойдут оттуда.
