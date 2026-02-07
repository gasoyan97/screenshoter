import Foundation

struct UploadRecord: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let fileURL: String
    let date: Date
    /// WebDAV URL для превью Яндекс.Диска (GET ?preview&size=S). nil для старых записей.
    let webdavURL: String?

    init(id: UUID = UUID(), fileName: String, fileURL: String, date: Date = Date(), webdavURL: String? = nil) {
        self.id = id
        self.fileName = fileName
        self.fileURL = fileURL
        self.date = date
        self.webdavURL = webdavURL
    }
}

final class UploadHistory {
    static let shared = UploadHistory()
    private let key = "uploadHistory"

    private init() {}

    private var records: [UploadRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([UploadRecord].self, from: data) else { return [] }
            return decoded.sorted { $0.date > $1.date }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    func add(_ record: UploadRecord) {
        var list = records
        list.insert(record, at: 0)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(fileName: String, fileURL: URL) {
        add(UploadRecord(fileName: fileName, fileURL: fileURL.absoluteString))
    }

    func add(_ result: WebDAVUploadResult) {
        let urlString = result.publicURL ?? result.fileURL.absoluteString
        add(UploadRecord(fileName: result.fileName, fileURL: urlString, webdavURL: result.fileURL.absoluteString))
    }

    func list() -> [UploadRecord] {
        records
    }
}
