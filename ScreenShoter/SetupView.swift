import SwiftUI
import AppKit

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case permissions
    case autostart
    case shortcuts
    case cloud
    case done
}

struct SetupView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @State private var yandexOAuthToken: String = AppSettings.yandexOAuthToken
    @State private var showYandexCodeInput = false
    @State private var yandexVerificationCode = ""
    @State private var yandexCodeExchangeInProgress = false
    @State private var yandexMessage: String?
    @State private var autoUpload: Bool = AppSettings.autoUploadToWebDAV

    var body: some View {
        VStack(spacing: 0) {
            if step != .done {
                stepIndicator
            }
            Group {
                switch step {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .autostart: autostartStep
                case .shortcuts: shortcutsStep
                case .cloud: cloudStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            bottomBar
        }
        .frame(width: 520, height: 520)
        .background(.ultraThinMaterial)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<OnboardingStep.allCases.count - 1, id: \.self) { i in
                Capsule()
                    .fill(i <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ScreenShoter")
                .font(.largeTitle.weight(.bold))
            Text("Быстрые скриншоты из меню-бара: вся область, окно или выбранный фрагмент. Аннотации и загрузка в облако.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    @State private var notificationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var notificationRequestInProgress = false

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Разрешения")
                .font(.title2.weight(.semibold))

            // Уведомления
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.secondary)
                    Text("Уведомления")
                        .font(.headline)
                }
                Text("Приложение показывает уведомление, когда скриншот загружен в облако (WebDAV).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        notificationRequestInProgress = true
                        Task {
                            _ = await NotificationManager.shared.requestAuthorization()
                            await MainActor.run { notificationRequestInProgress = false }
                            await refreshNotificationStatus()
                        }
                    } label: {
                        if notificationRequestInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 80, height: 22)
                        } else {
                            Text(notificationStatus == .authorized || notificationStatus == .provisional ? "Разрешено" : "Разрешить уведомления")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(notificationRequestInProgress || notificationStatus == .authorized || notificationStatus == .provisional)
                    if notificationStatus == .denied {
                        Text("Отклонено — включите в «Системные настройки» → Уведомления")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Запись экрана
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .foregroundStyle(.secondary)
                    Text("Запись экрана")
                        .font(.headline)
                }
                Text("Для скриншота выбранной области macOS запросит доступ к записи экрана. Включите ScreenShoter в списке.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Открыть «Системные настройки» → Конфиденциальность и безопасность → Запись экрана") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
        .onAppear {
            Task { await refreshNotificationStatus() }
        }
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        await MainActor.run {
            notificationStatus = status
        }
    }

    private var autostartStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Автозапуск")
                .font(.title2.weight(.semibold))
            Text("Запускать ScreenShoter при входе в систему — иконка будет всегда в меню-баре.")
                .font(.body)
                .foregroundStyle(.secondary)
            Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, new in
                    _ = LaunchAtLoginManager.setEnabled(new)
                }
            Spacer()
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Горячие клавиши")
                .font(.title2.weight(.semibold))
            Text("Открыть меню: нажмите на иконку в меню-баре (рядом с часами). Чтобы назначить свою комбинацию, откройте «Системные настройки» → Клавиатура → Сочетания клавиш → Сочетания клавиш программ.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Открыть настройки клавиатуры") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    private var cloudStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Облако (необязательно)")
                .font(.title2.weight(.semibold))
            Text("Загрузка скриншотов в Яндекс.Диск. Можно подключить позже в меню «Настройки».")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                if YandexOAuthConfig.builtInClientID.isEmpty {
                    Text("Приложение не настроено для подключения Яндекс.Диска.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if yandexOAuthToken.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !YandexOAuthConfig.builtInClientSecret.isEmpty {
                        Button(action: startYandexOAuthFlow) {
                            HStack {
                                Image(systemName: "link.badge.plus")
                                Text("Подключить Яндекс.Диск")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        Text("Откроется браузер. Войдите в аккаунт, нажмите «Разрешить» и вставьте код со страницы ниже.")
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
                        Text("Укажите Client secret в YandexOAuthConfig и пересоберите приложение.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Яндекс.Диск подключён")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Загружать в облако после сохранения", isOn: $autoUpload)
                        .toggleStyle(.switch)
                        .onChange(of: autoUpload) { _, new in
                            AppSettings.autoUploadToWebDAV = new
                        }
                }
                if let msg = yandexMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("успешно") || msg.contains("получен") || msg.contains("сохранён") ? Color.green : Color.orange)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
        .onAppear {
            yandexOAuthToken = AppSettings.yandexOAuthToken
            autoUpload = AppSettings.autoUploadToWebDAV
        }
    }

    private func startYandexOAuthFlow() {
        yandexMessage = nil
        guard let url = YandexOAuthConfig.authorizeURL else { return }
        NSWorkspace.shared.open(url)
        showYandexCodeInput = true
    }

    private func exchangeYandexCodeForToken() {
        let code = yandexVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        yandexMessage = nil
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
                    yandexMessage = "Токен получен и сохранён."
                    autoUpload = true
                    AppSettings.autoUploadToWebDAV = true
                }
            } catch {
                await MainActor.run {
                    yandexCodeExchangeInProgress = false
                    yandexMessage = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Всё готово")
                .font(.title2.weight(.semibold))
            Text("Нажмите «Готово» — иконка ScreenShoter появится в меню-баре. Клик по ней откроет меню выбора типа скриншота.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var bottomBar: some View {
        HStack {
            if step.rawValue > 0 {
                Button("Назад") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if step == .done {
                Button("Готово") {
                    closeSetup()
                }
                .buttonStyle(.borderedProminent)
            } else if step == .cloud {
                Button("Завершить") {
                    withAnimation(.easeInOut(duration: 0.2)) { step = .done }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(step == .welcome ? "Начать" : "Далее") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private func closeSetup() {
        UserDefaults.standard.set(true, forKey: "hasCheckedSetup")
        NSApp.windows.first(where: { $0.title.contains("Установка") })?.close()
    }
}
