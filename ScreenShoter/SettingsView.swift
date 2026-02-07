import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var defaultSaveFolder: URL? = AppSettings.defaultSaveFolder
    @State private var screenshotFormat: ScreenshotFormat = AppSettings.screenshotFormat
    @State private var yandexOAuthToken: String = AppSettings.yandexOAuthToken
    @State private var oauthTokenInProgress = false
    @State private var showYandexCodeInput = false
    @State private var yandexVerificationCode = ""
    @State private var yandexCodeExchangeInProgress = false
    @State private var autoUpload: Bool = AppSettings.autoUploadToWebDAV
    @State private var wallpaperPath: String = AppSettings.wallpaperImagePath ?? ""
    @State private var useMacWallpaper: Bool = AppSettings.useMacWallpaper
    @State private var wallpaperPaddingPreset: AppSettings.WallpaperPaddingPreset = AppSettings.wallpaperPaddingPreset
    @State private var wallpaperPaddingVerticalPreset: AppSettings.WallpaperPaddingPreset = AppSettings.wallpaperPaddingVerticalPreset
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @State private var webdavTestInProgress = false
    @State private var webdavTestMessage: String?
    @State private var notificationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var scaleDownRetina: Bool = AppSettings.scaleDownRetina
    @State private var compressionLevel: CompressionLevel = AppSettings.compressionLevel
    @State private var shortcutWithEditingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutWithEditingKeyCode, modifiers: AppSettings.shortcutWithEditingModifiers)
    @State private var shortcutWithoutEditingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutWithoutEditingKeyCode, modifiers: AppSettings.shortcutWithoutEditingModifiers)
    @State private var useQuickOverlayAfterCapture: Bool = AppSettings.useQuickOverlayAfterCapture
    @State private var hideDesktopIconsBeforeCapture: Bool = AppSettings.hideDesktopIconsBeforeCapture
    @State private var showCrosshairForRegionCapture: Bool = AppSettings.showCrosshairForRegionCapture
    @State private var wallpaperPreset: WallpaperPreset? = AppSettings.wallpaperPreset

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(defaultSaveFolder?.path ?? String(localized: "settings.not_selected"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("settings.choose", action: chooseSaveFolder)
                }
                Picker("settings.format", selection: $screenshotFormat) {
                    ForEach(ScreenshotFormat.allCases) { Text($0.localizedLabel).tag($0) }
                }
                .onChange(of: screenshotFormat) { _, new in AppSettings.screenshotFormat = new }
                Picker("settings.compression", selection: $compressionLevel) {
                    ForEach(CompressionLevel.allCases) { Text($0.localizedLabel).tag($0) }
                }
                .onChange(of: compressionLevel) { _, new in AppSettings.compressionLevel = new }
                Toggle("settings.scale_retina", isOn: $scaleDownRetina)
                    .onChange(of: scaleDownRetina) { _, new in AppSettings.scaleDownRetina = new }
            } header: { Text("settings.section_save") }
            footer: { Text("settings.section_save.footer") }

            Section {
                Toggle("settings.quick_overlay", isOn: $useQuickOverlayAfterCapture)
                    .onChange(of: useQuickOverlayAfterCapture) { _, new in AppSettings.useQuickOverlayAfterCapture = new }
                Toggle("settings.hide_desktop_icons", isOn: $hideDesktopIconsBeforeCapture)
                    .onChange(of: hideDesktopIconsBeforeCapture) { _, new in AppSettings.hideDesktopIconsBeforeCapture = new }
                Toggle("settings.crosshair_region", isOn: $showCrosshairForRegionCapture)
                    .onChange(of: showCrosshairForRegionCapture) { _, new in AppSettings.showCrosshairForRegionCapture = new }
            } header: { Text("settings.section_capture") }
            footer: { Text("settings.section_capture.footer") }

            Section {
                Toggle("settings.launch_at_login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in
                        _ = LaunchAtLoginManager.setEnabled(new)
                    }
            } header: { Text("settings.section_autostart") }
            footer: { Text("settings.section_autostart.footer") }

            Section {
                HStack {
                    Text(statusTextForNotification)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if notificationStatus == .authorized || notificationStatus == .provisional {
                        Text("setup.allowed")
                            .foregroundStyle(.green)
                    } else {
                        Button("settings.allow_notifications") {
                            Task {
                                _ = await NotificationManager.shared.requestAuthorization()
                                await refreshNotificationStatus()
                            }
                        }
                        Button("settings.open_settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: { Text("settings.section_notifications") }
            footer: { Text("settings.section_notifications.footer") }

            Section {
                HStack {
                    Text("settings.shortcut_with_editing")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortcutWithEditingDisplay)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                    Button("settings.change") {
                        HotkeyManager.shared.recordShortcut { keyCode, modifiers in
                            AppSettings.shortcutWithEditingKeyCode = keyCode
                            AppSettings.shortcutWithEditingModifiers = modifiers
                            shortcutWithEditingDisplay = HotkeyManager.string(keyCode: keyCode, modifiers: modifiers)
                        }
                    }
                }
                HStack {
                    Text("settings.shortcut_without_editing")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortcutWithoutEditingDisplay)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                    Button("settings.change") {
                        HotkeyManager.shared.recordShortcut { keyCode, modifiers in
                            AppSettings.shortcutWithoutEditingKeyCode = keyCode
                            AppSettings.shortcutWithoutEditingModifiers = modifiers
                            shortcutWithoutEditingDisplay = HotkeyManager.string(keyCode: keyCode, modifiers: modifiers)
                        }
                    }
                }
            } header: { Text("settings.section_shortcuts") }
            footer: { Text("settings.section_shortcuts.footer") }

            Section {
                Toggle("settings.upload_after_save", isOn: $autoUpload)
                    .onChange(of: autoUpload) { _, new in AppSettings.autoUploadToWebDAV = new }

                VStack(alignment: .leading, spacing: 12) {
                    if YandexOAuthConfig.builtInClientID.isEmpty {
                        Text("settings.yandex_not_configured")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Link("settings.dev_instructions", destination: URL(string: "https://yandex.ru/dev/disk-api/doc/ru/concepts/quickstart")!)
                            .font(.caption)
                    } else if yandexOAuthToken.trimmingCharacters(in: .whitespaces).isEmpty {
                        if YandexOAuthConfig.builtInClientSecret.isEmpty {
                            Text("settings.client_secret_hint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(action: startOAuthTokenFlow) {
                            HStack {
                                Image(systemName: "link.badge.plus")
                                Text("settings.connect_yandex")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        Text("settings.connect_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if showYandexCodeInput {
                            HStack(spacing: 8) {
                                TextField("settings.code_from_page", text: $yandexVerificationCode)
                                    .textFieldStyle(.roundedBorder)
                                Button(yandexCodeExchangeInProgress ? String(localized: "settings.getting") : String(localized: "settings.get_token")) {
                                    exchangeYandexCodeForToken()
                                }
                                .disabled(yandexCodeExchangeInProgress || yandexVerificationCode.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("settings.yandex_connected")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("settings.disconnect") {
                                yandexOAuthToken = ""
                                AppSettings.yandexOAuthToken = ""
                            }
                            .buttonStyle(.borderless)
                        }
                        Button(webdavTestInProgress ? String(localized: "settings.testing") : String(localized: "settings.test_connection")) {
                            testYandexRESTConnection()
                        }
                        .disabled(webdavTestInProgress)
                    }
                    if let msg = webdavTestMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.lowercased().contains("success") || msg.lowercased().contains("успешно") || msg.lowercased().contains("получен") || msg.lowercased().contains("成功") ? Color.green : Color.orange)
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("settings.section_yandex") }
            footer: { Text("settings.section_yandex.footer") }

            Section {
                Picker("settings.wallpaper_preset", selection: $wallpaperPreset) {
                    Text("settings.none").tag(Optional<WallpaperPreset>.none)
                    ForEach(WallpaperPreset.allCases.filter { $0 != .none }) { preset in
                        Text(preset.localizedLabel).tag(Optional(preset))
                    }
                }
                .onChange(of: wallpaperPreset) { _, new in AppSettings.wallpaperPreset = new }
                Toggle("settings.use_mac_wallpaper", isOn: $useMacWallpaper)
                    .onChange(of: useMacWallpaper) { _, new in AppSettings.useMacWallpaper = new }
                Picker("settings.padding_h", selection: $wallpaperPaddingPreset) {
                    ForEach(AppSettings.WallpaperPaddingPreset.allCases) { preset in
                        Text(preset.localizedLabel).tag(preset)
                    }
                }
                .onChange(of: wallpaperPaddingPreset) { _, new in AppSettings.wallpaperPaddingPreset = new }
                Picker("settings.padding_v", selection: $wallpaperPaddingVerticalPreset) {
                    ForEach(AppSettings.WallpaperPaddingPreset.allCases) { preset in
                        Text(preset.localizedLabel).tag(preset)
                    }
                }
                .onChange(of: wallpaperPaddingVerticalPreset) { _, new in AppSettings.wallpaperPaddingVerticalPreset = new }
                if wallpaperPreset == nil, !useMacWallpaper {
                    HStack {
                        Text(wallpaperPath.isEmpty ? String(localized: "settings.not_selected") : (URL(fileURLWithPath: wallpaperPath).lastPathComponent))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("settings.choose", action: chooseWallpaper)
                        if !wallpaperPath.isEmpty {
                            Button("settings.delete") {
                                wallpaperPath = ""
                                AppSettings.wallpaperImagePath = nil
                            }
                        }
                    }
                }
            } header: { Text("settings.section_wallpaper") }
            footer: { Text("settings.section_wallpaper.footer") }

            Section {
                Button("settings.check_updates") {
                    SparkleUpdater.checkForUpdates()
                }
                Button("settings.contact_author") {
                    var components = URLComponents()
                    components.scheme = "mailto"
                    components.path = "work@gasoyan.ru"
                    components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "mail.subject"))]
                    if let url = components.url {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: { Text("settings.section_updates") }
            footer: { Text("settings.section_updates.footer") }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 700)
        .onAppear {
            defaultSaveFolder = AppSettings.defaultSaveFolder
            screenshotFormat = AppSettings.screenshotFormat
            scaleDownRetina = AppSettings.scaleDownRetina
            compressionLevel = AppSettings.compressionLevel
            yandexOAuthToken = AppSettings.yandexOAuthToken
            autoUpload = AppSettings.autoUploadToWebDAV
            wallpaperPath = AppSettings.wallpaperImagePath ?? ""
            useMacWallpaper = AppSettings.useMacWallpaper
            wallpaperPaddingPreset = AppSettings.wallpaperPaddingPreset
            wallpaperPaddingVerticalPreset = AppSettings.wallpaperPaddingVerticalPreset
            launchAtLogin = LaunchAtLoginManager.isEnabled
            webdavTestMessage = nil
            shortcutWithEditingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutWithEditingKeyCode, modifiers: AppSettings.shortcutWithEditingModifiers)
            shortcutWithoutEditingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutWithoutEditingKeyCode, modifiers: AppSettings.shortcutWithoutEditingModifiers)
            useQuickOverlayAfterCapture = AppSettings.useQuickOverlayAfterCapture
            hideDesktopIconsBeforeCapture = AppSettings.hideDesktopIconsBeforeCapture
            showCrosshairForRegionCapture = AppSettings.showCrosshairForRegionCapture
            wallpaperPreset = AppSettings.wallpaperPreset
            Task { await refreshNotificationStatus() }
        }
    }

    private var statusTextForNotification: String {
        switch notificationStatus {
        case .notDetermined: return String(localized: "settings.notification_not_requested")
        case .denied: return String(localized: "settings.notification_denied")
        case .authorized, .provisional: return String(localized: "settings.notification_enabled")
        }
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        await MainActor.run { notificationStatus = status }
    }

    private func startOAuthTokenFlow() {
        webdavTestMessage = nil
        guard let url = YandexOAuthConfig.authorizeURL else { return }
        NSWorkspace.shared.open(url)
        showYandexCodeInput = true
    }

    private func exchangeYandexCodeForToken() {
        let code = yandexVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        webdavTestMessage = nil
        yandexCodeExchangeInProgress = true
        Task {
            do {
                let token = try await YandexOAuthConfig.exchangeCodeForToken(code)
                await MainActor.run {
                    yandexOAuthToken = token
                    AppSettings.yandexOAuthToken = token
                    yandexVerificationCode = ""
                    showYandexCodeInput = false
                    yandexCodeExchangeInProgress = false
                    webdavTestMessage = String(localized: "settings.token_received")
                }
            } catch {
                await MainActor.run {
                    yandexCodeExchangeInProgress = false
                    webdavTestMessage = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
                }
            }
        }
    }

    private func testYandexRESTConnection() {
        AppSettings.yandexOAuthToken = yandexOAuthToken
        webdavTestMessage = nil
        webdavTestInProgress = true
        Task {
            do {
                try await WebDAVUploader.shared.testYandexRESTConnection(oauthToken: yandexOAuthToken.isEmpty ? nil : yandexOAuthToken)
                await MainActor.run {
                    webdavTestInProgress = false
                    webdavTestMessage = String(localized: "settings.connection_ok")
                }
            } catch {
                await MainActor.run {
                    webdavTestInProgress = false
                    let ns = error as NSError
                    let msg = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? error.localizedDescription
                    webdavTestMessage = msg
                }
            }
        }
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultSaveFolder
        panel.begin { response in
            if response == .OK, let url = panel.url {
                defaultSaveFolder = url
                AppSettings.defaultSaveFolder = url
            }
        }
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                wallpaperPath = url.path
                AppSettings.wallpaperImagePath = url.path
            }
        }
    }

}
