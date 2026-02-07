import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            if enabled {
                try? SMAppService.mainApp.register()
                return SMAppService.mainApp.status == .enabled
            } else {
                try? SMAppService.mainApp.unregister()
                return true
            }
        }
        return false
    }
}
