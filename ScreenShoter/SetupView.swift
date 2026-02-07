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
    @State private var webdavURL: String = AppSettings.webdavURL
    @State private var webdavUsername: String = AppSettings.webdavUsername
    @State private var webdavPassword: String = AppSettings.webdavPassword

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
            Text("Можно настроить загрузку скриншотов по WebDAV (Nextcloud, Яндекс.Диск по WebDAV, свой сервер). Позже — в меню «Настройки».")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("WebDAV (URL, логин, пароль):")
                    .font(.subheadline.weight(.medium))
                TextField("URL", text: $webdavURL, prompt: Text("https://webdav.example.com или https://webdav.yandex.ru"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: webdavURL) { _, new in AppSettings.webdavURL = new }
                TextField("Логин", text: $webdavUsername)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: webdavUsername) { _, new in AppSettings.webdavUsername = new }
                SecureField("Пароль", text: $webdavPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: webdavPassword) { _, new in AppSettings.webdavPassword = new }
            }
            Spacer()
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
            if step.rawValue > 0 && step != .cloud {
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
