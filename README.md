# ScreenShoter

Нативное приложение для macOS (Apple Silicon) на Swift/SwiftUI: скриншоты из меню-бара, аннотации и загрузка в облако по WebDAV (Nextcloud, Яндекс.Диск по WebDAV и т.п.).

## Требования

- macOS 14+
- Xcode 15+

## Сборка и запуск

```bash
open ScreenShoter.xcodeproj
```

В Xcode: Product → Build (⌘B), затем Product → Run (⌘R).

Приложение появится в меню-баре macOS (иконка crop). Клик — выбор режима захвата.

### Вариант с XcodeGen (опционально)

```bash
xcodegen generate
open ScreenShoter.xcodeproj
```

## Публичная сборка (релиз для распространения)

Проект подготовлен к подписи и нотаризации Apple: включён Hardened Runtime, настроены entitlements и Info.plist.

### 1. Подпись (Developer ID)

1. В Xcode откройте проект → выберите target **ScreenShoter** → вкладка **Signing & Capabilities**.
2. Укажите **Team** (аккаунт Apple Developer).
3. Для распространения вне App Store выберите **Sign to Run Locally** или **Developer ID Application**.

### 2. Архив и экспорт

1. **Product → Archive** (схема Release).
2. В Organizer: **Distribute App** → **Developer ID** (или Custom) → **Next** → экспортируйте `.app` или создайте **Copy App**.
3. При необходимости упакуйте в DMG (например, через скрипт или [create-dmg](https://github.com/create-dmg/create-dmg)).

### 3. Нотаризация (обязательно для macOS 10.15+)

После подписи отправьте приложение (или DMG) на нотаризацию:

```bash
# Отправка на нотаризацию (нужен Apple ID + app-specific password)
xcrun notarytool submit ScreenShoter.app.zip --apple-id "your@email.com" --team-id "TEAM_ID" --password "app-specific-password" --wait

# После успеха — «прикрепить» штамп к приложению
xcrun stapler staple ScreenShoter.app
```

Для DMG: сначала подшейте штамп к `.app` внутри DMG, затем при необходимости подшейте к самому DMG.

### 4. Версия и сборка

- **Версия для пользователя:** `CFBundleShortVersionString` в Info.plist (например, 1.0.0).
- **Номер сборки:** `CFBundleVersion` в Info.plist (увеличивайте при каждой загрузке в нотаризацию/дистрибуцию).

### 5. OTA-обновления (Sparkle)

Приложение поддерживает обновления по воздуху через [Sparkle](https://sparkle-project.org/). Настройка выполнена. Осталось:
1. Добавить `SPARKLE_PRIVATE_KEY` в GitHub Secrets (см. [docs/SPARKLE_SETUP_DONE.md](docs/SPARKLE_SETUP_DONE.md))
2. Включить GitHub Pages (Source: GitHub Actions)

Подробная инструкция — [docs/OTA_UPDATES.md](docs/OTA_UPDATES.md).

## Структура проекта

- **ScreenShoter/** — исходный код приложения
- **ScreenShoter.entitlements** — права для Hardened Runtime и подписи
- **ScreenShoter.xcodeproj** — проект Xcode
- **assets/** — исходная иконка (icon.png) для генерации AppIcon

## Архитектура

- **ScreenShoterApp** — точка входа, MenuBarExtra
- **LauncherMenuView** — меню с кнопками захвата
- **ScreenshotService** — вызов `screencapture` CLI
- **AnnotationView** — редактирование (стрелки, выделения)
- **WebDAVUploader** — загрузка в облако по WebDAV
- **SetupView** — пошаговая установка при первом запуске
- **SettingsView** — настройки (путь, формат, WebDAV, обои, автозапуск)
- **HistoryView** — история загрузок
