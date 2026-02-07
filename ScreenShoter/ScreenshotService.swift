import Foundation
import AppKit

enum CaptureMode: String {
    case full
    case window
    case region
}

enum ScreenshotError: Error {
    case cancelled
    case failed
}

final class ScreenshotService {
    static let shared = ScreenshotService()
    private let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("scrinsjater")

    private init() {
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func capture(mode: CaptureMode) async throws -> NSImage {
        let path = tempDir.appendingPathComponent("screenshot_\(Date().timeIntervalSince1970).png")

        var restoreDesktopIcons = false
        if AppSettings.hideDesktopIconsBeforeCapture, mode == .full || mode == .region {
            restoreDesktopIcons = DesktopIconsHelper.beforeCapture()
        }

        defer {
            if restoreDesktopIcons {
                DesktopIconsHelper.afterCapture(restore: true)
            }
        }

        var args = ["-x"]
        switch mode {
        case .full:
            args.append("-m")
        case .window:
            args.append("-w")
        case .region:
            if AppSettings.showCrosshairForRegionCapture {
                guard let rect = await showRegionSelector() else { throw ScreenshotError.cancelled }
                let x = Int(rect.origin.x)
                let y = Int(rect.origin.y)
                let w = Int(rect.width)
                let h = Int(rect.height)
                args.append("-R")
                args.append("\(x),\(y),\(w),\(h)")
            } else {
                args.append("-i")
            }
        }
        args.append(path.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { throw ScreenshotError.cancelled }

        let data = try Data(contentsOf: path)
        try? FileManager.default.removeItem(at: path)

        guard let image = NSImage(data: data) else { throw ScreenshotError.failed }
        return image
    }
}
