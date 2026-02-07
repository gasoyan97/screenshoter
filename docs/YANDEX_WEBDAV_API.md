# Анализ Yandex WebDAV API для ScreenShoter

## Источники

- [Disk WebDAV API](https://yandex.com/dev/disk/webdav/) — обзор
- [Publishing files and folders](https://yandex.com/dev/disk/doc/en/reference/publish) — публикация и публичная ссылка

---

## 1. Подключение (аутентификация)

### Варианты

| Способ | Описание |
|--------|----------|
| **OAuth** | В заголовке: `Authorization: OAuth <access_token>`. Токен получают через [Yandex OAuth](https://yandex.com/dev/oauth/). |
| **Basic (логин + пароль приложения)** | В заголовке: `Authorization: Basic <base64(login:password)>`. **Пароль** — только **пароль приложения** (id.yandex.ru → Безопасность → Пароли приложений), не основной пароль. При 2FA основной пароль для WebDAV не подойдёт. |

В приложении используется **Basic** с логином (email) и паролем приложения — это корректный сценарий для WebDAV.

### Хост и URL

- **WebDAV:** `https://webdav.yandex.ru` (в примерах в документации). Также встречается `https://webdav.yandex.com` — оба варианта допустимы.
- В настройках у пользователя должен быть указан полный URL с `https://`, логин и пароль приложения.

### Проверка подключения

- Запрос **PROPFIND** на корень с `Depth: 1` и телом с `<propfind xmlns="DAV:">...</propfind>`.
- Успех: ответ **207 Multi-Status** или **200 OK**.
- Ошибка **401**: неверный логин или пароль (для Яндекса — напомнить про пароль приложения и задержку 2–3 часа для нового пароля).

---

## 2. Загрузка файла (PUT)

- **Метод:** `PUT`
- **URL:** `https://webdav.yandex.ru/<путь>/<имя_файла>` (в приложении — папка `ScreenShoter_mac`).
- **Заголовки:** `Authorization: Basic ...`, `Content-Type: application/octet-stream`, `Content-Length: <размер>`.
- **Тело:** бинарное содержимое файла.
- Успех: **200** или **201** (или **204** в зависимости от сервера).

Перед первой загрузкой папку создаём запросом **MKCOL** на URL папки (201 — создана, 405 — уже есть).

---

## 3. Публичная ссылка (публикация файла)

### Запрос

- **Метод:** `PROPPATCH`
- **URL:** тот же, что и у загруженного файла (полный WebDAV-URL файла).
- **Заголовки:**  
  - `Authorization: Basic ...` (или `OAuth ...`)  
  - `Content-Type: application/xml; charset=utf-8`
- **Тело (XML):**

```xml
<propertyupdate xmlns="DAV:">
  <set>
    <prop>
      <public_url xmlns="urn:yandex:disk:meta">true</public_url>
    </prop>
  </set>
</propertyupdate>
```

Любое непустое значение `public_url` (например, `true`) включает публикацию.

### Ответ при успехе

- **Код:** `207 Multi-Status`
- **Тело (XML):**

```xml
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/ScreenShoter_mac/имя_файла.png</d:href>
    <d:propstat>
      <d:status>HTTP/1.1 200 OK</d:status>
      <d:prop>
        <public_url xmlns="urn:yandex:disk:meta"> http://yadi.sk/d/XXXXXXXX </public_url>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
```

Публичная ссылка возвращается в элементе **`public_url`** (namespace `urn:yandex:disk:meta`). В значении могут быть пробелы в начале и конце — при парсинге нужно делать `trim`.

### Поведение

- Если файл уже опубликован, Яндекс возвращает **ту же** ранее выданную ссылку.
- Ссылка имеет вид `http://yadi.sk/d/...` (или `https://...`).

### Надёжный парсинг 207

- Искать элемент `public_url` (по `local-name()` без привязки к namespace).
- Предпочтительно брать `public_url` из блока `propstat`, где `status` содержит `200 OK`, чтобы не взять пустое значение из блока с ошибкой (404 и т.п.).
- Результат обрезать по краям от пробелов и проверить на непустоту.

---

## 4. Рекомендации для приложения

1. **Подключение:** оставить Basic (логин + пароль приложения). В подсказках при 401 явно указывать: пароль приложения, раздел «Пароли приложений», задержка 2–3 часа для нового пароля.
2. **Определение Яндекса:** проверять по вхождению `"yandex"` в URL (поддержка и `webdav.yandex.ru`, и `webdav.yandex.com`).
3. **Публикация:** после успешного PUT вызывать PROPPATCH на тот же URL файла; при 207 парсить публичную ссылку из `public_url` в успешном `propstat` (status 200), с `trim`.
4. **PROPPATCH:** указывать `Content-Length` для тела запроса (хорошая практика для WebDAV).
5. **Таймауты:** оставить увеличенные таймауты для загрузки и PROPPATCH — серверы Яндекса могут отвечать медленно.

Этого достаточно для стабильного подключения к Yandex WebDAV и получения публичной ссылки на загруженный файл в рамках текущего приложения.
