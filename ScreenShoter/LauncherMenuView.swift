import SwiftUI

struct LauncherMenuView: View {
    @ObservedObject var appState: AppState
    @Binding var hasCheckedSetup: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = { AppState.current = appState }()
        VStack(spacing: 0) {
            Text("app.name")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if appState.trayUploadStatus != .idle {
                trayStatusBlock(appState: appState)
            }

            Divider()
                .opacity(0.4)
                .padding(.horizontal, 12)

            VStack(spacing: 4) {
                Button { capture(.full) } label: { Text("menu.capture.full").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.window) } label: { Text("menu.capture.window").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.region) } label: { Text("menu.capture.region").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button {
                    Task { await ScrollCaptureService.startScrollCapture(appState: appState) }
                } label: { Text("menu.capture.scroll").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()
                .opacity(0.4)
                .padding(.horizontal, 12)

            Text("menu.with_timer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            VStack(spacing: 4) {
                Button { capture(.full, delaySeconds: 3) } label: { Text("menu.capture.full.3s").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.full, delaySeconds: 5) } label: { Text("menu.capture.full.5s").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { capture(.full, delaySeconds: 10) } label: { Text("menu.capture.full.10s").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.bottom, 4)

            Divider()
                .opacity(0.4)
                .padding(.horizontal, 12)

            VStack(spacing: 4) {
                Text("menu.screen_recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                Button {
                    Task { @MainActor in RecordingStubService.showStub() }
                } label: { Text("menu.record_screen").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.bottom, 4)

            Divider()
                .opacity(0.4)
                .padding(.horizontal, 12)

            VStack(spacing: 4) {
                Button { openWindow(id: "history") } label: { Text("menu.upload_history").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { openWindow(id: "settings") } label: { Text("menu.settings").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button {
                    SparkleUpdater.checkForUpdates()
                } label: { Text("menu.check_updates").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button {
                    var components = URLComponents()
                    components.scheme = "mailto"
                    components.path = "work@gasoyan.ru"
                    components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "mail.subject"))]
                    if let url = components.url {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Text("menu.contact_author").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
                Button { NSApplication.shared.terminate(nil) } label: { Text("menu.quit").frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .padding(.bottom, 12)
        }
        .frame(width: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            _ = SparkleUpdater.controller
            if !hasCheckedSetup {
                hasCheckedSetup = true
                openWindow(id: "setup")
            }
            HotkeyManager.shared.setHandlers(
                withEditing: { Task { @MainActor in await Self.captureWithEditing(appState: appState, openWindow: openWindow) } },
                withoutEditing: { Task { @MainActor in await QuickCaptureService.shared.captureAndSave(appState: appState) } },
                recording: {
                    Task { @MainActor in RecordingStubService.showStub() }
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
                    Text("menu.uploading \(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
            case .success(let fileName, _):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("menu.uploaded \(fileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .onTapGesture { appState.trayUploadStatus = .idle }
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
