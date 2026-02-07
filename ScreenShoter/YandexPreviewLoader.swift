import Foundation
import AppKit

/// Загружает превью изображения с Яндекс.Диска (WebDAV URL с OAuth).
/// GET /path/file.png?preview&size=S — размер S = 150px по ширине.
final class YandexPreviewLoader {
    static let shared = YandexPreviewLoader()
    private let session: URLSession
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    /// Загружает превью. Возвращает nil, если URL не Yandex или нет OAuth-токена.
    func loadPreview(webdavURL: String?, size: String = "S") async -> NSImage? {
        let token = AppSettings.yandexOAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = webdavURL,
              !base.isEmpty,
              base.lowercased().contains("yandex"),
              !token.isEmpty else {
            return nil
        }
        guard var components = URLComponents(string: base) else { return nil }
        if components.queryItems == nil { components.queryItems = [] }
        components.queryItems?.removeAll { $0.name == "preview" || $0.name == "size" }
        components.queryItems?.append(contentsOf: [URLQueryItem(name: "preview", value: nil), URLQueryItem(name: "size", value: size)])
        guard let url = components.url else { return nil }
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        var request = URLRequest(url: url)
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("ScreenShoter/1.0 (Yandex)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
