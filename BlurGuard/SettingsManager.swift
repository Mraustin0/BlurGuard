import Foundation
import Security

final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - UserDefaults keys

    static let idleTimeoutKey       = "idleTimeout"
    static let hotkeyKeyCodeKey     = "hotkeyKeyCode"
    static let hotkeyModifiersKey   = "hotkeyModifiers"
    static let hotkeyDisplayKey     = "hotkeyDisplay"
    static let ignoredBundleIDsKey  = "ignoredBundleIDs"
    static let cameraEnabledKey     = "cameraEnabled"
    static let cameraAwayDelayKey   = "cameraAwayDelay"
    static let cameraSensitivityKey = "cameraSensitivity"
    static let peekResponseKey      = "peekResponse"
    static let awayResponseKey      = "awayResponse"

    private init() {
        UserDefaults.standard.register(defaults: [
            Self.idleTimeoutKey:       30.0,
            Self.hotkeyKeyCodeKey:     37,       // L key
            Self.hotkeyModifiersKey:   768,      // ⇧⌘ (shift=512 + cmd=256)
            Self.hotkeyDisplayKey:     "⇧⌘L",
            Self.cameraEnabledKey:     false,
            Self.cameraAwayDelayKey:   8,
            Self.cameraSensitivityKey: 0.6,
            Self.peekResponseKey:      "blur",
            Self.awayResponseKey:      "blur",
            Self.ignoredBundleIDsKey:  [
                "us.zoom.xos",
                "com.microsoft.teams",
                "com.microsoft.teams2",
                "com.cisco.webexmeetings",
                "com.apple.FaceTime",
            ],
        ])
    }

    // MARK: - Idle timeout (10 s – 10 min)

    var idleTimeout: TimeInterval {
        get { min(max(UserDefaults.standard.double(forKey: Self.idleTimeoutKey), 10), 600) }
        set { UserDefaults.standard.set(min(max(newValue, 10), 600), forKey: Self.idleTimeoutKey) }
    }

    // MARK: - Hotkey

    var hotkeyKeyCode: Int {
        get { UserDefaults.standard.integer(forKey: Self.hotkeyKeyCodeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hotkeyKeyCodeKey) }
    }

    var hotkeyModifiers: Int {
        get { UserDefaults.standard.integer(forKey: Self.hotkeyModifiersKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hotkeyModifiersKey) }
    }

    var hotkeyDisplay: String {
        get { UserDefaults.standard.string(forKey: Self.hotkeyDisplayKey) ?? "⇧⌘L" }
        set { UserDefaults.standard.set(newValue, forKey: Self.hotkeyDisplayKey) }
    }

    // MARK: - Camera

    var cameraEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.cameraEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.cameraEnabledKey) }
    }

    var cameraAwayDelay: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Self.cameraAwayDelayKey)
            return v == 0 ? 8 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.cameraAwayDelayKey) }
    }

    var cameraSensitivity: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Self.cameraSensitivityKey)
            return v == 0 ? 0.6 : v
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: Self.cameraSensitivityKey) }
    }

    // MARK: - Response actions ("blur" or "lock")

    var peekResponse: String {
        get { UserDefaults.standard.string(forKey: Self.peekResponseKey) ?? "blur" }
        set { UserDefaults.standard.set(newValue, forKey: Self.peekResponseKey) }
    }

    var awayResponse: String {
        get { UserDefaults.standard.string(forKey: Self.awayResponseKey) ?? "blur" }
        set { UserDefaults.standard.set(newValue, forKey: Self.awayResponseKey) }
    }

    // MARK: - Ignored bundle IDs

    var ignoredBundleIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.array(forKey: Self.ignoredBundleIDsKey) as? [String] ?? []
            return Set(stored)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.ignoredBundleIDsKey) }
    }

    // MARK: - Require authentication (Keychain)
    // Stored in the Keychain rather than UserDefaults so it can't be trivially
    // toggled by editing a plist file. kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    // prevents it from being copied to another device via backup or migration.

    private let keychainService = "com.blurguard.app"
    private let keychainAccount = "requireAuth"

    var requireAuth: Bool {
        get { keychainRead() ?? true }
        set { keychainWrite(newValue) }
    }

    private func keychainWrite(_ value: Bool) {
        let data  = Data([value ? 1 : 0])
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
        ]
        let attrs: [CFString: Any] = [
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
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
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  keychainService,
            kSecAttrAccount:  keychainAccount,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let byte = data.first
        else { return nil }
        return byte != 0
    }
}
