// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User-configurable companion endpoint, pairing, and TLS fingerprint.
enum CompanionConfig {
    struct Endpoint: Equatable {
        var host: String
        var port: Int
        var useTLS: Bool
        /// Official `grok agent serve` WebSocket (pro path). When false, legacy TCP+TLS bridge.
        var useWebSocket: Bool
    }

    static let defaultPort = 7391
    /// Official `grok agent serve` default bind port.
    static let defaultWebSocketPort = 2419
    static let bonjourType = "_grok-build._tcp"
    static let bonjourName = "Grok Build"

    private static let hostKey = "GROK_ACP_HOST"
    private static let portKey = "GROK_ACP_PORT"
    private static let onboardedKey = "GROK_ONBOARDED"
    private static let pinKey = "GROK_PAIR_PIN"
    private static let tokenKey = "GROK_PAIR_TOKEN"
    private static let fingerprintKey = "GROK_CERT_FINGERPRINT"
    private static let tlsKey = "GROK_USE_TLS"
    private static let wsKey = "GROK_USE_WEBSOCKET"

    static var isOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedKey) }
    }

    static var pairToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
        }
    }

    static var savedPIN: String {
        get { UserDefaults.standard.string(forKey: pinKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: pinKey) }
    }

    static var pinnedFingerprint: String {
        get { UserDefaults.standard.string(forKey: fingerprintKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: fingerprintKey) }
    }

    static func bundledPort() -> Int {
        if let url = Bundle.main.url(forResource: "companion.defaults", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let port = obj["port"] as? Int, port > 0 {
            return port
        }
        return defaultWebSocketPort
    }

    /// Absolute Mac workspace for `session/new` (official serve rejects relative cwd).
    static func workspaceCwd() -> String {
        if let stored = UserDefaults.standard.string(forKey: "GROK_WORKSPACE_CWD")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           stored.hasPrefix("/") {
            return stored
        }
        if let url = Bundle.main.url(forResource: "companion.defaults", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cwd = obj["cwd"] as? String,
           cwd.hasPrefix("/") {
            return cwd
        }
        // Fallback absolute path accepted by `grok agent serve`.
        return "/tmp"
    }

    static func saveWorkspaceCwd(_ cwd: String) {
        let c = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.hasPrefix("/") {
            UserDefaults.standard.set(c, forKey: "GROK_WORKSPACE_CWD")
        }
    }

    static func resolved() -> Endpoint {
        let useWS = UserDefaults.standard.object(forKey: wsKey) as? Bool ?? true
        let useTLS = UserDefaults.standard.object(forKey: tlsKey) as? Bool
        let host = UserDefaults.standard.string(forKey: hostKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedPort = UserDefaults.standard.integer(forKey: portKey)
        let resolvedHost = host.isEmpty ? "127.0.0.1" : host
        let local = resolvedHost == "127.0.0.1" || resolvedHost == "localhost" || resolvedHost == "::1"
        let defaultPort = useWS ? defaultWebSocketPort : defaultPort
        return Endpoint(
            host: resolvedHost,
            port: storedPort > 0 ? storedPort : defaultPort,
            useTLS: useWS ? false : (useTLS ?? !local),
            useWebSocket: useWS
        )
    }

    static func save(host: String, port: Int, useTLS: Bool = false, useWebSocket: Bool = true) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(h, forKey: hostKey)
        UserDefaults.standard.set(port > 0 ? port : (useWebSocket ? defaultWebSocketPort : defaultPort), forKey: portKey)
        UserDefaults.standard.set(useTLS, forKey: tlsKey)
        UserDefaults.standard.set(useWebSocket, forKey: wsKey)
    }

    static var hasHost: Bool {
        !resolved().host.isEmpty
    }

    /// Saved Secret from `grok agent serve` (stored in GROK_PAIR_PIN for compatibility).
    static var hasSavedSecret: Bool {
        !savedPIN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Golden path: WebSocket serve with a pasted Secret.
    static var isWebSocketServe: Bool {
        resolved().useWebSocket
    }

    static func clearPairing() {
        pairToken = nil
        savedPIN = ""
        pinnedFingerprint = ""
    }

    static func savePairing(pin: String, fingerprint: String, token: String?) {
        savedPIN = pin
        pinnedFingerprint = fingerprint
        pairToken = token
    }

    // MARK: - Welcome top_bar location (last known companion cwd/git)

    private static let lastCwdKey = "GROK_LAST_CWD"
    private static let lastGitKey = "GROK_LAST_GIT_BRANCH"
    private static let lastWorktreeKey = "GROK_LAST_IS_WORKTREE"

    static func persistWelcomeLocation(cwd: String, gitBranch: String?, isWorktree: Bool) {
        if !cwd.isEmpty {
            UserDefaults.standard.set(cwd, forKey: lastCwdKey)
        }
        if let gitBranch {
            UserDefaults.standard.set(gitBranch, forKey: lastGitKey)
        }
        UserDefaults.standard.set(isWorktree, forKey: lastWorktreeKey)
    }

    static func welcomeLocation() -> (cwd: String, gitBranch: String?, isWorktree: Bool) {
        (
            UserDefaults.standard.string(forKey: lastCwdKey) ?? "",
            UserDefaults.standard.string(forKey: lastGitKey),
            UserDefaults.standard.bool(forKey: lastWorktreeKey)
        )
    }
}
