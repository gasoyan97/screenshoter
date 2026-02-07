import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage

/// Экспорт видео (MOV/MP4) в анимированный GIF через AVAssetImageGenerator и ImageIO.
enum GifExportService {
    /// Максимальное число кадров для GIF (чтобы не раздувать размер).
    static let maxFrames = 120
    /// Целевой FPS для GIF.
    static let targetFPS: Double = 10
    /// Задержка между кадрами в секундах.
    static let frameDelay: Double = 1.0 / targetFPS

    /// Конвертирует видео по URL в GIF и сохраняет рядом с исходным файлом (то же имя с расширением .gif).
    /// Возвращает URL созданного GIF или nil при ошибке.
    static func exportVideoToGIF(videoURL: URL) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let duration = asset.duration
        let totalSeconds = CMTimeGetSeconds(duration)
        let frameCount = min(maxFrames, max(1, Int(totalSeconds * targetFPS)))
        guard frameCount > 0 else { return nil }

        let gifURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        guard let destination = CGImageDestinationCreateWithURL(
            gifURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else { return nil }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        let timeStep = totalSeconds / Double(frameCount)
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) * timeStep, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            } catch {
                break
            }
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return gifURL
    }
}
