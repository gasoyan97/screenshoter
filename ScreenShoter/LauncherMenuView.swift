import SwiftUI

struct LauncherMenuView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var recordingService = ScreenRecordingService.shared
    @Binding var hasCheckedSetup: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = { AppState.current = appState }()
        VStack(spacing: 0) {
            Text("ScreenShoter")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if appState.trayUploadStatus != .idle {
                trayStatusBlock(appState: appState)
            }

            Divider()
                .opacity(0.5)
                .padding(.horizontal, 12)

            VStack(spacing: 4) {
                Button { capture(.full) } label: { Text("Вся область экрана").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.window) } label: { Text("Окно (с тенью)").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.region) } label: { Text("Выбранная область").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button {
                    Task { await ScrollCaptureService.startScrollCapture(appState: appState) }
                } label: { Text("Прокручиваемая область").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .opacity(0.5)
                .padding(.horizontal, 12)

            Text("С таймером")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            VStack(spacing: 4) {
                Button { capture(.full, delaySeconds: 3) } label: { Text("Вся область (3 с)").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.full, delaySeconds: 5) } label: { Text("Вся область (5 с)").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.full, delaySeconds: 10) } label: { Text("Вся область (10 с)").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .padding(.bottom, 4)

            Divider()
                .opacity(0.5)
                .padding(.horizontal, 12)

            if recordingService.isRecording {
                Button {
                    Task { await recordingService.stopRecording(appState: appState) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                        Text("Остановить запись")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    Text("Запись экрана")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    Button {
                        Task {
                            do {
                                try await recordingService.startRecording()
                            } catch {
                                await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
                            }
                        }
                    } label: { Text("Записать экран").frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(GlassButtonStyle())
                    if recordingService.lastRecordedVideoURL != nil {
                        Button {
                            Task { await Self.exportLastRecordingAsGIF(appState: appState) }
                        } label: { Text("Экспорт последней записи в GIF").frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .padding(.bottom, 4)
            }

            Divider()
                .opacity(0.5)
                .padding(.horizontal, 12)

            VStack(spacing: 4) {
                Button { openWindow(id: "history") } label: { Text("История загрузок").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { openWindow(id: "settings") } label: { Text("Настройки").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button {
                    SparkleUpdater.checkForUpdates()
                } label: { Text("Проверить обновления…").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button {
                    var components = URLComponents()
                    components.scheme = "mailto"
                    components.path = "work@gasoyan.ru"
                    components.queryItems = [URLQueryItem(name: "subject", value: "есть идея по приложению")]
                    if let url = components.url {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Text("Написать автору").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { NSApplication.shared.terminate(nil) } label: { Text("Выход").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.bottom, 16)
        }
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            if !hasCheckedSetup {
                hasCheckedSetup = true
                openWindow(id: "setup")
            }
            HotkeyManager.shared.setHandlers(
                withEditing: { Task { @MainActor in await Self.captureWithEditing(appState: appState, openWindow: openWindow) } },
                withoutEditing: { Task { @MainActor in await QuickCaptureService.shared.captureAndSave(appState: appState) } },
                recording: {
                    Task { @MainActor in
                        if ScreenRecordingService.shared.isRecording {
                            await ScreenRecordingService.shared.stopRecording(appState: appState)
                        } else {
                            try? await ScreenRecordingService.shared.startRecording()
                        }
                    }
                }
            )
            HotkeyManager.shared.start()
        }
    }

    @ViewBuilder
    private func trayStatusBlock(appState: AppState) -> some View {
        Group {
            switch appState.trayUploadStatus {
            case .idle:
                EmptyView()
            case .uploading(let fileName):
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Загрузка \(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
            case .success(let fileName, _):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Загружено: \(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .onTapGesture { appState.trayUploadStatus = .idle }
            case .failed(let message):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .onTapGesture { appState.trayUploadStatus = .idle }
            }
        }
    }

    /// Экспорт последней записи в GIF и уведомление пользователя.
    private static func exportLastRecordingAsGIF(appState: AppState) async {
        guard let url = ScreenRecordingService.shared.lastRecordedVideoURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let gifURL = await GifExportService.exportVideoToGIF(videoURL: url) {
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
                NSWorkspace.shared.activateFileViewerSelecting([gifURL])
            }
        }
    }

    /// Вызывается по шорткату: скриншот всего экрана и открытие окна аннотаций.
    private static func captureWithEditing(appState: AppState, openWindow: OpenWindowAction) async {
        NSApp.hide(nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard let image = try? await ScreenshotService.shared.capture(mode: .full) else {
            await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
            return
        }
        await MainActor.run {
            appState.capturedImage = image
            appState.annotationImageId = UUID()
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "annotation")
        }
    }

    private func capture(_ mode: CaptureMode, delaySeconds: Int = 0) {
        NSApp.hide(nil)
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
            do {
                let image = try await ScreenshotService.shared.capture(mode: mode)
                await MainActor.run {
                    appState.capturedImage = image
                    appState.annotationImageId = UUID()
                    NSApp.activate(ignoringOtherApps: true)
                    if AppSettings.useQuickOverlayAfterCapture {
                        openWindow(id: "quickOverlay")
                    } else {
                        openWindow(id: "annotation")
                    }
                }
            } catch {
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
