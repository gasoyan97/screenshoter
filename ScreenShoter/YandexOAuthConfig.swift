import Foundation

/// Конфиг OAuth для Яндекс.Диска (REST API). Credentials из YandexOAuthSecrets (генерируется скриптом из Secrets.xcconfig или env).
/// Redirect URI на oauth.yandex.ru нельзя менять — используем поток с кодом: пользователь копирует код со страницы, вставляет в приложение, мы обмениваем код на токен.
enum YandexOAuthConfig {
    static var builtInClientID: String { YandexOAuthSecrets.clientID }
    static var builtInClientSecret: String { YandexOAuthSecrets.clientSecret }

    /// Права для API Яндекс.Диска. Должны совпадать с «Запрашиваемые права» в консоли приложения (oauth.yandex.com).
    /// Только те, что включены у приложения: иначе invalid_scope.
    private static let diskScopes = "cloud_api:disk.write%20cloud_api:disk.app_folder"

    /// URL для авторизации (пользователь получает код на странице verification_code).
    static var authorizeURL: URL? {
        URL(string: "https://oauth.yandex.ru/authorize?response_type=code&client_id=\(builtInClientID)&force_confirm=yes&scope=\(diskScopes)")
    }

    /// Обменивает код подтверждения на OAuth-токен.
    static func exchangeCodeForToken(_ code: String) async throws -> String {
        let clientID = builtInClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = builtInClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw NSError(domain: "YandexOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Укажите Client ID и Client secret в YandexOAuthConfig."])
        }
        guard let url = URL(string: "https://oauth.yandex.ru/token") else {
            throw NSError(domain: "YandexOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный URL."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)&client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)&client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)"
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "YandexOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет ответа от сервера."])
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Ошибка \(http.statusCode)"
            throw NSError(domain: "YandexOAuth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить токен: \(msg)"])
        }
        struct TokenResponse: Decodable {
            let access_token: String
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return decoded.access_token
    }
}
