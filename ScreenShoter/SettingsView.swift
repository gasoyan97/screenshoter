import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var defaultSaveFolder: URL? = AppSettings.defaultSaveFolder
    @State private var screenshotFormat: ScreenshotFormat = AppSettings.screenshotFormat
    @State private var webdavURL: String = AppSettings.webdavURL
    @State private var webdavUsername: String = AppSettings.webdavUsername
    @State private var webdavPassword: String = AppSettings.webdavPassword
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
    @State private var shortcutRecordingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutRecordingKeyCode, modifiers: AppSettings.shortcutRecordingModifiers)
    @State private var useQuickOverlayAfterCapture: Bool = AppSettings.useQuickOverlayAfterCapture
    @State private var videoSaveFolder: URL? = AppSettings.videoSaveFolder
    @State private var autoUploadVideo: Bool = AppSettings.autoUploadVideoToWebDAV
    @State private var hideDesktopIconsBeforeCapture: Bool = AppSettings.hideDesktopIconsBeforeCapture
    @State private var showCrosshairForRegionCapture: Bool = AppSettings.showCrosshairForRegionCapture
    @State private var wallpaperPreset: WallpaperPreset? = AppSettings.wallpaperPreset

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(defaultSaveFolder?.path ?? "Не выбрана")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Выбрать…", action: chooseSaveFolder)
                }
                Picker("Формат файла", selection: $screenshotFormat) {
                    ForEach(ScreenshotFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: screenshotFormat) { _, new in AppSettings.screenshotFormat = new }
                Picker("Сжатие изображения", selection: $compressionLevel) {
                    ForEach(CompressionLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: compressionLevel) { _, new in AppSettings.compressionLevel = new }
                Toggle("Уменьшать Retina (2x → 1x)", isOn: $scaleDownRetina)
                    .onChange(of: scaleDownRetina) { _, new in AppSettings.scaleDownRetina = new }
            } header: { Text("Сохранение") }
            footer: { Text("Папка по умолчанию подставляется в диалог сохранения. Формат — PNG или JPEG. Сжатие влияет на JPEG: нет = max качество, среднее = баланс, сильное = меньший размер. «Уменьшать Retina» даёт меньший размер, как в CleanShot.") }

            Section {
                Toggle("После съёмки: быстрый оверлей", isOn: $useQuickOverlayAfterCapture)
                    .onChange(of: useQuickOverlayAfterCapture) { _, new in AppSettings.useQuickOverlayAfterCapture = new }
                Toggle("Скрывать иконки рабочего стола при съёмке", isOn: $hideDesktopIconsBeforeCapture)
                    .onChange(of: hideDesktopIconsBeforeCapture) { _, new in AppSettings.hideDesktopIconsBeforeCapture = new }
                Toggle("Режим прицела при выборе области", isOn: $showCrosshairForRegionCapture)
                    .onChange(of: showCrosshairForRegionCapture) { _, new in AppSettings.showCrosshairForRegionCapture = new }
            } header: { Text("Съёмка") }
            footer: { Text("Если включено, после съёмки показывается компактная панель «Сохранить / Копировать / Загрузить / Редактировать» вместо полного окна аннотаций. «Скрывать иконки» временно скрывает иконки на рабочем столе. «Режим прицела» — при выборе области показывается прицел по центру и выделение мышью вместо системного выбора.") }

            Section {
                HStack {
                    Text(videoSaveFolder?.path ?? "Как у скриншотов")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Выбрать…", action: chooseVideoSaveFolder)
                    if videoSaveFolder != nil {
                        Button("Сбросить") {
                            videoSaveFolder = nil
                            AppSettings.videoSaveFolder = nil
                        }
                    }
                }
                Toggle("Загружать видео в облако после записи", isOn: $autoUploadVideo)
                    .onChange(of: autoUploadVideo) { _, new in AppSettings.autoUploadVideoToWebDAV = new }
            } header: { Text("Запись экрана") }
            footer: { Text("Папка для сохранения видео. Если не выбрана, используется папка для скриншотов.") }

            Section {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in
                        _ = LaunchAtLoginManager.setEnabled(new)
                    }
            } header: { Text("Автозапуск") }
            footer: { Text("ScreenShoter будет появляться в меню-баре при каждой загрузке macOS.") }

            Section {
                HStack {
                    Text(statusTextForNotification)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if notificationStatus == .authorized || notificationStatus == .provisional {
                        Text("Разрешено")
                            .foregroundStyle(.green)
                    } else {
                        Button("Разрешить уведомления") {
                            Task {
                                _ = await NotificationManager.shared.requestAuthorization()
                                await refreshNotificationStatus()
                            }
                        }
                        Button("Открыть настройки") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: { Text("Уведомления") }
            footer: { Text("Уведомление показывается после загрузки скриншота в облако (WebDAV).") }

            Section {
                HStack {
                    Text("Скриншот с редактированием")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortcutWithEditingDisplay)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                    Button("Изменить") {
                        HotkeyManager.shared.recordShortcut { keyCode, modifiers in
                            AppSettings.shortcutWithEditingKeyCode = keyCode
                            AppSettings.shortcutWithEditingModifiers = modifiers
                            shortcutWithEditingDisplay = HotkeyManager.string(keyCode: keyCode, modifiers: modifiers)
                        }
                    }
                }
                HStack {
                    Text("Скриншот без редактирования")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortcutWithoutEditingDisplay)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                    Button("Изменить") {
                        HotkeyManager.shared.recordShortcut { keyCode, modifiers in
                            AppSettings.shortcutWithoutEditingKeyCode = keyCode
                            AppSettings.shortcutWithoutEditingModifiers = modifiers
                            shortcutWithoutEditingDisplay = HotkeyManager.string(keyCode: keyCode, modifiers: modifiers)
                        }
                    }
                }
                HStack {
                    Text("Запись экрана")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortcutRecordingDisplay)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                    Button("Изменить") {
                        HotkeyManager.shared.recordShortcut { keyCode, modifiers in
                            AppSettings.shortcutRecordingKeyCode = keyCode
                            AppSettings.shortcutRecordingModifiers = modifiers
                            shortcutRecordingDisplay = HotkeyManager.string(keyCode: keyCode, modifiers: modifiers)
                        }
                    }
                }
            } header: { Text("Сочетания клавиш") }
            footer: { Text("Глобальные шорткаты (работают, когда приложение в фоне). По умолчанию: ⌘⇧E — с редактированием, ⌘⇧S — сохранение в папку и загрузка в облако. Нужно разрешение «Универсальный доступ» в Системных настройках.") }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Подойдёт любой WebDAV: Nextcloud, Яндекс.Диск по WebDAV, свой сервер и т.п.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("URL сервера", text: $webdavURL, prompt: Text("https://webdav.example.com или https://webdav.yandex.ru"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: webdavURL) { _, new in AppSettings.webdavURL = new }
                    TextField("Логин (email или имя пользователя)", text: $webdavUsername)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: webdavUsername) { _, new in AppSettings.webdavUsername = new }
                    SecureField("Пароль", text: $webdavPassword)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: webdavPassword) { _, new in AppSettings.webdavPassword = new }
                    Toggle("Загружать в облако после сохранения", isOn: $autoUpload)
                        .onChange(of: autoUpload) { _, new in AppSettings.autoUploadToWebDAV = new }
                    if let msg = webdavTestMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("успешно") ? Color.green : Color.orange)
                    }
                    Button(webdavTestInProgress ? "Проверка…" : "Проверить подключение") {
                        testWebDAVConnection()
                    }
                    .disabled(webdavTestInProgress || webdavURL.isEmpty || webdavUsername.isEmpty || webdavPassword.isEmpty)
                }
                .padding(.vertical, 4)
            } header: { Text("WebDAV") }
            footer: {
                Text("Для Яндекс.Диска: URL — https://webdav.yandex.ru или https://webdav.yandex.com (если один не работает, попробуйте другой). Логин — ваш email, пароль — только пароль приложения: id.yandex.ru → Безопасность → Пароли приложений → создать для «WebDAV». Новый пароль действует через 2–3 ч.")
            }

            Section {
                Picker("Готовый фон", selection: $wallpaperPreset) {
                    Text("Нет").tag(Optional<WallpaperPreset>.none)
                    ForEach(WallpaperPreset.allCases.filter { $0 != .none }) { preset in
                        Text(preset.rawValue).tag(Optional(preset))
                    }
                }
                .onChange(of: wallpaperPreset) { _, new in AppSettings.wallpaperPreset = new }
                Toggle("Использовать обои рабочего стола Mac", isOn: $useMacWallpaper)
                    .onChange(of: useMacWallpaper) { _, new in AppSettings.useMacWallpaper = new }
                Picker("Отступ слева и справа", selection: $wallpaperPaddingPreset) {
                    ForEach(AppSettings.WallpaperPaddingPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .onChange(of: wallpaperPaddingPreset) { _, new in AppSettings.wallpaperPaddingPreset = new }
                Picker("Отступ сверху и снизу", selection: $wallpaperPaddingVerticalPreset) {
                    ForEach(AppSettings.WallpaperPaddingPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .onChange(of: wallpaperPaddingVerticalPreset) { _, new in AppSettings.wallpaperPaddingVerticalPreset = new }
                if wallpaperPreset == nil || wallpaperPreset == .none, !useMacWallpaper {
                    HStack {
                        Text(wallpaperPath.isEmpty ? "Не выбрано" : (URL(fileURLWithPath: wallpaperPath).lastPathComponent))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Выбрать…", action: chooseWallpaper)
                        if !wallpaperPath.isEmpty {
                            Button("Удалить") {
                                wallpaperPath = ""
                                AppSettings.wallpaperImagePath = nil
                            }
                        }
                    }
                }
            } header: { Text("Обои для скриншотов") }
            footer: { Text("При сохранении скриншот будет наложен на обои. Отступы — расстояние от краёв обоев до скриншота (S–XXL, 20–150 pt).") }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 700)
        .onAppear {
            defaultSaveFolder = AppSettings.defaultSaveFolder
            screenshotFormat = AppSettings.screenshotFormat
            scaleDownRetina = AppSettings.scaleDownRetina
            compressionLevel = AppSettings.compressionLevel
            webdavURL = AppSettings.webdavURL
            webdavUsername = AppSettings.webdavUsername
            webdavPassword = AppSettings.webdavPassword
            autoUpload = AppSettings.autoUploadToWebDAV
            wallpaperPath = AppSettings.wallpaperImagePath ?? ""
            useMacWallpaper = AppSettings.useMacWallpaper
            wallpaperPaddingPreset = AppSettings.wallpaperPaddingPreset
            wallpaperPaddingVerticalPreset = AppSettings.wallpaperPaddingVerticalPreset
            launchAtLogin = LaunchAtLoginManager.isEnabled
            webdavTestMessage = nil
            shortcutWithEditingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutWithEditingKeyCode, modifiers: AppSettings.shortcutWithEditingModifiers)
            shortcutWithoutEditingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutWithoutEditingKeyCode, modifiers: AppSettings.shortcutWithoutEditingModifiers)
            shortcutRecordingDisplay = HotkeyManager.string(keyCode: AppSettings.shortcutRecordingKeyCode, modifiers: AppSettings.shortcutRecordingModifiers)
            useQuickOverlayAfterCapture = AppSettings.useQuickOverlayAfterCapture
            videoSaveFolder = AppSettings.videoSaveFolder
            autoUploadVideo = AppSettings.autoUploadVideoToWebDAV
            hideDesktopIconsBeforeCapture = AppSettings.hideDesktopIconsBeforeCapture
            showCrosshairForRegionCapture = AppSettings.showCrosshairForRegionCapture
            wallpaperPreset = AppSettings.wallpaperPreset
            Task { await refreshNotificationStatus() }
        }
    }

    private var statusTextForNotification: String {
        switch notificationStatus {
        case .notDetermined: return "Разрешение не запрашивалось"
        case .denied: return "Уведомления отключены"
        case .authorized, .provisional: return "Уведомления включены"
        }
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        await MainActor.run { notificationStatus = status }
    }

    private func testWebDAVConnection() {
        AppSettings.webdavURL = webdavURL
        AppSettings.webdavUsername = webdavUsername
        AppSettings.webdavPassword = webdavPassword
        webdavTestMessage = nil
        webdavTestInProgress = true
        Task {
            do {
                try await WebDAVUploader.shared.testConnection(
                    baseURL: webdavURL.isEmpty ? nil : webdavURL,
                    username: webdavUsername.isEmpty ? nil : webdavUsername,
                    password: webdavPassword.isEmpty ? nil : webdavPassword
                )
                await MainActor.run {
                    webdavTestInProgress = false
                    webdavTestMessage = "Подключение успешно."
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

    private func chooseVideoSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = videoSaveFolder ?? defaultSaveFolder
        panel.begin { response in
            if response == .OK, let url = panel.url {
                videoSaveFolder = url
                AppSettings.videoSaveFolder = url
            }
        }
    }
}
