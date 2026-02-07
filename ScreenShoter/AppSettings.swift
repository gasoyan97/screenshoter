import Foundation
import AppKit

enum ScreenshotFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
    var utType: String { self == .png ? "public.png" : "public.jpeg" }
}

/// Степень сжатия JPEG: нет = max качество, среднее = баланс, сильное = меньший размер.
enum CompressionLevel: String, CaseIterable, Identifiable {
    case none = "Нет"
    case medium = "Среднее"
    case strong = "Сильное"
    var id: String { rawValue }
    var jpegQuality: CGFloat {
        switch self {
        case .none: return 1.0
        case .medium: return 0.85
        case .strong: return 0.6
        }
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    static var defaultSaveFolder: URL? {
        get {
            defaults.url(forKey: "defaultSaveFolder") ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        set {
            defaults.set(newValue, forKey: "defaultSaveFolder")
        }
    }

    static var screenshotFormat: ScreenshotFormat {
        get {
            guard let raw = defaults.string(forKey: "screenshotFormat"),
                  let f = ScreenshotFormat(rawValue: raw) else { return .png }
            return f
        }
        set { defaults.set(newValue.rawValue, forKey: "screenshotFormat") }
    }

    static var compressionLevel: CompressionLevel {
        get {
            guard let raw = defaults.string(forKey: "compressionLevel"),
                  let c = CompressionLevel(rawValue: raw) else { return .medium }
            return c
        }
        set { defaults.set(newValue.rawValue, forKey: "compressionLevel") }
    }

    /// Уменьшать Retina (2x → 1x) при сохранении — меньший размер файла, как в CleanShot.
    static var scaleDownRetina: Bool {
        get { defaults.bool(forKey: "scaleDownRetina") }
        set { defaults.set(newValue, forKey: "scaleDownRetina") }
    }

    static var wallpaperImagePath: String? {
        get { defaults.string(forKey: "wallpaperImagePath") }
        set { defaults.set(newValue, forKey: "wallpaperImagePath") }
    }

    /// true = использовать текущие обои рабочего стола Mac; false = свой файл из wallpaperImagePath.
    static var useMacWallpaper: Bool {
        get { defaults.bool(forKey: "useMacWallpaper") }
        set { defaults.set(newValue, forKey: "useMacWallpaper") }
    }

    /// Паддинг (отступ) от краёв обоев до скриншота: S=20, M=50, L=90, XXL=150 pt.
    enum WallpaperPaddingPreset: String, CaseIterable, Identifiable {
        case s = "S"
        case m = "M"
        case l = "L"
        case xxl = "XXL"
        var id: String { rawValue }
        var points: CGFloat {
            switch self {
            case .s: return 20
            case .m: return 50
            case .l: return 90
            case .xxl: return 150
            }
        }
        var label: String { "\(rawValue) (\(Int(points)) pt)" }
    }
    static var wallpaperPaddingPreset: WallpaperPaddingPreset {
        get {
            guard let raw = defaults.string(forKey: "wallpaperPaddingPreset"),
                  let p = WallpaperPaddingPreset(rawValue: raw) else { return .m }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: "wallpaperPaddingPreset") }
    }

    /// Паддинг сверху и снизу (от краёв обоев до скриншота). По умолчанию тот же, что и горизонтальный.
    static var wallpaperPaddingVerticalPreset: WallpaperPaddingPreset {
        get {
            guard let raw = defaults.string(forKey: "wallpaperPaddingVerticalPreset"),
                  let p = WallpaperPaddingPreset(rawValue: raw) else { return .m }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: "wallpaperPaddingVerticalPreset") }
    }

    /// Готовый фон (градиент, текстура). nil или .none = не использовать пресет (обои Mac или свой файл).
    static var wallpaperPreset: WallpaperPreset? {
        get {
            guard let raw = defaults.string(forKey: "wallpaperPreset"), !raw.isEmpty, raw != WallpaperPreset.none.rawValue,
                  let p = WallpaperPreset(rawValue: raw) else { return nil }
            return p == .none ? nil : p
        }
        set {
            if let p = newValue, p != .none {
                defaults.set(p.rawValue, forKey: "wallpaperPreset")
            } else {
                defaults.removeObject(forKey: "wallpaperPreset")
            }
        }
    }

    static var webdavURL: String {
        get { defaults.string(forKey: "webdavURL") ?? "" }
        set { defaults.set(newValue, forKey: "webdavURL") }
    }

    static var webdavUsername: String {
        get { defaults.string(forKey: "webdavUsername") ?? "" }
        set { defaults.set(newValue, forKey: "webdavUsername") }
    }

