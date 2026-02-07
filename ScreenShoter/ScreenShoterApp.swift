import SwiftUI
import AppKit

@main
struct ScreenShoterApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("hasCheckedSetup") private var hasCheckedSetup = false

    init() {
        _ = NotificationManager.shared
        // SparkleUpdater.controller создаётся при первом обращении (на MainActor)
    }

    var body: some Scene {
        MenuBarExtra("ScreenShoter", systemImage: "crop") {
            LauncherMenuView(appState: appState, hasCheckedSetup: $hasCheckedSetup)
        }
        .menuBarExtraStyle(.window)

        Window(String(localized: "window.annotation_title"), id: "annotation") {
            if let image = appState.capturedImage {
                AnnotationView(image: image, appState: appState)
                    .id(appState.annotationImageId)
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = WindowDockHelper.findAndConfigure(id: .annotation, titleContains: String(localized: "window.annotations")) {
                                window.level = .normal
                                window.collectionBehavior = [.managed, .participatesInCycle]
                            }
                            WindowDockHelper.updateDockVisibility()
                        }
                    }
                    .onDisappear { WindowDockHelper.updateDockVisibilityAfterClose() }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .commandsRemoved()

        Window(String(localized: "window.overlay_title"), id: "quickOverlay") {
            if let image = appState.capturedImage {
                QuickOverlayView(image: image, appState: appState)
                    .onAppear {
                        DispatchQueue.main.async {
                            if let window = WindowDockHelper.findAndConfigure(id: .quickOverlay, titleContains: String(localized: "window.quick_overlay")) {
                                window.level = .floating
                                window.collectionBehavior = [.managed, .participatesInCycle]
                                window.isMovableByWindowBackground = true
                            }
                            WindowDockHelper.updateDockVisibility()
                        }
                    }
                    .onDisappear { WindowDockHelper.updateDockVisibilityAfterClose() }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 200)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Window(String(localized: "window.setup_title"), id: "setup") {
            SetupView()
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = WindowDockHelper.findAndConfigure(id: .setup, titleContains: String(localized: "window.setup")) {
                            window.level = .floating
                            window.collectionBehavior = [.managed, .participatesInCycle]
                            window.isMovableByWindowBackground = true
                        }
                        WindowDockHelper.updateDockVisibility()
                    }
                }
                .onDisappear { WindowDockHelper.updateDockVisibilityAfterClose() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 520)

        Window(String(localized: "window.history_title"), id: "history") {
            HistoryView()
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = WindowDockHelper.findAndConfigure(id: .history, titleContains: String(localized: "window.history")) {
                            window.level = .normal
                            window.collectionBehavior = [.managed, .participatesInCycle]
                            window.isMovableByWindowBackground = true
                        }
                        WindowDockHelper.updateDockVisibility()
                    }
                }
                .onDisappear { WindowDockHelper.updateDockVisibilityAfterClose() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 500)
        
        Window(String(localized: "window.settings_title"), id: "settings") {
            SettingsView()
                .onAppear {
                    DispatchQueue.main.async {
                        if let window = WindowDockHelper.findAndConfigure(id: .settings, titleContains: String(localized: "window.settings")) {
                            window.level = .normal
                            window.collectionBehavior = [.managed, .participatesInCycle]
                            window.isMovableByWindowBackground = true
                        }
                        WindowDockHelper.updateDockVisibility()
                    }
                }
                .onDisappear { WindowDockHelper.updateDockVisibilityAfterClose() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 700)
    }
}
