import Foundation
import AppKit
@preconcurrency import Vision

/// Распознавание текста с изображения (OCR) через Vision. Копирование в буфер обмена.
enum OCRService {
    /// Распознаёт текст на изображении и возвращает объединённую строку или nil при ошибке.
    static func recognizeText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let strings = observations.compactMap { obs in obs.topCandidates(1).first?.string }
                continuation.resume(returning: strings.isEmpty ? nil : strings.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Распознаёт текст и копирует в буфер обмена. Возвращает true, если текст был распознан и скопирован.
    @MainActor
    static func recognizeAndCopyToClipboard(from image: NSImage) async -> Bool {
        guard let text = await recognizeText(from: image), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }
}
