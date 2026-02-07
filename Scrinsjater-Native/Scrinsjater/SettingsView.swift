import SwiftUI

struct SettingsView: View {
    @AppStorage("yandexToken") private var yandexToken = ""

    var body: some View {
        Form {
            Section {
                SecureField("OAuth токен", text: $yandexToken)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Яндекс.Диск")
            } footer: {
                Text("Получите токен: oauth.yandex.ru → создать приложение → права на Яндекс.Диск")
            }

            Button("Открыть OAuth Яндекса") {
                NSWorkspace.shared.open(URL(string: "https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 200)
    }
}
