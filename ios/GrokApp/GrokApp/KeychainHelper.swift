// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

enum KeychainHelper {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "app.grokbuild.ios"
    }

    private static let apiKeyAccount = "XAI_API_KEY"

    #if DEBUG
    /// Unsigned simulator builds lack Keychain entitlements; session-only memory (never UserDefaults).
    private static var debugSessionKey: String?
    /// After Sign out, ignore `SIMCTL_CHILD_XAI_API_KEY` / process env until user pastes a key again.
    private static var ignoreLaunchEnvKey = false
    #endif

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess {
            #if DEBUG
            debugSessionKey = nil
            ignoreLaunchEnvKey = false
            #endif
            return
        }
        #if DEBUG
        if status == errSecMissingEntitlement || status == errSecNotAvailable {
            debugSessionKey = key
            ignoreLaunchEnvKey = false
            return
        }
        #endif
        throw KeychainError.saveFailed(status)
    }

    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let key = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        #if DEBUG
        if let key = debugSessionKey?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        if !ignoreLaunchEnvKey,
           let env = ProcessInfo.processInfo.environment["XAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            debugSessionKey = env
            return env
        }
        #endif
        return nil
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]
        SecItemDelete(query as CFDictionary)
        #if DEBUG
        debugSessionKey = nil
        ignoreLaunchEnvKey = true
        #endif
    }

    static var hasAPIKey: Bool {
        guard let key = loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !key.isEmpty
    }

    #if DEBUG
    /// Test hook — never persisted to disk.
    static func setDebugSessionAPIKey(_ key: String?) {
        debugSessionKey = key
        if key != nil { ignoreLaunchEnvKey = false }
    }
    #endif
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            if status == errSecMissingEntitlement {
                return "Keychain unavailable on this build (missing signing). Rebuild with a development team."
            }
            return "Keychain save failed (\(status))"
        }
    }
}
