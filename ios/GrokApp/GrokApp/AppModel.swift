// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
import SwiftUI
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: AppScreen = .welcome
    @Published var messages: [ScrollbackEntry] = []
    @Published var draft: String = ""
    @Published var alwaysApprove: Bool = false {
        didSet {
            acp.alwaysApprove = alwaysApprove
            chrome.alwaysApprove = alwaysApprove
        }
    }
    @Published var themeName: String = "GrokNight"
    @Published var sessionTitle: String = "loading..."
    @Published var chrome = SessionChrome()
    @Published var permissionRequest: PermissionRequest?
    @Published var isPromptFocused: Bool = false
    @Published var apiKeyDraft: String = ""
    @Published var acpHostDraft: String = ""
    @Published var acpPortDraft: String = "2419"
    @Published var pairPinDraft: String = ""
    @Published var fingerprintDraft: String = ""
    @Published var setupError: String?
    /// Setup Connect button: idle → checking (spinner) → succeeded / failed.
    @Published var connectionPhase: ConnectionPhase = .idle
    @Published var workspaceFiles: [String] = []
    @Published var fileFilter: String = ""
    @Published var sessionListEntries: [SessionListEntry] = []
    @Published var isLoadingSessions = false
    @Published var showTimestamps: Bool = AppSettings.showTimestamps
    @Published var showThinkingBlocks: Bool = AppSettings.showThinkingBlocks
    /// Upstream dashboard roster from `x.ai/sessions/list` (falls back to session/list).
    @Published var dashboardRows: [DashboardRowModel] = []
    /// Shell-owned `[ui]` values from companion `config_get` (Mac ~/.grok/config.toml).
    @Published var shellConfig: [String: Bool] = [:]
    @Published var shellConfigStrings: [String: String] = [:]
    @Published var shellConfigPath: String = ""
    @Published var mermaidRenderError: String?
    /// Shown in agent chrome when transport drops and reconnect is in progress.
    @Published var reconnectBanner: String?

    let acp = ACPClient()
    let companionBrowser = CompanionBrowser()
    private var acpBagForward: AnyCancellable?
    private var browserBagForward: AnyCancellable?
    private var isReconnecting = false

    var theme: GrokTheme { GrokTheme.load(named: themeName) }
    var hasAPIKey: Bool { KeychainHelper.hasAPIKey }

    /// Official path: `grok agent serve` Secret + host. Legacy Bonjour bridge is advanced-only.
    var canStartSession: Bool {
        if preferredBonjourEndpoint != nil {
            return CompanionConfig.hasSavedSecret
        }
        return CompanionConfig.hasHost && CompanionConfig.hasSavedSecret
    }

    var hasChangelog: Bool {
        Bundle.main.url(forResource: "0.2.99", withExtension: "md", subdirectory: "changelogs") != nil
            || Bundle.main.url(forResource: "0.2.99", withExtension: "md") != nil
    }

    var changelogTitle: String {
        guard let text = loadChangelogText() else { return "Changelog" }
        for line in text.split(separator: "\n") {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("# ") {
                return String(s.dropFirst(2))
            }
        }
        return "Changelog"
    }

    var changelogBody: String {
        loadChangelogText() ?? ""
    }

    private func loadChangelogText() -> String? {
        let url = Bundle.main.url(forResource: "0.2.99", withExtension: "md", subdirectory: "changelogs")
            ?? Bundle.main.url(forResource: "0.2.99", withExtension: "md")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var availableThemes: [String] {
        GrokTheme.availableThemeNames().filter { $0.lowercased() != "auto" }
    }

    var isThemeDraft: Bool {
        let d = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return d == "/theme" || d.hasPrefix("/theme ") || d == "/t" || d.hasPrefix("/t ")
    }

    var atFileQuery: String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        let fragment = String(draft[draft.index(after: at)...])
        if fragment.contains(" ") || fragment.contains("\n") { return nil }
        return fragment
    }

    var filteredAtFiles: [String] {
        guard let query = atFileQuery?.lowercased() else { return workspaceFiles }
        if query.isEmpty { return workspaceFiles }
        return workspaceFiles
            .filter { $0.lowercased().contains(query) }
            .sorted { a, b in
                let al = a.lowercased(), bl = b.lowercased()
                let ap = al.hasPrefix(query), bp = bl.hasPrefix(query)
                if ap != bp { return ap }
                return al < bl
            }
    }

    @Published private(set) var preferredBonjourEndpoint: NWEndpoint?

    init() {
        // Never honor leftover smoke UserDefaults — wipe if present (polluted sims).
        UserDefaults.standard.removeObject(forKey: "GROK_LIVE_SMOKE_PROMPT")
        UserDefaults.standard.removeObject(forKey: "GROK_LIVE_SMOKE_AUTO_AGENT")

        loadConnectionDrafts()
        wireACP()
        // Always land on Welcome (official pager). Setup is opened from the welcome menu.
        screen = .welcome
    }

    func loadConnectionDrafts() {
        apiKeyDraft = KeychainHelper.loadAPIKey() ?? ""
        let ep = CompanionConfig.resolved()
        acpHostDraft = ep.host
        acpPortDraft = String(ep.port)
        pairPinDraft = CompanionConfig.savedPIN
        fingerprintDraft = CompanionConfig.pinnedFingerprint
    }

    private func wireACP() {
        // Forward ACPClient publishes so AgentStatusBar connection dot refreshes.
        acpBagForward = acp.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        browserBagForward = companionBrowser.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        acp.alwaysApprove = alwaysApprove
        acp.onModelChanged = { [weak self] modelId in
            guard let self else { return }
            self.chrome.modelId = modelId
        }
        acp.onChromeChanged = { [weak self] chrome in
            guard let self else { return }
            var c = chrome
            c.alwaysApprove = self.alwaysApprove
            self.chrome = c
            CompanionConfig.persistWelcomeLocation(
                cwd: c.cwd,
                gitBranch: c.gitBranch,
                isWorktree: c.isWorktree
            )
            if c.sessionId != nil, self.sessionTitle == "loading..." || self.sessionTitle.hasPrefix("session ") {
                self.sessionTitle = c.loadingTitle
            }
        }
        acp.onPermissionRequest = { [weak self] request in
            self?.permissionRequest = request
        }
        acp.onRosterChanged = { [weak self] entries in
            guard let self else { return }
            if self.screen == .dashboard {
                self.applyRosterToDashboard(entries)
            }
        }
        acp.onTransportLost = { [weak self] in
            self?.handleTransportLost()
        }
        acp.tracker.onChange = { [weak self] entries in
            guard let self else { return }
            self.messages = self.acp.tracker.displayEntries(showThinking: self.showThinkingBlocks)
            self.refreshSessionTitle(from: entries)
        }
    }

    /// Upstream session title: first user prompt → `session {8}` → `loading...`
    private func refreshSessionTitle(from entries: [ScrollbackEntry]) {
        if let firstUser = entries.first(where: { $0.kind == .user })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUser.isEmpty {
            let truncated = firstUser.count > 60 ? String(firstUser.prefix(57)) + "…" : firstUser
            sessionTitle = truncated
            return
        }
        if let sid = acp.sessionId, !sid.isEmpty {
            sessionTitle = "session \(sid.prefix(8))"
            return
        }
        sessionTitle = "loading..."
    }

    func showWelcome() {
        companionBrowser.stop()
        screen = .welcome
    }

    func showDashboard() {
        screen = .dashboard
        Task { await reloadDashboardFromSessionList() }
    }

    func startNewSessionFromDashboard() {
        // Upstream `[+ New Agent]` — starts a new agent session.
        startNewSession()
    }

    func openDashboardRow(_ row: DashboardRowModel) {
        if let sid = row.sessionId, !sid.isEmpty {
            resumeSession(id: sid)
        } else {
            showAgent()
        }
    }

    func reloadDashboardFromSessionList() async {
        guard canStartSession else {
            dashboardRows = []
            return
        }
        if !acp.isConnected {
            acp.connect()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let roster = await acp.listRoster()
        if !roster.isEmpty {
            applyRosterToDashboard(roster)
            return
        }
        // Fallback: resume list (idle only) when fleet roster unavailable.
        let entries = await acp.listSessions()
        dashboardRows = entries.map { e in
            let title: String
            if !e.title.isEmpty {
                title = e.title
            } else if !e.cwd.isEmpty {
                title = e.cwd
            } else {
                title = e.id
            }
            return DashboardRowModel(
                sessionId: e.id,
                title: title,
                state: .idle,
                activity: nil,
                ageLabel: nil
            )
        }
    }

    private func applyRosterToDashboard(_ roster: [RosterSessionEntry]) {
        dashboardRows = roster.map { e in
            DashboardRowModel(
                sessionId: e.id,
                title: e.displayTitle,
                state: e.dashboardState,
                activity: e.activity == .working ? "working" : (e.activity == .needsInput ? "awaiting" : nil),
                ageLabel: e.ageLabel
            )
        }
    }

    func renderMermaidPNG(source: String) async -> Data? {
        mermaidRenderError = nil
        do {
            if !acp.isConnected {
                acp.connect()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            return try await acp.renderMermaid(source: source, themeDark: theme.isDark)
        } catch {
            mermaidRenderError = error.localizedDescription
            return nil
        }
    }

    func reloadShellConfig() async {
        guard acp.isPaired || acp.isConnected else { return }
        let values = await acp.fetchShellConfig()
        var bools: [String: Bool] = [:]
        var strings: [String: String] = [:]
        for (k, v) in values {
            if let b = v.boolValue {
                bools[k] = b
            } else if let s = v.stringValue {
                strings[k] = s
            }
        }
        shellConfig = bools
        shellConfigStrings = strings
    }

    func setShellBool(_ key: String, _ value: Bool) async {
        do {
            let updated = try await acp.setShellConfig([key: .bool(value)])
            if let b = updated[key]?.boolValue {
                shellConfig[key] = b
            } else {
                shellConfig[key] = value
            }
            if key == "show_thinking_blocks" {
                showThinkingBlocks = value
                AppSettings.showThinkingBlocks = value
                refreshDisplayedMessages()
            }
            if key == "show_timestamps" {
                showTimestamps = value
                AppSettings.showTimestamps = value
            }
        } catch {
            setupError = error.localizedDescription
        }
    }

    func setShellString(_ key: String, _ value: String) async {
        do {
            let updated = try await acp.setShellConfig([key: .string(value)])
            if let s = updated[key]?.stringValue {
                shellConfigStrings[key] = s
            } else {
                shellConfigStrings[key] = value
            }
        } catch {
            setupError = error.localizedDescription
        }
    }

    func showOnboarding() {
        loadConnectionDrafts()
        setupError = nil
        screen = .onboarding
    }

    func showSettings() {
        screen = .pagerSettings
        Task { await reloadShellConfig() }
    }

    func showCompanionSettings() {
        loadConnectionDrafts()
        setupError = nil
        screen = .settings
    }

    func startLegacyBonjourBrowse() {
        companionBrowser.start()
    }

    func stopLegacyBonjourBrowse() {
        companionBrowser.stop()
    }

    /// Reconnect after background / Wi‑Fi blip — preserves session when possible.
    func reconnectTransportIfNeeded() {
        guard canStartSession else { return }
        guard screen == .agent || screen == .dashboard else { return }
        guard !acp.sessionReady else {
            reconnectBanner = nil
            return
        }
        guard !isReconnecting else { return }
        isReconnecting = true
        reconnectBanner = "Reconnecting…"
        let resumeId = acp.sessionId
        acp.reconnect(preserveSessionId: resumeId)
        Task { @MainActor in
            defer { self.isReconnecting = false }
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if self.acp.sessionReady {
                    self.reconnectBanner = nil
                    return
                }
                if let err = self.acp.lastError, !err.isEmpty {
                    self.reconnectBanner = err
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            self.reconnectBanner = "Could not reconnect — open Setup"
        }
    }

    private func handleTransportLost() {
        guard screen == .agent || screen == .dashboard else { return }
        reconnectBanner = "Disconnected — reconnecting…"
        reconnectTransportIfNeeded()
    }

    func refreshDisplayedMessages() {
        messages = acp.tracker.displayEntries(showThinking: showThinkingBlocks)
    }

    func showThemePicker() {
        screen = .themePicker
    }

    func showSessionPicker() {
        guard canStartSession else { showOnboarding(); return }
        screen = .sessionPicker
    }

    func showChangelog() {
        screen = .changelog
    }

    func refreshSessionList() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        if !acp.isConnected {
            acp.connect()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        sessionListEntries = await acp.listSessions()
    }

    func resumeSession(id: String) {
        guard canStartSession else { showOnboarding(); return }
        screen = .agent
        acp.disconnect()
        acp.tracker.reset()
        if let preferredBonjourEndpoint {
            acp.setPreferredEndpoint(preferredBonjourEndpoint)
        } else {
            acp.setPreferredEndpoint(nil)
        }
        acp.connect()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            do {
                try await self.acp.loadSession(id)
            } catch {
                self.acp.tracker.appendError(error.localizedDescription)
            }
        }
    }

    func showFilePicker() {
        fileFilter = ""
        screen = .filePicker
        Task { await refreshWorkspaceFiles() }
    }

    func selectBonjourPeer(_ peer: CompanionPeer) {
        preferredBonjourEndpoint = peer.endpoint
        acp.setPreferredEndpoint(peer.endpoint)
        if let fp = peer.fingerprint, !fp.isEmpty {
            fingerprintDraft = fp
        }
        CompanionConfig.save(host: "", port: CompanionConfig.resolved().port, useTLS: true, useWebSocket: false)
        acpHostDraft = peer.name
        setupError = nil
        connectionPhase = .idle
    }

    /// Connect with Secret from `grok agent serve` (legacy Bonjour bridge: 6-digit PIN in Advanced).
    func connectWithPINAndVerify() {
        let secret = pairPinDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard secret.count >= 4 else {
            let msg = "Paste the Secret from `grok agent serve`."
            setupError = msg
            connectionPhase = .failed(msg)
            return
        }

        let trimmedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            do {
                try KeychainHelper.saveAPIKey(trimmedKey)
            } catch {
                setupError = error.localizedDescription
                connectionPhase = .failed(error.localizedDescription)
                return
            }
        }

        if preferredBonjourEndpoint == nil {
            if acpHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                acpHostDraft = "127.0.0.1"
            }
            if acpPortDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                acpPortDraft = String(CompanionConfig.defaultWebSocketPort)
            }
            let port = Int(acpPortDraft) ?? CompanionConfig.defaultWebSocketPort
            let host = acpHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            // Primary path: official WebSocket serve (Secret = server-key).
            CompanionConfig.save(host: host, port: port, useTLS: false, useWebSocket: true)
            acp.setPreferredEndpoint(nil)
        } else {
            // Legacy Bonjour TCP+TLS bridge peers.
            CompanionConfig.save(
                host: "",
                port: CompanionConfig.resolved().port,
                useTLS: true,
                useWebSocket: false
            )
        }

        let optionalFP = fingerprintDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        CompanionConfig.savePairing(pin: secret, fingerprint: optionalFP, token: nil)
        setupError = nil
        Task { await verifyCompanionConnection() }
    }

    /// After successful probe — land on Welcome (user taps Continue).
    func finishSetupAfterSuccessfulConnect() {
        guard case .succeeded = connectionPhase else { return }
        CompanionConfig.isOnboarded = true
        companionBrowser.stop()
        // Keep ACP session alive — do not reset tracker/session here.
        connectionPhase = .succeeded
        showWelcome()
    }

    private func verifyCompanionConnection() async {
        connectionPhase = .checking
        setupError = nil
        acp.disconnect()
        acp.tracker.reset()
        if let preferredBonjourEndpoint {
            acp.setPreferredEndpoint(preferredBonjourEndpoint)
        }
        acp.connect()

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if Task.isCancelled { return }
            if let err = acp.lastError, !err.isEmpty {
                connectionPhase = .failed(err)
                setupError = err
                acp.disconnect()
                return
            }
            if acp.sessionReady, acp.sessionId != nil {
                connectionPhase = .succeeded
                setupError = nil
                let pinned = CompanionConfig.pinnedFingerprint
                if !pinned.isEmpty {
                    fingerprintDraft = pinned
                }
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let msg = acp.lastError
            ?? "Could not reach agent — is `grok agent serve` running?"
        connectionPhase = .failed(msg)
        setupError = msg
        acp.disconnect()
    }

    func clearBonjourPreference() {
        preferredBonjourEndpoint = nil
        acp.setPreferredEndpoint(nil)
    }

    func saveAPIKeyOnly() -> Bool {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setupError = "Paste your xAI API key from console.x.ai"
            return false
        }
        do {
            try KeychainHelper.saveAPIKey(trimmed)
            setupError = nil
            return true
        } catch {
            setupError = error.localizedDescription
            return false
        }
    }

    func saveManualCompanion() {
        let port = Int(acpPortDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? CompanionConfig.defaultWebSocketPort
        let host = acpHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        CompanionConfig.save(host: host, port: port, useTLS: false, useWebSocket: true)
        preferredBonjourEndpoint = nil
        acp.setPreferredEndpoint(nil)
    }

    func savePairing() {
        CompanionConfig.savePairing(
            pin: pairPinDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            fingerprint: fingerprintDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            token: CompanionConfig.pairToken
        )
    }

    func completeSetupAndStart() {
        connectWithPINAndVerify()
    }

    func showAgent() {
        guard canStartSession else {
            setupError = "Connect a companion first."
            showOnboarding()
            return
        }
        screen = .agent
        // Reuse live ACP session — tearing down caused red dot + hung prompts.
        if acp.sessionReady {
            return
        }
        acp.disconnect()
        acp.tracker.reset()
        if let preferredBonjourEndpoint {
            acp.setPreferredEndpoint(preferredBonjourEndpoint)
        } else {
            acp.setPreferredEndpoint(nil)
        }
        acp.connect()
    }

    func startNewSession() {
        guard canStartSession else { showOnboarding(); return }
        draft = ""
        // New worktree: fresh scrollback, keep transport if sessionReady; else reconnect.
        if acp.sessionReady {
            acp.tracker.reset()
            messages = []
            sessionTitle = "loading..."
            screen = .agent
            // Request a new ACP session on the same socket.
            Task { await acp.startFreshSession() }
            return
        }
        acp.tracker.reset()
        messages = []
        sessionTitle = "loading..."
        showAgent()
    }

    /// Upstream welcome prompt submit: type a message → enter agent session with that prompt.
    func startSessionFromWelcomePrompt() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard canStartSession else { showOnboarding(); return }
        draft = ""
        acp.tracker.reset()
        showAgent()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.acp.tracker.appendUser(text)
            self.acp.sendPrompt(text)
        }
    }

    /// Upstream welcome "Resume session" (ctrl+s) — session picker UI.
    func resumeSessionFromWelcome() {
        showSessionPicker()
    }

    /// Upstream welcome Quit — return stays on welcome (iOS has no process exit).
    func quitFromWelcome() {
        draft = ""
        acp.disconnect()
        acp.tracker.reset()
        messages = []
        screen = .welcome
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if text.hasPrefix("/") {
            handleSlashCommand(text)
            draft = ""
            return
        }
        if text.contains("@") {
            // In-prompt @ references stay in agent — no FilePicker navigation.
        }

        acp.tracker.appendUser(text)
        draft = ""
        acp.sendPrompt(text)
    }

    func insertFileReference(_ path: String) {
        if let at = draft.lastIndex(of: "@") {
            let prefix = String(draft[..<draft.index(after: at)])
            draft = prefix + path
        } else {
            let ref = path.hasPrefix("@") ? path : "@\(path)"
            draft += (draft.isEmpty ? "" : " ") + ref
        }
        screen = .agent
    }

    func insertAtFile(_ path: String) {
        insertFileReference(path)
    }

    func selectThemeFromDraft(_ name: String) {
        setTheme(name)
        draft = ""
        screen = .agent
    }

    func stopTurn() { acp.stop() }

    func approvePermission(optionId: String) {
        acp.respondToPermission(optionId: optionId)
        permissionRequest = nil
    }

    func selectPermission(optionId: String) {
        let kind = permissionRequest?.options.first(where: { $0.optionId == optionId })?.kind.lowercased() ?? ""
        if kind.contains("allowalways") || kind == "allow_always" {
            alwaysApprove = true
        }
        approvePermission(optionId: optionId)
    }

    func approvePermission(always: Bool) {
        if always { alwaysApprove = true }
        if let req = permissionRequest, !req.options.isEmpty {
            let pick = req.options.first(where: {
                always
                    ? ($0.kind.lowercased().contains("allowalways") || $0.kind == "allow_always")
                    : ($0.kind.lowercased().contains("allowonce") || $0.kind == "allow_once")
            }) ?? req.options.first
            if let pick {
                selectPermission(optionId: pick.optionId)
                return
            }
        }
        acp.respondToPermission(approved: true, alwaysApprove: always)
        permissionRequest = nil
    }

    func denyPermission() {
        if let req = permissionRequest,
           let reject = req.options.first(where: {
               $0.kind.lowercased().contains("reject") || $0.kind.contains("deny")
           }) {
            approvePermission(optionId: reject.optionId)
            return
        }
        acp.respondToPermission(approved: false, alwaysApprove: false)
        permissionRequest = nil
    }

    func toggleTimestamps() {
        showTimestamps.toggle()
        AppSettings.showTimestamps = showTimestamps
    }

    func toggleThinkingBlocks() {
        showThinkingBlocks.toggle()
        AppSettings.showThinkingBlocks = showThinkingBlocks
        messages = acp.tracker.displayEntries(showThinking: showThinkingBlocks)
    }

    func setTheme(_ name: String) {
        themeName = name
    }

    func signOut() {
        KeychainHelper.deleteAPIKey()
        apiKeyDraft = ""
        pairPinDraft = ""
        fingerprintDraft = ""
        CompanionConfig.isOnboarded = false
        CompanionConfig.clearPairing()
        CompanionConfig.save(host: "127.0.0.1", port: CompanionConfig.defaultWebSocketPort, useTLS: false, useWebSocket: true)
        preferredBonjourEndpoint = nil
        acp.setPreferredEndpoint(nil)
        acp.disconnect()
        acp.tracker.reset()
        messages = []
        connectionPhase = .idle
        setupError = nil
        objectWillChange.send()
        showOnboarding()
    }

    func refreshWorkspaceFiles() async {
        workspaceFiles = await acp.listWorkspaceFiles()
        // No invented fake paths when companion returns empty.
    }

    var filteredWorkspaceFiles: [String] {
        let f = fileFilter.lowercased()
        if f.isEmpty { return workspaceFiles }
        return workspaceFiles.filter { $0.lowercased().contains(f) }
    }

    private func handleSlashCommand(_ text: String) {
        let resolved = SlashCommandCatalog.resolve(text)
        let command = resolved.split(separator: " ").first.map(String.init) ?? resolved
        switch command.lowercased() {
        case "/new", "/clear":
            sessionTitle = "loading..."
            acp.disconnect()
            acp.tracker.reset()
            messages = []
            acp.connect()
        case "/theme", "/t":
            draft = command + " "
        case "/timestamps":
            toggleTimestamps()
        case "/settings", "/config", "/preferences", "/prefs":
            if resolved.lowercased().contains("show_thinking_blocks") {
                toggleThinkingBlocks()
            } else {
                showSettings()
            }
        case "/always-approve":
            alwaysApprove.toggle()
            acp.alwaysApprove = alwaysApprove
        case "/home", "/welcome", "/quit", "/exit":
            acp.disconnect()
            showWelcome()
        case "/dashboard":
            showDashboard()
        default:
            // Forward to grok agent (official slash handling lives in the Mac harness).
            acp.tracker.appendUser(resolved)
            acp.sendPrompt(resolved)
        }
    }

    var slashFilter: String? {
        guard draft.hasPrefix("/") else { return nil }
        let body = String(draft.dropFirst())
        return body.isEmpty ? nil : body
    }

    var filteredSlashCommands: [SlashCommand] {
        guard let filter = slashFilter?.lowercased() else { return SlashCommand.builtins }
        return SlashCommand.builtins.filter {
            $0.name.dropFirst().lowercased().contains(filter) || $0.summary.lowercased().contains(filter)
        }
    }
}
