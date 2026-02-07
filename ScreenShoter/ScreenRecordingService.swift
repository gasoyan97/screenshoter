import Foundation
import AppKit
import AVFoundation
import ScreenCaptureKit
import os.log

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenShoter", category: "ScreenRecording")

enum ScreenRecordingError: Error {
    case noDisplay
    case noShareableContent
    case writerSetupFailed
    case streamStartFailed
}

/// Обёртка для передачи AVAssetWriter/Input в @Sendable closure (они не Sendable).
private final class WriterContext: @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    init(writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.input = input
    }
}

/// Запись экрана в видео (MP4/MOV) через ScreenCaptureKit. macOS 12.3+.
@MainActor
final class ScreenRecordingService: NSObject, ObservableObject {
    static let shared = ScreenRecordingService()

    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private let videoQueue = DispatchQueue(label: "ScreenShoter.videoWrite")
    private var firstSampleTime: CMTime = .zero
    private var lastSampleBuffer: CMSampleBuffer?
    private var outputURL: URL?
    private var streamOutput: StreamOutput?

    /// URL последней записанной записи (для экспорта в GIF).
    private(set) var lastRecordedVideoURL: URL?

    private override init() {
        super.init()
    }

    /// Начинает запись всего экрана (основной дисплей).
    func startRecording() async throws {
        guard !isRecording else { return }
        errorMessage = nil

        let content: SCShareableContent
        do {
            content = try await withCheckedThrowingContinuation { continuation in
                SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let content = content {
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(throwing: ScreenRecordingError.noShareableContent)
                    }
                }
            }
        } catch {
            errorMessage = "Нет доступа к экрану. Включите «Запись экрана» в Системных настройках → Конфиденциальность и безопасность."
            throw error
        }

        guard let display = content.displays.first else {
            errorMessage = "Дисплей не найден"
            throw ScreenRecordingError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        try await startCapture(filter: filter, display: display)
    }

    /// Начинает запись с выбранным контентом (дисплей или окно).
    func startRecording(display: SCDisplay) async throws {
        guard !isRecording else { return }
        errorMessage = nil
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        try await startCapture(filter: filter, display: display)
    }

    func startRecording(window: SCWindow) async throws {
        guard !isRecording else { return }
        errorMessage = nil
        let filter = SCContentFilter(desktopIndependentWindow: window)
        try await startCapture(filter: filter, display: nil)
    }

    private func startCapture(filter: SCContentFilter, display: SCDisplay?) async throws {
        let config = SCStreamConfiguration()
        let width: Int
        let height: Int
        if let display = display {
            let size = display.frame.size
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            width = Int(size.width * scale)
            height = Int(size.height * scale)
        } else {
            width = 1920
            height = 1080
        }
        config.width = min(width, 4096)
        config.height = min(height, 2304)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5

        let name = "recording_\(ISO8601DateFormatter().string(from: Date()).prefix(19).replacingOccurrences(of: ":", with: "-"))"
        let folder = AppSettings.videoSaveFolder ?? AppSettings.defaultSaveFolder ?? FileManager.default.temporaryDirectory
        let url = folder.appendingPathComponent("\(name).mov")
        outputURL = url

        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        do {
            writer = try AVAssetWriter(url: url, fileType: .mov)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            assetWriter = writer
            videoInput = input
        } catch {
            self.errorMessage = error.localizedDescription
            throw ScreenRecordingError.writerSetupFailed
        }

        let streamOut = StreamOutput(
            videoInput: input,
            assetWriter: writer,
            queue: videoQueue,
            onFirstSample: { [weak self] time in
                Task { @MainActor in self?.firstSampleTime = time }
            },
            onLastSample: { [weak self] buffer in
                Task { @MainActor in self?.lastSampleBuffer = buffer }
            }
        )
        streamOutput = streamOut

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(streamOut, type: .screen, sampleHandlerQueue: videoQueue)
        self.stream = stream
        try await stream.startCapture()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        isRecording = true
    }

    /// Останавливает запись, сохраняет файл в папку и при включённой опции загружает в WebDAV.
    func stopRecording(appState: AppState) async {
        guard isRecording, let stream = stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            // Игнорируем ошибку остановки — всё равно завершаем запись
        }
        self.stream = nil

        guard let writer = assetWriter, let input = videoInput, let url = outputURL else {
            isRecording = false
            return
        }

        let lastTime = streamOutput?.lastSampleBuffer?.presentationTimeStamp ?? .zero
        let firstTime = streamOutput?.firstSampleTime ?? .zero
        let endTime = lastTime - firstTime
        let ctx = WriterContext(writer: writer, input: input)
        videoQueue.async { [weak self] in
            guard let self = self else { return }
            ctx.input.markAsFinished()
            ctx.writer.endSession(atSourceTime: endTime)
            ctx.writer.finishWriting {
                Task { @MainActor in
                    self.finishRecording(url: url, appState: appState)
                }
            }
        }
    }

    private func finishRecording(url: URL, appState: AppState) {
        lastRecordedVideoURL = url
        assetWriter = nil
        videoInput = nil
        streamOutput = nil
        outputURL = nil
        firstSampleTime = .zero
        lastSampleBuffer = nil
        isRecording = false

        let name = url.lastPathComponent
        let canUpload = !AppSettings.webdavURL.isEmpty && !AppSettings.webdavUsername.isEmpty && !AppSettings.webdavPassword.isEmpty
        if AppSettings.autoUploadVideoToWebDAV, canUpload {
            Task { @MainActor in
                appState.setTrayUploadStatus(.uploading(fileName: name))
                do {
                    let result = try await WebDAVUploader.shared.upload(
                        fileURL: url,
                        username: AppSettings.webdavUsername,
                        password: AppSettings.webdavPassword
                    )
                    UploadHistory.shared.add(result)
                    let link = result.publicURL ?? result.fileURL.absoluteString
                    appState.setTrayUploadStatus(.success(fileName: result.fileName, link: link))
                    NotificationManager.shared.showUploadSuccess(fileName: result.fileName, publicURL: link)
                } catch {
                    appState.setTrayUploadStatus(.failed(message: WebDAVUploader.friendlyUploadErrorMessage(error)))
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    let videoInput: AVAssetWriterInput
    let assetWriter: AVAssetWriter
    let queue: DispatchQueue
    let onFirstSample: (CMTime) -> Void
    let onLastSample: (CMSampleBuffer?) -> Void

    var firstSampleTime: CMTime = .zero
    var lastSampleBuffer: CMSampleBuffer?

    init(
        videoInput: AVAssetWriterInput,
        assetWriter: AVAssetWriter,
        queue: DispatchQueue,
        onFirstSample: @escaping (CMTime) -> Void,
        onLastSample: @escaping (CMSampleBuffer?) -> Void
    ) {
        self.videoInput = videoInput
        self.assetWriter = assetWriter
        self.queue = queue
        self.onFirstSample = onFirstSample
        self.onLastSample = onLastSample
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        if firstSampleTime == .zero {
            firstSampleTime = sampleBuffer.presentationTimeStamp
            onFirstSample(firstSampleTime)
        }
        let offset = sampleBuffer.presentationTimeStamp - firstSampleTime
        var timing = CMSampleTimingInfo(
            duration: sampleBuffer.duration,
            presentationTimeStamp: offset,
            decodeTimeStamp: sampleBuffer.decodeTimeStamp
        )
        var retimed: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimed
        )
        guard let buf = retimed, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(buf)
        lastSampleBuffer = buf
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onLastSample(lastSampleBuffer)
    }
}
