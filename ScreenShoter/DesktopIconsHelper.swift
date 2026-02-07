import Foundation
import AppKit

/// Временно скрывает/показывает иконки на рабочем столе (через defaults com.apple.finder CreateDesktop и перезапуск Finder).
enum DesktopIconsHelper {
    private static let domain = "com.apple.finder"
    private static let key = "CreateDesktop"

    /// Текущее состояние: true = иконки показываются, false = скрыты.
    static func areIconsVisible() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return true }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value != "false"
    }

    /// Установить видимость иконок рабочего стола. Требует перезапуска Finder.
    static func setIconsVisible(_ visible: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-bool", visible ? "true" : "false"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        let killFinder = Process()
        killFinder.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killFinder.arguments = ["Finder"]
        killFinder.standardOutput = FileHandle.nullDevice
        killFinder.standardError = FileHandle.nullDevice
        try? killFinder.run()
        killFinder.waitUntilExit()
    }

    /// Скрыть иконки перед съёмкой, затем вернуть прежнее состояние. Вызвать beforeCapture перед capture, afterCapture после.
    static func beforeCapture() -> Bool {
        guard areIconsVisible() else { return false }
        setIconsVisible(false)
        Thread.sleep(forTimeInterval: 0.8)
        return true
    }

    static func afterCapture(restore: Bool) {
        if restore {
            setIconsVisible(true)
        }
    }
}
