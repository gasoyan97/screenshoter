import Foundation
import AppKit

/// Глобальные шорткаты: скриншот с редактированием / без (сохранение + облако).
/// Требуется разрешение «Универсальный доступ» (Accessibility).
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var globalMonitor: Any?
    private var withEditingHandler: (() -> Void)?
    private var withoutEditingHandler: (() -> Void)?
    private var recordingHandler: (() -> Void)?
    private var isStarted = false

    private init() {}

    func setHandlers(withEditing: @escaping () -> Void, withoutEditing: @escaping () -> Void, recording: (() -> Void)? = nil) {
        withEditingHandler = withEditing
        withoutEditingHandler = withoutEditing
        recordingHandler = recording
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    func stop() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        isStarted = false
    }

    private func handleKeyDown(_ event: NSEvent) {
        let mod = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let key = event.keyCode

        let withCode = AppSettings.shortcutWithEditingKeyCode
        let withMod = AppSettings.shortcutWithEditingModifiers
        let withoutCode = AppSettings.shortcutWithoutEditingKeyCode
        let withoutMod = AppSettings.shortcutWithoutEditingModifiers

        if key == withCode && UInt(mod) == withMod {
            DispatchQueue.main.async { [weak self] in
                self?.withEditingHandler?()
            }
            return
        }
        if key == withoutCode && UInt(mod) == withoutMod {
            DispatchQueue.main.async { [weak self] in
                self?.withoutEditingHandler?()
            }
            return
        }
        let recCode = AppSettings.shortcutRecordingKeyCode
        let recMod = AppSettings.shortcutRecordingModifiers
        if key == recCode && UInt(mod) == recMod {
            DispatchQueue.main.async { [weak self] in
                self?.recordingHandler?()
            }
        }
    }

    /// Записать новое сочетание: ставит локальный монитор на один keyDown, затем вызывает completion(keyCode, modifiers).
    /// Монитор снимается по нажатию клавиши или через 60 с (если окно закрыли без нажатия).
    func recordShortcut(completion: @escaping (UInt16, UInt) -> Void) {
        class Holder {
            var monitor: Any?
            var cleanupWorkItem: DispatchWorkItem?
        }
        let holder = Holder()
        holder.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            holder.cleanupWorkItem?.cancel()
            holder.cleanupWorkItem = nil
            if let m = holder.monitor { NSEvent.removeMonitor(m); holder.monitor = nil }
            let mod = UInt(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            DispatchQueue.main.async { completion(event.keyCode, mod) }
            return nil
        }
        let workItem = DispatchWorkItem { [weak holder] in
            guard let h = holder, let m = h.monitor else { return }
            NSEvent.removeMonitor(m)
            h.monitor = nil
            h.cleanupWorkItem = nil
        }
        holder.cleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: workItem)
    }

    /// Строка для отображения сочетания (⌘⇧E и т.п.).
    static func string(keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []
        let m = NSEvent.ModifierFlags(rawValue: modifiers)
        if m.contains(.command) { parts.append("⌘") }
        if m.contains(.shift) { parts.append("⇧") }
        if m.contains(.option) { parts.append("⌥") }
        if m.contains(.control) { parts.append("⌃") }
        if let char = keyCodeToCharacter(keyCode) { parts.append(String(char)) }
        return parts.joined()
    }

    private static func keyCodeToCharacter(_ code: UInt16) -> Character? {
        let map: [UInt16: Character] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↵", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "⇥", 49: "␣", 50: "`", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[code]
    }
}
