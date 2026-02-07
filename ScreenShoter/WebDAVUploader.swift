import Foundation
import os.log

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenShoter", category: "WebDAV")

struct WebDAVUploadResult {
    let fileName: String
    let fileURL: URL
    /// Публичная ссылка (yadi.sk), если сервер — Яндекс.Диск и публикация прошла успешно.
    let publicURL: String?
}

final class WebDAVUploader {
    static let shared = WebDAVUploader()

    static func friendlyUploadErrorMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "WebDAVUpload",
           let msg = ns.userInfo[NSLocalizedDescriptionKey] as? String, !msg.isEmpty {
            return msg
        }
        if let urlError = error as? URLError, urlError.code == .unsupportedURL {
            return "Неверный или неподдерживаемый адрес. Проверьте URL в настройках (должен начинаться с https://)."
        }
        let desc = error.localizedDescription
        if desc.lowercased().contains("unsupported url") {
            return "Неверный или неподдерживаемый адрес. Проверьте URL в настройках (должен начинаться с https://)."
        }
        return desc
    }

    /// Async-safe кэш baseURL, для которых уже создана папка на WebDAV (без NSLock в async-контексте).
    private actor FolderCache {
        private var ensured: Set<String> = []
        func contains(_ key: String) -> Bool { ensured.contains(key) }
        func insert(_ key: String) { ensured.insert(key) }
    }

    /// Папка на WebDAV (Яндекс.Диск и др.), куда кладём скриншоты.
    private static let remoteFolderName = "ScreenShoter_mac"

    /// Сессия с увеличенным таймаутом для WebDAV (Яндекс и др. могут отвечать медленно).
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    /// Кэш: для какого baseURL уже создана папка (чтобы не слать MKCOL при каждой загрузке).
    private let folderCache = FolderCache()

    private init() {}

    func upload(fileURL: URL, username: String, password: String) async throws -> WebDAVUploadResult {
        let baseURL = AppSettings.webdavURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.isEmpty ? AppSettings.webdavUsername : username
        let pass = password.isEmpty ? AppSettings.webdavPassword : password

        guard !baseURL.isEmpty, !user.isEmpty, !pass.isEmpty else {
            var missing: [String] = []
            if baseURL.isEmpty { missing.append("URL сервера") }
            if user.isEmpty { missing.append("логин") }
            if pass.isEmpty { missing.append("пароль") }
            let hint = missing.isEmpty ? "Укажите WebDAV в настройках." : "В настройках укажите: \(missing.joined(separator: ", "))."
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: hint])
        }
        return try await uploadViaWebDAV(fileURL: fileURL, baseURL: baseURL, username: user, password: pass)
    }

    private func uploadViaWebDAV(fileURL: URL, baseURL: String, username: String, password: String) async throws -> WebDAVUploadResult {
        var urlString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.contains("://") { urlString = "https://" + urlString }
        if !urlString.hasSuffix("/") { urlString += "/" }
        guard let base = URL(string: urlString), base.scheme == "http" || base.scheme == "https" else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный WebDAV URL. Укажите полный адрес с https:// (например https://webdav.yandex.ru)"])
        }
        try await ensureFolderExistsIfNeeded(baseURL: urlString, username: username, password: password)

        let fileName = fileURL.lastPathComponent
        guard let remoteURL = buildUploadURL(baseURL: base, folder: Self.remoteFolderName, fileName: fileName) else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный WebDAV URL. Укажите полный адрес с https://"])
        }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let credential = "\(username):\(password)"
        guard let credentialData = credential.data(using: .utf8) else { throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования"]) }

        var lastError: Error?
        var lastData: Data?
        var lastResponse: URLResponse?
        for attempt in 1...2 {
            var request = URLRequest(url: remoteURL)
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
            request.setValue("Basic \(credentialData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            request.setValue("ScreenShoter/1.0 (WebDAV)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await uploadWithRetryIfYandex(request: request, fileURL: fileURL, urlString: urlString)
                guard let http = response as? HTTPURLResponse else {
                    lastError = NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки WebDAV (нет ответа сервера)"])
                    if attempt == 1 { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                    throw lastError!
                }
                if (200...299).contains(http.statusCode) {
                    lastData = data
                    lastResponse = response
                    lastError = nil
                    break
                }
                if (500...599).contains(http.statusCode), attempt == 1 {
                    lastError = NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: webDAVErrorMessage(statusCode: http.statusCode, url: urlString, responseData: data)])
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                var msg = webDAVErrorMessage(statusCode: http.statusCode, url: urlString, responseData: data)
                msg += " Код ответа: \(http.statusCode)."
                if let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !body.isEmpty, body.count < 400, !body.hasPrefix("<") {
                    msg += " Ответ: \(body)"
                }
                throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            } catch let urlError as URLError where isTransientURLError(urlError) {
                lastError = urlError
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                throw NSError(domain: "WebDAVUpload", code: urlError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить после повторной попытки. Проверьте интернет или попробуйте другой URL (webdav.yandex.com / webdav.yandex.ru)."])
            } catch {
                throw error
            }
        }

        guard let _ = lastData, let response = lastResponse else {
            if let e = lastError { throw e }
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки WebDAV"])
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let e = lastError { throw e }
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка загрузки WebDAV"])
        }

        var publicURL: String?
        if urlString.lowercased().contains("yandex") {
            // Яндекс не сразу отдаёт public_url после PUT — пробуем несколько раз с паузами.
            let delays: [UInt64] = [0, 2, 4, 6, 8]
            for delaySec in delays {
                if delaySec > 0 { try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000) }
                publicURL = await publishFileOnYandex(remoteURL: remoteURL, username: username, password: password)
                if publicURL != nil { break }
            }
        }

        return WebDAVUploadResult(fileName: fileName, fileURL: remoteURL, publicURL: publicURL)
    }

    /// Временные сетевые ошибки, при которых имеет смысл повторить запрос.
    private func isTransientURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// Для Яндекса: одна повторная попытка при таймауте (сервер часто отвечает медленно).
    private func uploadWithRetryIfYandex(request: URLRequest, fileURL: URL, urlString: String) async throws -> (Data, URLResponse) {
        do {
            return try await uploadFromFile(request: request, fileURL: fileURL)
        } catch let urlError as URLError where urlError.code == .timedOut && urlString.lowercased().contains("yandex") {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return try await uploadFromFile(request: request, fileURL: fileURL)
        }
    }

    /// Загрузка из файла стримингом (без загрузки всего файла в память). Быстрее старт и меньше памяти.
    private func uploadFromFile(request: URLRequest, fileURL: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = session.uploadTask(with: request, fromFile: fileURL) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет ответа сервера"]))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    /// Публикует файл на Яндекс.Диске (PROPPATCH public_url) и возвращает ссылку yadi.sk или nil.
    private func publishFileOnYandex(remoteURL: URL, username: String, password: String) async -> String? {
        let body = """
        <propertyupdate xmlns="DAV:">
          <set>
            <prop>
              <public_url xmlns="urn:yandex:disk:meta">true</public_url>
            </prop>
          </set>
        </propertyupdate>
        """
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PROPPATCH"
        let bodyData = body.data(using: .utf8)
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(bodyData?.count ?? 0)", forHTTPHeaderField: "Content-Length")
        request.httpBody = bodyData
        let credential = "\(username):\(password)"
        guard let credentialData = credential.data(using: .utf8) else { return nil }
        request.setValue("Basic \(credentialData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (WebDAV)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                log.error("PROPPATCH: не HTTPURLResponse")
                return nil
            }
            guard http.statusCode == 207 else {
                log.error("PROPPATCH status=\(http.statusCode) body=\(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            if let link = parsePublicURLFromMultistatusResponse(data) {
                return link
            }
            log.error("PROPPATCH 207, но public_url не найден в XML: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            return nil
        } catch {
            log.error("PROPPATCH ошибка: \(error.localizedDescription)")
            return nil
        }
    }

    /// Достаёт public_url (yadi.sk) из ответа 207 Multi-Status (XML). Берёт ссылку из propstat со статусом 200 OK.
    private func parsePublicURLFromMultistatusResponse(_ data: Data) -> String? {
        guard let doc = try? XMLDocument(data: data) else { return nil }
        // 1. Предпочтительно: public_url из блока propstat со статусом 200 OK (успешная публикация)
        if let node = try? doc.nodes(forXPath: "//*[local-name()='propstat'][.//*[local-name()='status'][contains(.,'200')]]//*[local-name()='public_url']").first as? XMLElement,
           let text = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.contains("yadi.sk") {
            return text
        }
        // 2. Любой непустой public_url
        let fallback = try? doc.nodes(forXPath: "//*[local-name()='public_url']")
        if let node = fallback?.first(where: { ($0 as? XMLElement)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) as? XMLElement,
           let text = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.contains("yadi.sk") {
            return text
        }
        // 3. Поиск ссылки yadi.sk в сыром XML (если формат ответа изменился)
        if let raw = String(data: data, encoding: .utf8),
           let range = raw.range(of: #"https?://[^"'\s<>]*yadi\.sk/d/[^"'\s<>]+"#, options: .regularExpression) {
            return String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Собирает URL для PUT: base + папка + имя файла с корректным percent-encoding имени файла.
    private func buildUploadURL(baseURL: URL, folder: String, fileName: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/\(folder)/\(encodedFileName)"
        return components?.url
    }

    /// Создаёт папку ScreenShoter_mac на WebDAV, если её ещё нет (MKCOL). Кэширует успех по baseURL, чтобы не слать MKCOL при каждой загрузке.
    private func ensureFolderExistsIfNeeded(baseURL: String, username: String, password: String) async throws {
        let key = baseURL
        if await folderCache.contains(key) { return }
        try await ensureFolderExists(baseURL: baseURL, username: username, password: password)
        await folderCache.insert(key)
    }

    /// Один запрос MKCOL для создания папки. 201 = создана, 405 = уже есть.
    private func ensureFolderExists(baseURL: String, username: String, password: String) async throws {
        let folderPath = Self.remoteFolderName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? Self.remoteFolderName
        let folderURLString = baseURL.hasSuffix("/") ? baseURL + folderPath + "/" : baseURL + "/" + folderPath + "/"
        guard let folderURL = URL(string: folderURLString), folderURL.scheme == "http" || folderURL.scheme == "https" else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный WebDAV URL для создания папки. Укажите полный адрес с https://"])
        }
        var request = URLRequest(url: folderURL)
        request.httpMethod = "MKCOL"
        let credential = "\(username):\(password)"
        guard let credentialData = credential.data(using: .utf8) else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования учётных данных."])
        }
        request.setValue("Basic \(credentialData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (WebDAV)", forHTTPHeaderField: "User-Agent")
        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw NSError(domain: "WebDAVUpload", code: urlError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Превышено время ожидания ответа от сервера. Проверьте интернет или попробуйте позже."])
        } catch {
            throw error
        }
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 201: break // папка создана
        case 405: break // папка уже существует (MKCOL не разрешён на существующем ресурсе)
        case 401, 403, 404, 409, 507:
            let msg = webDAVErrorMessage(statusCode: http.statusCode, url: baseURL, responseData: nil)
            throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        default:
            if http.statusCode >= 500 {
                throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка сервера при создании папки. Попробуйте позже."])
            }
            throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Неожиданный ответ сервера при создании папки (\(http.statusCode)). Проверьте URL и доступ."])
        }
    }

    /// Проверка подключения к WebDAV (PROPFIND на корень). Для отладки и кнопки «Проверить подключение».
    func testConnection(baseURL: String? = nil, username: String? = nil, password: String? = nil) async throws {
        let url = (baseURL ?? AppSettings.webdavURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username ?? AppSettings.webdavUsername
        let pass = password ?? AppSettings.webdavPassword
        guard !url.isEmpty, !user.isEmpty, !pass.isEmpty else {
            var missing: [String] = []
            if url.isEmpty { missing.append("URL") }
            if user.isEmpty { missing.append("логин") }
            if pass.isEmpty { missing.append("пароль") }
            let hint = missing.isEmpty ? "Укажите URL, логин и пароль." : "Заполните: \(missing.joined(separator: ", "))."
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: hint])
        }
        var urlString = url
        if !urlString.contains("://") { urlString = "https://" + urlString }
        if !urlString.hasSuffix("/") { urlString += "/" }
        guard let testURL = URL(string: urlString), testURL.scheme == "http" || testURL.scheme == "https" else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный WebDAV URL."])
        }
        var request = URLRequest(url: testURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let bodyData = """
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:"><prop><displayname/><resourcetype/></prop></propfind>
        """.data(using: .utf8)
        request.httpBody = bodyData
        request.setValue("\(bodyData?.count ?? 0)", forHTTPHeaderField: "Content-Length")
        let credential = "\(user):\(pass)"
        guard let credentialData = credential.data(using: .utf8) else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ошибка кодирования."])
        }
        request.setValue("Basic \(credentialData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (WebDAV)", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw NSError(domain: "WebDAVUpload", code: urlError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Превышено время ожидания ответа от сервера. Проверьте интернет или попробуйте позже."])
        } catch {
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет ответа сервера."])
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = webDAVErrorMessage(statusCode: http.statusCode, url: urlString, responseData: data)
            throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private func webDAVErrorMessage(statusCode: Int, url: String, responseData: Data?) -> String {
        let isYandex = url.lowercased().contains("yandex")
        let domainHint = isYandex ? " Если не работает — попробуйте другой URL: https://webdav.yandex.com вместо .ru или наоборот." : ""
        switch statusCode {
        case 401:
            if isYandex {
                return "Неверный логин или пароль. Для Яндекс.Диска: id.yandex.ru → Безопасность → Пароли приложений → создать пароль для «WebDAV-клиент для Яндекс Диска». Используйте только пароль приложения (не основной). Новый пароль действует через 2–3 часа.\(domainHint)"
            }
            return "Неверный логин или пароль. Проверьте настройки WebDAV."
        case 403:
            return "Доступ запрещён (403). Проверьте права и URL.\(domainHint)"
        case 404:
            return "Сервер не найден или путь неверный (404). Проверьте URL WebDAV.\(domainHint)"
        case 407:
            return "Требуется авторизация прокси. Настройте прокси в системе."
        case 409:
            return "Конфликт при загрузке (409). Возможно, файл уже существует."
        case 507:
            return "Недостаточно места на диске (507). Освободите место в облаке."
        default:
            if statusCode >= 500 {
                return "Ошибка сервера (\(statusCode)). Яндекс.Диск может быть перегружен. Попробуйте позже.\(domainHint)"
            }
            return "Ошибка загрузки WebDAV (\(statusCode)). Проверьте URL и доступ.\(domainHint)"
        }
    }
}
