import SwiftUI

struct LauncherMenuView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Text("Scrinsjater")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            Button("Вся область экрана") { capture(.full) }
            Button("Окно (с тенью)") { capture(.window) }
            Button("Выбранная область") { capture(.region) }

            Divider()

            Button("Настройки") {
                openWindow(id: "settings")
            }

            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 220)
        .padding(.vertical, 8)
        .buttonStyle(.plain)
    }

    private func capture(_ mode: CaptureMode) {
        NSApp.hide(nil)
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            do {
                let image = try await ScreenshotService.shared.capture(mode: mode)
                await MainActor.run {
                    appState.capturedImage = image
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "annotation")
                }
            } catch {
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
