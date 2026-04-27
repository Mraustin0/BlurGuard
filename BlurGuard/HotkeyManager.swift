import AppKit

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?

    private var monitor: Any?

    // MARK: - Carbon modifier bit-masks
    // Can't replace with OptionSet — CGEventFlags and NSEvent.ModifierFlags use
    // different bit layouts, so we keep explicit Carbon values for storage
    // and convert to NSEvent flags only when comparing live events.
    private enum CarbonMod {
        static let command: UInt32 = 256
        static let shift:   UInt32 = 512
        static let option:  UInt32 = 2048
        static let control: UInt32 = 4096
    }

    private init() {
        reregister()
    }

    func update(keyCode: UInt32, carbonModifiers: UInt32) {
        reregister()
    }

    private func reregister() {
        if let existing = monitor {
            NSEvent.removeMonitor(existing)
            monitor = nil
        }

        let targetKeyCode  = SettingsManager.shared.hotkeyKeyCode
        let targetMods     = nsModifiers(fromCarbon: SettingsManager.shared.hotkeyModifiers)

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == targetKeyCode else { return }
            let pressed = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard pressed == targetMods else { return }
            self?.onTrigger?()
        }
    }

    // MARK: - Modifier conversion helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= CarbonMod.command }
        if flags.contains(.shift)   { result |= CarbonMod.shift   }
        if flags.contains(.option)  { result |= CarbonMod.option  }
        if flags.contains(.control) { result |= CarbonMod.control }
        return result
    }

    static func displayString(carbonModifiers: UInt32, character: String) -> String {
        var symbols = ""
        if carbonModifiers & CarbonMod.control != 0 { symbols += "⌃" }
        if carbonModifiers & CarbonMod.option  != 0 { symbols += "⌥" }
        if carbonModifiers & CarbonMod.shift   != 0 { symbols += "⇧" }
        if carbonModifiers & CarbonMod.command != 0 { symbols += "⌘" }
        return symbols + character.uppercased()
    }

    private func nsModifiers(fromCarbon carbon: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & Int(CarbonMod.command) != 0 { flags.insert(.command) }
        if carbon & Int(CarbonMod.shift)   != 0 { flags.insert(.shift)   }
        if carbon & Int(CarbonMod.option)  != 0 { flags.insert(.option)  }
        if carbon & Int(CarbonMod.control) != 0 { flags.insert(.control) }
        return flags
    }
}
