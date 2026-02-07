import Foundation
import Sparkle

/// Общий контроллер Sparkle — должен жить всё время работы приложения,
/// иначе checkForUpdates прерывается при деаллокации.
enum SparkleUpdater {
    static let controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
