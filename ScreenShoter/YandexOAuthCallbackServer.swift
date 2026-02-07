import Foundation
import Network

/// Локальный HTTP-сервер на localhost:8765 для приёма OAuth-токена после редиректа от Яндекса.
/// Запускается по кнопке «Получить OAuth-токен», открывает браузер; после авторизации Яндекс редиректит на /callback#access_token=...,
/// мы отдаём HTML, который перенаправляет на /save_token?token=..., получаем токен и вызываем onTokenReceived.
final class YandexOAuthCallbackServer {
    static let port: UInt16 = 8765
    static let redirectURI = "http://localhost:\(port)/callback"

    private var listener: NWListener?
    private var onTokenReceived: ((String) -> Void)?
    private var activeConnection: NWConnection?

    func start(onTokenReceived: @escaping (String) -> Void) {
        self.onTokenReceived = onTokenReceived
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let listener = try? NWListener(using: params, on: port) else {
            DispatchQueue.main.async { onTokenReceived("") } // ошибка — не удалось занять порт
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.start(queue: .main)
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        activeConnection?.cancel()
        activeConnection = connection
        connection.start(queue: .main)
        receiveRequest(connection: connection)
    }

    private func receiveRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, let request = String(data: data, encoding: .utf8) {
                self.processRequest(request, connection: connection)
            } else {
                self.sendResponse(connection: connection, body: self.errorHTML("Нет данных"))
            }
        }
    }

    private func processRequest(_ request: String, connection: NWConnection) {
        let firstLine = request.split(separator: "\r\n").first ?? Substring(request.split(separator: "\n").first ?? "")
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, body: errorHTML("Неверный запрос"))
            return
        }
        let pathAndQuery = String(parts[1])
        let path: String
        let query: String?
        if let q = pathAndQuery.firstIndex(of: "?") {
            path = String(pathAndQuery[..<q])
            query = String(pathAndQuery[pathAndQuery.index(after: q)...])
        } else {
            path = pathAndQuery
            query = nil
        }

        if path == "/callback" {
            let html = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>ScreenShoter</title></head><body><p>Обработка…</p><script>
            var h = window.location.hash.substring(1);
            var p = new URLSearchParams(h);
            var t = p.get('access_token');
            if (t) window.location.href = 'http://localhost:\(Self.port)/save_token?token=' + encodeURIComponent(t);
            else document.body.innerHTML = '<p>Токен не найден. Закройте вкладку.</p>';
            </script></body></html>
            """
            sendResponse(connection: connection, body: html)
        } else if path == "/save_token", let query = query {
            let params = query.split(separator: "&")
            var token: String?
            for p in params {
                let kv = p.split(separator: "=", maxSplits: 1)
                if kv.count == 2, String(kv[0]) == "token" {
                    token = String(kv[1]).removingPercentEncoding
                    break
                }
            }
            if let t = token, !t.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onTokenReceived?(t)
                    self?.stop()
                }
            }
            let html = """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>ScreenShoter</title></head><body>
            <p style="font-family:system-ui;padding:20px;">Токен получен. Можно закрыть эту вкладку и вернуться в приложение.</p>
            </body></html>
            """
            sendResponse(connection: connection, body: html)
        } else {
            sendResponse(connection: connection, body: errorHTML("Неизвестный путь"))
        }
    }

    private func sendResponse(connection: NWConnection, body: String) {
        let data = body.data(using: .utf8)!
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        let response = (header + body).data(using: .utf8)!
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.activeConnection = nil
        })
    }

    private func errorHTML(_ message: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body><p>\(message)</p></body></html>
        """
    }
}
