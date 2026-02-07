import SwiftUI
import AppKit
import Sparkle

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
            footer: { Text("Уведомление показывается после загрузки скриншота в облако.") }

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
                Toggle("Загружать в облако после сохранения", isOn: $autoUpload)
                    .onChange(of: autoUpload) { _, new in AppSettings.autoUploadToWebDAV = new }

                VStack(alignment: .leading, spacing: 12) {
                    if YandexOAuthConfig.builtInClientID.isEmpty {
                        Text("Приложение не настроено для подключения Яндекс.Диска.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Link("Инструкция для разработчика", destination: URL(string: "https://yandex.ru/dev/disk-api/doc/ru/concepts/quickstart")!)
                            .font(.caption)
                    } else if yandexOAuthToken.trimmingCharacters(in: .whitespaces).isEmpty {
                        if YandexOAuthConfig.builtInClientSecret.isEmpty {
                            Text("Укажите Client secret в YandexOAuthConfig.swift (скопируйте с страницы приложения на oauth.yandex.ru) и пересоберите приложение.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(action: startOAuthTokenFlow) {
                            HStack {
                                Image(systemName: "link.badge.plus")
                                Text("Подключить Яндекс.Диск")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        Text("Нажмите кнопку — откроется браузер. Войдите в аккаунт и нажмите «Разрешить», затем скопируйте код со страницы и вставьте ниже.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if showYandexCodeInput {
                            HStack(spacing: 8) {
                                TextField("Код со страницы", text: $yandexVerificationCode)
                                    .textFieldStyle(.roundedBorder)
                                Button(yandexCodeExchangeInProgress ? "Получение…" : "Получить токен") {
                                    exchangeYandexCodeForToken()
                                }
                                .disabled(yandexCodeExchangeInProgress || yandexVerificationCode.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Яндекс.Диск подключён")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Отключить") {
                                yandexOAuthToken = ""
                                AppSettings.yandexOAuthToken = ""
                            }
                            .buttonStyle(.borderless)
                        }
                        Button(webdavTestInProgress ? "Проверка…" : "Проверить подключение") {
                            testYandexRESTConnection()
                        }
                        .disabled(webdavTestInProgress)
                    }
                    if let msg = webdavTestMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("успешно") || msg.contains("получен") ? Color.green : Color.orange)
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Яндекс.Диск") }
            footer: { Text("Нажмите «Подключить Яндекс.Диск» — войдите в аккаунт и нажмите «Разрешить». Файлы сохраняются в папку ScreenShoter_mac.") }

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

            Section {
                Button("Проверить обновления…") {
                    SPUStandardUpdaterController(
                        startingUpdater: true,
                        updaterDelegate: nil,
                        userDriverDelegate: nil
                    ).checkForUpdates(nil)
                }
            } header: { Text("Обновления") }
            footer: { Text("Проверить наличие новой версии ScreenShoter.") }
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
                    webdavTestMessage = "Токен получен и сохранён."
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