    static var webdavPassword: String {
        get { defaults.string(forKey: "webdavPassword") ?? "" }
        set { defaults.set(newValue, forKey: "webdavPassword") }
    }

    static var autoUploadToWebDAV: Bool {
        get { defaults.bool(forKey: "autoUploadToWebDAV") }
        set { defaults.set(newValue, forKey: "autoUploadToWebDAV") }
    }

    static var launchAtLogin: Bool {
        get { LaunchAtLoginManager.isEnabled }
        set { _ = LaunchAtLoginManager.setEnabled(newValue) }
    }

    /// После съёмки показывать быстрый оверлей (Сохранить/Копировать/Загрузить/Редактировать) вместо полного окна аннотаций.
    static var useQuickOverlayAfterCapture: Bool {
        get { defaults.bool(forKey: "useQuickOverlayAfterCapture") }
        set { defaults.set(newValue, forKey: "useQuickOverlayAfterCapture") }
    }

    /// Папка для сохранения записей экрана. nil = использовать defaultSaveFolder.
    static var videoSaveFolder: URL? {
        get { defaults.url(forKey: "videoSaveFolder") }
        set { defaults.set(newValue, forKey: "videoSaveFolder") }
    }

    /// Загружать записанное видео в WebDAV после остановки записи.
    static var autoUploadVideoToWebDAV: Bool {
        get { defaults.bool(forKey: "autoUploadVideoToWebDAV") }
        set { defaults.set(newValue, forKey: "autoUploadVideoToWebDAV") }
    }

    /// Скрывать иконки рабочего стола перед съёмкой (вся область или выбранная область).
    static var hideDesktopIconsBeforeCapture: Bool {
        get { defaults.bool(forKey: "hideDesktopIconsBeforeCapture") }
        set { defaults.set(newValue, forKey: "hideDesktopIconsBeforeCapture") }
    }

    /// При выборе области показывать прицел (собственный оверлей с crosshair вместо системного выбора).
    static var showCrosshairForRegionCapture: Bool {
        get { defaults.bool(forKey: "showCrosshairForRegionCapture") }
        set { defaults.set(newValue, forKey: "showCrosshairForRegionCapture") }
    }

    // Шорткаты: скриншот с редактированием / без (сохранение + облако)
    private static let defaultWithEditingKeyCode: UInt16 = 14   // E
    private static let defaultWithEditingModifiers: UInt = 768  // Cmd+Shift
    private static let defaultWithoutEditingKeyCode: UInt16 = 1 // S
    private static let defaultWithoutEditingModifiers: UInt = 768

    static var shortcutWithEditingKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: "shortcutWithEditingKeyCode") == 0 ? Int(defaultWithEditingKeyCode) : defaults.integer(forKey: "shortcutWithEditingKeyCode")) }
        set { defaults.set(Int(newValue), forKey: "shortcutWithEditingKeyCode") }
    }
    static var shortcutWithEditingModifiers: UInt {
        get { let v = defaults.integer(forKey: "shortcutWithEditingModifiers"); return v == 0 ? defaultWithEditingModifiers : UInt(v) }
        set { defaults.set(Int(newValue), forKey: "shortcutWithEditingModifiers") }
    }
    static var shortcutWithoutEditingKeyCode: UInt16 {
        get { let v = defaults.integer(forKey: "shortcutWithoutEditingKeyCode"); return v == 0 ? defaultWithoutEditingKeyCode : UInt16(v) }
        set { defaults.set(Int(newValue), forKey: "shortcutWithoutEditingKeyCode") }
    }
    static var shortcutWithoutEditingModifiers: UInt {
        get { let v = defaults.integer(forKey: "shortcutWithoutEditingModifiers"); return v == 0 ? defaultWithoutEditingModifiers : UInt(v) }
        set { defaults.set(Int(newValue), forKey: "shortcutWithoutEditingModifiers") }
    }

    // Шорткат записи экрана: начать/остановить запись
    private static let defaultRecordingKeyCode: UInt16 = 15  // R
    private static let defaultRecordingModifiers: UInt = 768  // Cmd+Shift
    static var shortcutRecordingKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: "shortcutRecordingKeyCode") == 0 ? Int(defaultRecordingKeyCode) : defaults.integer(forKey: "shortcutRecordingKeyCode")) }
        set { defaults.set(Int(newValue), forKey: "shortcutRecordingKeyCode") }
    }
    static var shortcutRecordingModifiers: UInt {
        get { let v = defaults.integer(forKey: "shortcutRecordingModifiers"); return v == 0 ? defaultRecordingModifiers : UInt(v) }
        set { defaults.set(Int(newValue), forKey: "shortcutRecordingModifiers") }
    }
}
