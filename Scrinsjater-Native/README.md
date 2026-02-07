# Scrinsjater — нативная macOS-версия

Нативное приложение для macOS (Apple Silicon) на Swift/SwiftUI.

## Требования

- macOS 14+
- Xcode 15+

## Сборка и запуск

```bash
cd Scrinsjater-Native
xcodegen generate   # если проект ещё не сгенерирован
open Scrinsjater.xcodeproj
```

В Xcode: Product → Build (⌘B), затем Product → Run (⌘R).

Приложение появится в меню-баре macOS (иконка crop). Клик — выбор режима захвата.

### Вариант 2: Ручное создание проекта в Xcode

1. Откройте Xcode → File → New → Project
2. Выберите macOS → App
3. Product Name: Scrinsjater, Interface: SwiftUI, Language: Swift
4. Укажите папку `Scrinsjater-Native`
5. Добавьте все файлы из папки `Scrinsjater/` в проект
6. В Build Settings установите:
   - Mac Catalyst: No
   - Supported Platforms: macOS
   - Architectures: arm64 (или Standard Architectures)
7. В Info добавьте `LSUIElement` = YES (приложение только в меню-баре)

## Архитектура

- **ScrinsjaterApp** — точка входа, MenuBarExtra
- **LauncherMenuView** — меню с кнопками захвата
- **ScreenshotService** — вызов `screencapture` CLI
- **AnnotationView** — редактирование (стрелки, выделения)
- **YandexUploader** — загрузка на Яндекс.Диск

## Иконка

Скопируйте `icon.png` в Assets.xcassets/AppIcon.appiconset для иконки приложения.
