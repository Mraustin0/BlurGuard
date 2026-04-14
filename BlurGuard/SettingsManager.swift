import Foundation
import Security

final class SettingsManager {
    static let shared = SettingsManager()

    static let idleTimeoutKey = "idleTimeout"
    static let requireAuthKey = "requireAuth"

    private let keychainService = "com.blurguard.app"
    private let requireAuthKeychainKey = "requireAuth"

    private init() {
        let defaults: [String: Any] = [
            SettingsManager.idleTimeoutKey: 30.0
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
        let attributes: [CFString: Any] = [kSecValueData: data]

        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
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
