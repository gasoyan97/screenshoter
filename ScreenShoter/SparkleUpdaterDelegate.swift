import Foundation
import Sparkle

/// Перед установкой обновления сбрасываем разрешение «Запись экрана» через tccutil.
/// После обновления macOS покажет запрос при первом захвате области.
@MainActor
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        resetScreenCapturePermission()
    }

    private func resetScreenCapturePermission() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleId]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // tccutil может не сработать (например, нужен sudo) — не блокируем обновление
        }
    }
}
