import Foundation
import os.log

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenShoter", category: "CloudUpload")

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
            return String(localized: "error.invalid_url")
        }
        let desc = error.localizedDescription
        if desc.lowercased().contains("unsupported url") {
            return String(localized: "error.invalid_url")
        }
        return desc
    }

    /// Папка на Яндекс.Диске, куда кладём скриншоты.
    private static let remoteFolderName = "ScreenShoter_mac"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Загрузка файла в Яндекс.Диск (REST API). Токен берётся из AppSettings.
    func upload(fileURL: URL) async throws -> WebDAVUploadResult {
        let token = AppSettings.yandexOAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Укажите OAuth-токен в настройках (Яндекс.Диск)."])
        }
        return try await uploadViaYandexREST(fileURL: fileURL, oauthToken: token)
    }

    // MARK: - Яндекс.Диск REST API (OAuth)

    private static let yandexCloudAPIBase = "https://cloud-api.yandex.net/v1/disk"
    private static let yandexWebDAVBase = "https://webdav.yandex.ru"

    private func uploadViaYandexREST(fileURL: URL, oauthToken: String) async throws -> WebDAVUploadResult {
        try await ensureRemoteFolderExists(oauthToken: oauthToken)
        let fileName = fileURL.lastPathComponent
        let diskPath = "/\(Self.remoteFolderName)/\(fileName)"
        var comp = URLComponents(string: "\(Self.yandexCloudAPIBase)/resources/upload")
        comp?.queryItems = [
            URLQueryItem(name: "path", value: diskPath),
            URLQueryItem(name: "overwrite", value: "true")
        ]
        guard let uploadURL = comp?.url else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный URL запроса загрузки."])
        }
        var getRequest = URLRequest(url: uploadURL)
        getRequest.httpMethod = "GET"
        getRequest.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        getRequest.setValue("ScreenShoter/1.0 (Yandex REST)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: getRequest)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет ответа от API Яндекс.Диска."])
        }
        guard http.statusCode == 200 else {
            let msg = yandexRestErrorMessage(statusCode: http.statusCode, responseData: data)
            throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        struct UploadLinkResponse: Decodable {
            let href: String
            let method: String?
        }
        let decoded = try JSONDecoder().decode(UploadLinkResponse.self, from: data)
        guard let putURL = URL(string: decoded.href) else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный URL для загрузки от API."])
        }
        var putRequest = URLRequest(url: putURL)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        putRequest.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        let (putData, putResponse) = try await uploadFromFile(request: putRequest, fileURL: fileURL)
        guard let putHttp = putResponse as? HTTPURLResponse else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет ответа при загрузке файла."])
        }
        guard putHttp.statusCode == 201 || putHttp.statusCode == 202 else {
            let msg = yandexRestErrorMessage(statusCode: putHttp.statusCode, responseData: putData)
            throw NSError(domain: "WebDAVUpload", code: putHttp.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let remoteURL = URL(string: "\(Self.yandexWebDAVBase)\(diskPath)")!
        var publicURL: String?
        let delays: [UInt64] = [0, 2, 4]
        for delaySec in delays {
            if delaySec > 0 { try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000) }
            publicURL = await publishFileOnYandexWebDAVWithOAuth(remoteURL: remoteURL, oauthToken: oauthToken)
            if publicURL != nil { break }
        }
        return WebDAVUploadResult(fileName: fileName, fileURL: remoteURL, publicURL: publicURL)
    }

    private func publishFileOnYandexWebDAVWithOAuth(remoteURL: URL, oauthToken: String) async -> String? {
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
        request.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (WebDAV)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 207 else { return nil }
            return parsePublicURLFromMultistatusResponse(data)
        } catch {
            log.error("PROPPATCH OAuth ошибка: \(error.localizedDescription)")
            return nil
        }
    }

    private func yandexRestErrorMessage(statusCode: Int, responseData: Data?) -> String {
        if let data = responseData,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desc = json["description"] as? String, !desc.isEmpty {
            return desc
        }
        switch statusCode {
        case 401: return "Неверный или истёкший OAuth-токен. Получите новый: id.yandex.ru → Безопасность → Внешние приложения."
        case 403: return "Доступ запрещён или закончилось место на Диске (403)."
        case 404: return "Ресурс не найден (404). Проверьте путь."
        case 409: return "Конфликт: файл уже существует (409)."
        case 413: return "Файл слишком большой для загрузки на Диск."
        case 423: return "Загрузка временно недоступна (лимит трафика или техработы)."
        case 429: return "Слишком много запросов. Подождите и попробуйте снова."
        case 507: return "Недостаточно места на Яндекс.Диске."
        default:
            if statusCode >= 500 { return "Ошибка сервера Яндекс.Диска (\(statusCode)). Попробуйте позже." }
            return "Ошибка API Яндекс.Диска (\(statusCode))."
        }
    }

    /// Загрузка из файла стримингом (без загрузки всего файла в память).
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

    /// Достаёт public_url (yadi.sk) из ответа 207 Multi-Status (XML).
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

    /// Создаёт папку ScreenShoter_mac на Диске, если её ещё нет (REST API).
    private func ensureRemoteFolderExists(oauthToken: String) async throws {
        var comp = URLComponents(string: "\(Self.yandexCloudAPIBase)/resources")
        comp?.queryItems = [URLQueryItem(name: "path", value: "/\(Self.remoteFolderName)")]
        guard let url = comp?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("OAuth \(oauthToken)", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (Yandex REST)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        // 201 — создана, 200 — уже есть (по доке), 409 — папка уже существует
        if http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 409 { return }
        let msg = yandexRestErrorMessage(statusCode: http.statusCode, responseData: data)
        throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    /// Проверка подключения к Яндекс.Диску REST API. Создаёт папку при необходимости, затем запрашивает URL загрузки.
    func testYandexRESTConnection(oauthToken: String? = nil) async throws {
        let token = (oauthToken ?? AppSettings.yandexOAuthToken).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Укажите OAuth-токен."])
        }
        try await ensureRemoteFolderExists(oauthToken: token)
        let testPath = "/\(Self.remoteFolderName)/.connection_check"
        var comp = URLComponents(string: "\(Self.yandexCloudAPIBase)/resources/upload")
        comp?.queryItems = [URLQueryItem(name: "path", value: testPath), URLQueryItem(name: "overwrite", value: "true")]
        guard let url = comp?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (Yandex REST)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "WebDAVUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет ответа от API."])
        }
        guard http.statusCode == 200 else {
            let msg = yandexRestErrorMessage(statusCode: http.statusCode, responseData: data)
            throw NSError(domain: "WebDAVUpload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
