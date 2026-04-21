import AppKit

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?

    private var monitor: Any?

    private init() {
        registerCurrentHotkey()
    }

    func update(keyCode: UInt32, carbonModifiers: UInt32) {
        // carbonModifiers stored for compatibility; we compare using NSEvent.ModifierFlags
        registerCurrentHotkey()
    }

    private func registerCurrentHotkey() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        let kc = SettingsManager.shared.hotkeyKeyCode
        let mods = nsModifiers(fromCarbon: SettingsManager.shared.hotkeyModifiers)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kc else { return }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == mods else { return }
            self?.onTrigger?()
        }
    }

    // MARK: - Helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= 256 }  // cmdKey
        if flags.contains(.shift)   { m |= 512 }  // shiftKey
        if flags.contains(.option)  { m |= 2048 } // optionKey
        if flags.contains(.control) { m |= 4096 } // controlKey
        return m
    }

    static func displayString(carbonModifiers: UInt32, character: String) -> String {
        var s = ""
        if carbonModifiers & 4096 != 0 { s += "⌃" }
        if carbonModifiers & 2048 != 0 { s += "⌥" }
        if carbonModifiers & 512  != 0 { s += "⇧" }
        if carbonModifiers & 256  != 0 { s += "⌘" }
        return s + character.uppercased()
    }

    private func nsModifiers(fromCarbon carbon: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & 256  != 0 { flags.insert(.command) }
        if carbon & 512  != 0 { flags.insert(.shift) }
        if carbon & 2048 != 0 { flags.insert(.option) }
        if carbon & 4096 != 0 { flags.insert(.control) }
        return flags
    }
}
