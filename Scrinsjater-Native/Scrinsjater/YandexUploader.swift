import Foundation

final class YandexUploader {
    static let shared = YandexUploader()

    private init() {}

    func upload(fileURL: URL, token: String) async throws -> URL {
        let fileName = fileURL.lastPathComponent
        let remotePath = "/Scrinsjater/\(fileName)"
        let encoded = remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remotePath

        var components = URLComponents(string: "https://cloud-api.yandex.net/v1/disk/resources/upload")!
        components.queryItems = [URLQueryItem(name: "path", value: remotePath), URLQueryItem(name: "overwrite", value: "true")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(as: data) as? [String: Any],
               let msg = json["message"] as? String ?? json["description"] as? String {
                throw NSError(domain: "YandexUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw NSError(domain: "YandexUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get upload URL"])
        }

        struct UploadResponse: Decodable { let href: String }
        let uploadResp = try JSONDecoder().decode(UploadResponse.self, from: data)

        var putRequest = URLRequest(url: URL(string: uploadResp.href)!)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("image/png", forHTTPHeaderField: "Content-Type")
        putRequest.httpBody = try Data(contentsOf: fileURL)

        let (_, putResponse) = try await URLSession.shared.data(for: putRequest)
        guard let putHttp = putResponse as? HTTPURLResponse, (200...299).contains(putHttp.statusCode) else {
            throw NSError(domain: "YandexUpload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed"])
        }

        return URL(string: "https://disk.yandex.ru/client/disk/Scrinsjater")!
    }
}
