import Foundation
import Sparkle

/// Общий контроллер Sparkle — должен жить всё время работы приложения,
/// иначе checkForUpdates прерывается при деаллокации.
@MainActor
enum SparkleUpdater {
    private static let updaterDelegate = SparkleUpdaterDelegate()

    static let controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }()

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
