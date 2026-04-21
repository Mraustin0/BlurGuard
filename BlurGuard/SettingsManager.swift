import Foundation
import Security

final class SettingsManager {
    static let shared = SettingsManager()

    static let idleTimeoutKey = "idleTimeout"
    static let requireAuthKey = "requireAuth"
    static let hotkeyKeyCodeKey = "hotkeyKeyCode"
    static let hotkeyModifiersKey = "hotkeyModifiers"
    static let hotkeyDisplayKey = "hotkeyDisplay"
    static let ignoredBundleIDsKey = "ignoredBundleIDs"

    private let keychainService = "com.blurguard.app"
    private let requireAuthKeychainKey = "requireAuth"

    private init() {
        let defaults: [String: Any] = [
            SettingsManager.idleTimeoutKey: 30.0,
            SettingsManager.hotkeyKeyCodeKey: 37,    // L key
            SettingsManager.hotkeyModifiersKey: 768, // ⌘⇧ (cmdKey=256 + shiftKey=512)
            SettingsManager.hotkeyDisplayKey: "⌘⇧L",
            SettingsManager.ignoredBundleIDsKey: [
                "us.zoom.xos",
                "com.microsoft.teams",
                "com.microsoft.teams2",
                "com.cisco.webexmeetings",
                "com.apple.FaceTime",
            ],
        ]
        UserDefaults.standard.register(defaults: defaults)
    }

    // MARK: - Idle Timeout (UserDefaults with range validation)

    var idleTimeout: TimeInterval {
        get {
            let raw = UserDefaults.standard.double(forKey: SettingsManager.idleTimeoutKey)
            // Clamp to valid range: 10s – 10min
            return min(max(raw, 10), 600)
        }
        set {
            let clamped = min(max(newValue, 10), 600)
            UserDefaults.standard.set(clamped, forKey: SettingsManager.idleTimeoutKey)
        }
    }

    // MARK: - Hotkey (UserDefaults)

    var hotkeyKeyCode: Int {
        get { UserDefaults.standard.integer(forKey: Self.hotkeyKeyCodeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hotkeyKeyCodeKey) }
    }

    var hotkeyModifiers: Int {
        get { UserDefaults.standard.integer(forKey: Self.hotkeyModifiersKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hotkeyModifiersKey) }
    }

    var hotkeyDisplay: String {
        get { UserDefaults.standard.string(forKey: Self.hotkeyDisplayKey) ?? "⌘⇧L" }
        set { UserDefaults.standard.set(newValue, forKey: Self.hotkeyDisplayKey) }
    }

    // MARK: - Ignored Bundle IDs (UserDefaults)

    var ignoredBundleIDs: Set<String> {
        get {
            let arr = (UserDefaults.standard.array(forKey: Self.ignoredBundleIDsKey) as? [String]) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.ignoredBundleIDsKey)
        }
    }

    // MARK: - Require Auth (Keychain — tamper-resistant)

    var requireAuth: Bool {
        get { keychainRead() ?? true }   // default to true if missing
        set { keychainWrite(newValue) }
    }

    private func keychainWrite(_ value: Bool) {
        let data = Data([value ? 1 : 0])
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: requireAuthKeychainKey,
        ]
        // ThisDeviceOnly: prevents backup/migration to another device
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                NSLog("[BlurGuard] Keychain add failed: \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            NSLog("[BlurGuard] Keychain update failed: \(updateStatus)")
        }
    }

    private func keychainRead() -> Bool? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: requireAuthKeychainKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let byte = data.first
        else { return nil }
        return byte != 0
    }
}
