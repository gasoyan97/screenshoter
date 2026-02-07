# ScreenShoter

Нативное приложение для macOS — скриншоты из меню-бара, аннотации и загрузка в облако по WebDAV.

## Возможности

- **Захват экрана** — весь экран, окно или выбранная область
- **Прокручиваемые скриншоты** — длинные страницы в один кадр
- **Аннотации** — стрелки, выделения, текст
- **Облако** — загрузка в Nextcloud, Яндекс.Диск (WebDAV) и другие
- **Автообновления** — Sparkle

## Скачать

**[Скачать последнюю версию](https://github.com/gasoyan97/screnshoter/releases/latest)** (DMG)

## Требования

- macOS 14+
- Apple Silicon или Intel

## Технологии

Swift · SwiftUI · WebDAV · Sparkle

## FAQ

**После обновления снова просят разрешения (Запись экрана)?**  
macOS привязывает разрешения к подписи приложения. Сборка без Developer ID создаёт новую «личность» при каждой версии. Подробнее: [docs/TROUBLESHOOTING_PERMISSIONS.md](docs/TROUBLESHOOTING_PERMISSIONS.md)

## Разработка

Для работы загрузки в Яндекс.Диск нужны OAuth credentials. Локально: скопируйте `ScreenShoter/Secrets.xcconfig.example` в `ScreenShoter/Secrets.xcconfig` и заполните Client ID/Secret. Подробнее: [docs/OAUTH_SETUP.md](docs/OAUTH_SETUP.md)
