// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network

/// Typed ACP client: TLS pairing → initialize → authenticate → session/new → prompt.
@MainActor
final class ACPClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isPaired = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var sessionId: String?
    @Published private(set) var currentModelId: String?
    /// True after initialize+auth+session/new succeeded.
    @Published private(set) var sessionReady = false

    let tracker = ScrollbackTracker()

    private var connection: NWConnection?
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketSession: URLSession?
    private var receiveBuffer = Data()
    private var requestID = 0
    private var pendingPrompt: String?
    private var pendingPermissionID: ACPProtocol.JSONValue?
    private var lastTurnActivity: String?
    private var turnTokenBaseline: Int?
    private var preferredEndpoint: NWEndpoint?
    private var pendingRequests: [Int: CheckedContinuation<ACPProtocol.JSONRPCResponse, Error>] = [:]
    private var handshakeTask: Task<Void, Never>?
    private var connectTimeoutTask: Task<Void, Never>?
    private var lineWaiter: CheckedContinuation<String, Error>?
    /// TOFU: leaf fingerprint observed during TLS (persisted only after PIN succeeds).
    private let tlsFingerprintCapture = TLSFingerprintCapture()

    var alwaysApprove = false

    var onModelChanged: ((String) -> Void)?
    var onPermissionRequest: ((PermissionRequest) -> Void)?
    var onChromeChanged: ((SessionChrome) -> Void)?
    var onRosterChanged: (([RosterSessionEntry]) -> Void)?
    var onTransportLost: (() -> Void)?

    private var preserveSessionIdOnReconnect: String?
    private var receiveLoopActive = false

    private(set) var chrome = SessionChrome()
    private var rosterById: [String: RosterSessionEntry] = [:]

    func setPreferredEndpoint(_ endpoint: NWEndpoint?) {
        preferredEndpoint = endpoint
    }

    func connect() {
        if connection != nil || webSocketTask != nil {
            return
        }
        lastError = nil
        sessionReady = false
        isPaired = false
        receiveBuffer = Data()
        receiveLoopActive = false

        let ep = CompanionConfig.resolved()
        if ep.useWebSocket {
            connectWebSocket(ep: ep)
            return
        }

        tlsFingerprintCapture.clear()
        if let preferred = preferredEndpoint {
            let params = CompanionTLS.connectionParameters(
                useTLS: ep.useTLS,
                pinnedFingerprint: CompanionConfig.pinnedFingerprint.nilIfEmpty,
                capture: tlsFingerprintCapture
            )
            connection = NWConnection(to: preferred, using: params)
            startConnection()
            return
        }

        guard !ep.host.isEmpty else {
            fail("Could not reach companion")
            return
        }
        guard let port = NWEndpoint.Port(rawValue: UInt16(ep.port)) else {
            fail("Could not reach companion")
            return
        }
        let params = CompanionTLS.connectionParameters(
            useTLS: ep.useTLS,
            pinnedFingerprint: CompanionConfig.pinnedFingerprint.nilIfEmpty,
            capture: tlsFingerprintCapture
        )
        let host = NWEndpoint.Host(ep.host)
        connection = NWConnection(host: host, port: port, using: params)
        startConnection()
    }

    /// Official `grok agent serve` — ACP over WebSocket, auth via `server-key` (= Secret printed by CLI).
    private func connectWebSocket(ep: CompanionConfig.Endpoint) {
        let secret = CompanionConfig.savedPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            fail("Enter the Secret from `grok agent serve`")
            return
        }
        var components = URLComponents()
        components.scheme = "ws"
        components.host = ep.host
        components.port = ep.port
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "server-key", value: secret)]
        guard let url = components.url else {
            fail("Could not reach companion")
            return
        }

        let session = URLSession(configuration: .default)
        webSocketSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task

        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.isConnected else { return }
            self.fail("Could not reach companion — is `grok agent serve` running?")
        }

        task.resume()
        receiveLoopActive = true
        receiveWebSocketLoop()
        handshakeTask = Task { await self.runConnectPipeline() }
    }

    /// Drop transport and reconnect; optionally resume the prior ACP session.
    func reconnect(preserveSessionId sessionId: String?) {
        preserveSessionIdOnReconnect = sessionId
        teardownTransport()
        connect()
    }

    private func teardownTransport() {
        handshakeTask?.cancel()
        handshakeTask = nil
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        for (_, cont) in pendingRequests {
            cont.resume(throwing: ACPClientError.cancelled)
        }
        pendingRequests.removeAll()
        if let waiter = lineWaiter {
            lineWaiter = nil
            waiter.resume(throwing: ACPClientError.cancelled)
        }
        receiveLoopActive = false
        connection?.cancel()
        connection = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
        isConnected = false
        isPaired = false
        isRunning = false
        sessionReady = false
        pendingPrompt = nil
        pendingPermissionID = nil
    }

    private func startConnection() {
        guard let conn = connection else { return }
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.isConnected else { return }
            self.fail("Could not reach companion")
        }
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.connectTimeoutTask?.cancel()
                    self.connectTimeoutTask = nil
                    self.isConnected = true
                    self.receiveLoop()
                    self.handshakeTask = Task { await self.runConnectPipeline() }
                case .waiting:
                    break
                case .failed:
                    self.fail("Could not reach companion")
                case .cancelled:
                    self.isConnected = false
                    self.connection = nil
                    self.sessionReady = false
                default:
                    break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        preserveSessionIdOnReconnect = nil
        teardownTransport()
        sessionId = nil
    }

    func sendPrompt(_ text: String) {
        guard !text.isEmpty else { return }
        isRunning = true
        chrome.turnStartedAt = Date()
        chrome.phaseStartedAt = Date()
        chrome.turnTokensUsed = nil
        turnTokenBaseline = chrome.contextUsed
        lastTurnActivity = chrome.turnActivity
        tracker.finalizeStreaming()
        if sessionReady, sessionId != nil {
            Task { await sendSessionPrompt(text) }
        } else {
            pendingPrompt = text
            if (connection != nil || webSocketTask != nil), !isConnected {
                disconnect()
            }
            connect()
        }
    }

    func stop() {
        Task {
            var params: [String: ACPProtocol.JSONValue] = [:]
            if let sessionId { params["sessionId"] = .string(sessionId) }
            _ = try? await sendRPC(method: "session/cancel", params: .object(params))
            tracker.finalizeStreaming()
            isRunning = false
            clearTurnTimers()
        }
    }

    private func clearTurnTimers() {
        chrome.turnStartedAt = nil
        chrome.phaseStartedAt = nil
        chrome.turnTokensUsed = nil
        chrome.turnActivity = nil
        turnTokenBaseline = nil
        lastTurnActivity = nil
        publishChrome()
    }

    private func setTurnActivity(_ activity: String?) {
        if activity != lastTurnActivity {
            chrome.phaseStartedAt = Date()
            lastTurnActivity = activity
        }
        chrome.turnActivity = activity
        publishChrome()
    }

    func respondToPermission(optionId: String) {
        guard let pendingPermissionID else { return }
        let reply = ACPProtocol.permissionReply(id: pendingPermissionID, optionId: optionId)
        guard let data = ACPProtocol.encodeLine(reply) else { return }
        Task { try? await sendRaw(data) }
        self.pendingPermissionID = nil
    }

    func respondToPermission(approved: Bool, alwaysApprove: Bool) {
        guard let pendingPermissionID else { return }
        let reply = ACPProtocol.permissionReply(
            id: pendingPermissionID,
            approved: approved,
            alwaysApprove: alwaysApprove
        )
        guard let data = ACPProtocol.encodeLine(reply) else { return }
        Task { try? await sendRaw(data) }
        self.pendingPermissionID = nil
    }

    func listSessions() async -> [SessionListEntry] {
        guard isPaired else { return [] }
        do {
            let resp = try await sendRPC(
                method: "x.ai/session/list",
                params: .object([:])
            )
            guard let result = resp.result else { return [] }
            let payload = result["data"]?.objectValue ?? result.objectValue ?? [:]
            guard let sessions = payload["sessions"]?.arrayValue ?? result["sessions"]?.arrayValue else {
                return []
            }
            return sessions.compactMap { parseSessionListEntry($0) }
        } catch {
            return []
        }
    }

    /// Live fleet roster (`x.ai/sessions/list`) — dashboard activity glyphs.
    func listRoster() async -> [RosterSessionEntry] {
        guard isPaired else { return [] }
        do {
            let resp = try await sendRPC(
                method: ACPProtocol.sessionsListMethod,
                params: .object([:])
            )
            guard let sessions = resp.result?["sessions"]?.arrayValue else { return [] }
            let entries = sessions.compactMap { parseRosterEntry($0) }
            for e in entries { rosterById[e.id] = e }
            return entries
        } catch {
            return []
        }
    }

    func loadSession(_ sessionId: String) async throws {
        _ = try await sendRPC(
            method: "session/load",
            params: ACPProtocol.sessionLoadParams(sessionId: sessionId)
        )
        self.sessionId = sessionId
        sessionReady = true
        chrome.sessionId = sessionId
        publishChrome()
        await refreshSessionInfo()
        await refreshBilling()
    }

    func renderMermaid(source: String, themeDark: Bool) async throws -> Data {
        let resp = try await sendRPC(
            method: ACPProtocol.companionMermaidRenderMethod,
            params: .object([
                "source": .string(source),
                "theme": .string(themeDark ? "dark" : "light"),
                "quality": .string("open"),
                "width": .int(960),
            ])
        )
        guard let b64 = resp.result?["pngBase64"]?.stringValue,
              let data = Data(base64Encoded: b64) else {
            throw ACPClientError.rpc("mermaid render returned no PNG")
        }
        return data
    }

    func fetchShellConfig() async -> [String: ACPProtocol.JSONValue] {
        guard isPaired else { return [:] }
        do {
            let resp = try await sendRPC(
                method: ACPProtocol.companionConfigGetMethod,
                params: .object([:])
            )
            return resp.result?["values"]?.objectValue ?? [:]
        } catch {
            return [:]
        }
    }

    func setShellConfig(_ values: [String: ACPProtocol.JSONValue]) async throws -> [String: ACPProtocol.JSONValue] {
        let resp = try await sendRPC(
            method: ACPProtocol.companionConfigSetMethod,
            params: .object(["values": .object(values)])
        )
        return resp.result?["values"]?.objectValue ?? [:]
    }

    func refreshBilling() async {
        guard isPaired else { return }
        do {
            let resp = try await sendRPC(method: ACPProtocol.billingMethod, params: .object([:]))
            applyBillingResult(resp.result)
        } catch {
            // Billing is optional — many sessions omit the extension.
        }
    }

    private func parseSessionListEntry(_ value: ACPProtocol.JSONValue) -> SessionListEntry? {
        guard case .object(let obj) = value else { return nil }
        let id = obj["sessionId"]?.stringValue ?? obj["session_id"]?.stringValue
        guard let id, !id.isEmpty else { return nil }
        let summary = obj["summary"]?.stringValue ?? ""
        let firstPrompt = obj["firstPrompt"]?.stringValue ?? obj["first_prompt"]?.stringValue ?? ""
        let title: String
        if !summary.isEmpty {
            title = summary
        } else if !firstPrompt.isEmpty {
            title = String(firstPrompt.prefix(80))
        } else {
            title = "session \(id.prefix(8))"
        }
        let cwd = obj["cwd"]?.stringValue ?? ""
        return SessionListEntry(id: id, title: title, cwd: cwd)
    }

    private func parseRosterEntry(_ value: ACPProtocol.JSONValue) -> RosterSessionEntry? {
        guard case .object(let obj) = value else { return nil }
        let id = obj["sessionId"]?.stringValue ?? obj["session_id"]?.stringValue
        guard let id, !id.isEmpty else { return nil }
        let title = obj["title"]?.stringValue
        let cwd = obj["cwd"]?.stringValue ?? ""
        let activityRaw = (obj["activity"]?.stringValue ?? "idle").lowercased()
        let activity: RosterSessionEntry.Activity
        switch activityRaw {
        case "working": activity = .working
        case "needs_input", "needsinput": activity = .needsInput
        case "dormant": activity = .dormant
        case "completed": activity = .completed
        case "dead": activity = .dead
        default: activity = .idle
        }
        let lastMs = obj["lastChangeUnixMs"]?.intValue
            ?? obj["last_change_unix_ms"]?.intValue
        return RosterSessionEntry(
            id: id,
            title: title,
            cwd: cwd,
            activity: activity,
            lastChangeUnixMs: lastMs.map { Int64($0) }
        )
    }

    func listWorkspaceFiles() async -> [String] {
        guard isPaired else { return [] }
        do {
            let resp = try await sendRPC(
                method: ACPProtocol.workspaceListMethod,
                params: .object(["cwd": .string(".")])
            )
            guard let files = resp.result?["files"], case .array(let arr) = files else { return [] }
            return arr.compactMap { $0.stringValue }
        } catch {
            return []
        }
    }

    /// New worktree on an already-open transport — `session/new` without reconnect.
    func startFreshSession() async {
        guard isConnected, isPaired else {
            connect()
            return
        }
        isRunning = false
        pendingPrompt = nil
        do {
            let sessionResp = try await sendRPC(method: "session/new", params: ACPProtocol.sessionNewParams())
            guard let result = sessionResp.result,
                  let sid = result["sessionId"]?.stringValue else {
                throw ACPClientError.handshakeFailed("No sessionId")
            }
            sessionId = sid
            sessionReady = true
            chrome.sessionId = sid
            let buildModel = ACPProtocol.preferredBuildModelId
            _ = try? await sendRPC(
                method: "session/set_model",
                params: ACPProtocol.sessionSetModelParams(sessionId: sid, modelId: buildModel)
            )
            currentModelId = buildModel
            chrome.modelId = buildModel
            onModelChanged?(buildModel)
            if let obj = result.objectValue {
                applyContextWindow(from: obj)
            }
            if let cwd = result["cwd"]?.stringValue, !cwd.isEmpty {
                chrome.cwd = cwd
            }
            publishChrome()
            await refreshSessionInfo()
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Pipeline

    private func runConnectPipeline() async {
        do {
            let ep = CompanionConfig.resolved()
            if ep.useWebSocket {
                // Official `grok agent serve`: auth is `server-key` on the WS URL — no grok_pair.
                isPaired = true
            } else {
                let hasPin = !CompanionConfig.savedPIN.isEmpty
                let hasToken = CompanionConfig.pairToken != nil
                if hasPin || hasToken {
                    try await performPairing()
                    if let observed = tlsFingerprintCapture.fingerprint,
                       CompanionConfig.pinnedFingerprint.isEmpty {
                        CompanionConfig.pinnedFingerprint = observed
                    }
                } else if ep.useTLS {
                    throw ACPClientError.pairingRequired
                } else {
                    isPaired = true
                }
            }
            _ = try await sendRPC(method: "initialize", params: ACPProtocol.initializeParams())
            let key = KeychainHelper.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await sendRPC(method: "authenticate", params: ACPProtocol.authenticateParams(apiKey: key))

            if let resumeId = preserveSessionIdOnReconnect, !resumeId.isEmpty {
                preserveSessionIdOnReconnect = nil
                try await loadSession(resumeId)
            } else {
                let sessionResp = try await sendRPC(method: "session/new", params: ACPProtocol.sessionNewParams())
                guard let result = sessionResp.result,
                      let sid = result["sessionId"]?.stringValue else {
                    throw ACPClientError.handshakeFailed("No sessionId")
                }
                sessionId = sid
                sessionReady = true
                chrome.sessionId = sid
                if let models = result["models"]?.objectValue,
                   let mid = models["currentModelId"]?.stringValue {
                    currentModelId = mid
                    chrome.modelId = mid
                    onModelChanged?(mid)
                }
                let buildModel = ACPProtocol.preferredBuildModelId
                _ = try? await sendRPC(
                    method: "session/set_model",
                    params: ACPProtocol.sessionSetModelParams(sessionId: sid, modelId: buildModel)
                )
                currentModelId = buildModel
                chrome.modelId = buildModel
                onModelChanged?(buildModel)
                if let obj = result.objectValue {
                    applyContextWindow(from: obj)
                }
                if let cwd = result["cwd"]?.stringValue, !cwd.isEmpty {
                    chrome.cwd = cwd
                }
                publishChrome()
                await refreshSessionInfo()
                await refreshBilling()
            }

            isConnected = true
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            if let pending = pendingPrompt {
                pendingPrompt = nil
                chrome.turnActivity = "Thinking…"
                publishChrome()
                await sendSessionPrompt(pending)
            }
        } catch {
            if error is CancellationError || (error as? ACPClientError) == .cancelled {
                return
            }
            fail(error.localizedDescription)
        }
    }

    private func performPairing() async throws {
        let pin = CompanionConfig.savedPIN
        let token = CompanionConfig.pairToken
        var body = ACPProtocol.PairBody()
        if let token, !token.isEmpty {
            body.token = token
        } else if !pin.isEmpty {
            body.pin = pin
        } else {
            throw ACPClientError.pairingRequired
        }
        let req = ACPProtocol.PairRequest(grok_pair: body)
        guard let data = ACPProtocol.encodeLine(req) else {
            throw ACPClientError.encodeFailed
        }
        try await sendRaw(data)
        let line = try await awaitLine(timeout: 10)
        guard let result = ACPProtocol.decodePairResult(line) else {
            throw ACPClientError.pairingFailed("Invalid pair response")
        }
        guard result.ok else {
            throw ACPClientError.pairingFailed(result.error ?? "Pairing rejected")
        }
        if let newToken = result.token {
            CompanionConfig.pairToken = newToken
        }
        isPaired = true
    }

    private func sendSessionPrompt(_ text: String) async {
        guard let sessionId else {
            tracker.appendError("No ACP session yet")
            isRunning = false
            return
        }
        do {
            let id = nextID()
            let req = ACPProtocol.JSONRPCRequest(
                method: "session/prompt",
                params: ACPProtocol.sessionPromptParams(sessionId: sessionId, text: text),
                id: id
            )
            guard let data = ACPProtocol.encodeLine(req) else { throw ACPClientError.encodeFailed }
            try await sendRaw(data)
            chrome.turnActivity = "Thinking…"
            chrome.turnStartedAt = chrome.turnStartedAt ?? Date()
            chrome.phaseStartedAt = chrome.phaseStartedAt ?? Date()
            publishChrome()
        } catch {
            tracker.appendError(error.localizedDescription)
            isRunning = false
            chrome.turnActivity = nil
            publishChrome()
        }
    }

    private func refreshSessionInfo() async {
        guard let sessionId else { return }
        do {
            let resp = try await sendRPC(
                method: "x.ai/session/info",
                params: .object(["sessionId": .string(sessionId)])
            )
            guard let result = resp.result else { return }
            let data = result["data"]?.objectValue ?? result.objectValue ?? [:]
            if let cwd = data["cwd"]?.stringValue ?? result["cwd"]?.stringValue, !cwd.isEmpty {
                chrome.cwd = cwd
            }
            if let model = data["model"]?.stringValue
                ?? data["resolvedModelId"]?.stringValue
                ?? data["modelDisplayName"]?.stringValue
                ?? result["model"]?.stringValue {
                chrome.modelId = model
                currentModelId = model
                onModelChanged?(model)
            }
            if let effort = data["reasoningEffort"]?.stringValue
                ?? data["reasoning_effort"]?.stringValue
                ?? data["effort"]?.stringValue {
                chrome.modelEffort = effort
            }
            if let ctx = data["context"]?.objectValue ?? result["context"]?.objectValue {
                chrome.contextUsed = ctx["used"]?.intValue
                if let total = ctx["total"]?.intValue, total > 0 {
                    chrome.contextTotal = total
                }
            }
            applyContextWindow(from: data)
            if let obj = result.objectValue {
                applyContextWindow(from: obj)
            }
            publishChrome()
        } catch {
            // Extension optional.
        }
    }

    private func publishChrome() {
        chrome.alwaysApprove = alwaysApprove
        onChromeChanged?(chrome)
    }

    // MARK: - RPC

    private func nextID() -> Int {
        requestID += 1
        return requestID
    }

    private func sendRPC(method: String, params: ACPProtocol.JSONValue) async throws -> ACPProtocol.JSONRPCResponse {
        let id = nextID()
        let req = ACPProtocol.JSONRPCRequest(method: method, params: params, id: id)
        guard let data = ACPProtocol.encodeLine(req) else { throw ACPClientError.encodeFailed }
        try await sendRaw(data)
        return try await withCheckedThrowingContinuation { cont in
            pendingRequests[id] = cont
        }
    }

    private func sendRaw(_ data: Data) async throws {
        if let ws = webSocketTask {
            guard let text = String(data: data, encoding: .utf8) else {
                throw ACPClientError.encodeFailed
            }
            // Official serve strips trailing newlines from WS text frames.
            let payload = text.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            try await ws.send(.string(payload))
            return
        }
        guard let connection else { throw ACPClientError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    /// Official `grok agent serve` delivers one JSON-RPC message per WS text frame.
    private func receiveWebSocketLoop() {
        guard receiveLoopActive, let task = webSocketTask else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.receiveLoopActive else { return }
                switch result {
                case .failure:
                    self.handleTransportDrop()
                case .success(let message):
                    switch message {
                    case .string(let text):
                        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
                        if trimmed != "ping", !trimmed.isEmpty {
                            self.handleLine(trimmed)
                        }
                    case .data(let data):
                        if let s = String(data: data, encoding: .utf8) {
                            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
                            if trimmed != "ping", !trimmed.isEmpty {
                                self.handleLine(trimmed)
                            }
                        }
                    @unknown default:
                        break
                    }
                    self.receiveWebSocketLoop()
                }
            }
        }
    }

    private func handleTransportDrop() {
        let wasReady = sessionReady
        let priorSession = sessionId
        teardownTransport()
        sessionId = priorSession
        sessionReady = false
        if wasReady {
            preserveSessionIdOnReconnect = priorSession
            onTransportLost?()
        }
    }

    private func awaitLine(timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    Task { @MainActor in
                        self.lineWaiter = cont
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ACPClientError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Receive

    private func receiveLoop() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty { self.receiveBuffer.append(data); self.processBuffer() }
                if error != nil || isComplete {
                    self.handleTransportDrop()
                    return
                }
                self.receiveLoop()
            }
        }
    }

    private func processBuffer() {
        while let line = extractLine() {
            handleLine(line)
        }
    }

    private func extractLine() -> String? {
        guard let range = receiveBuffer.firstRange(of: Data([0x0A])) else { return nil }
        let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<range.lowerBound)
        receiveBuffer.removeSubrange(receiveBuffer.startIndex...range.lowerBound)
        return String(data: lineData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func handleLine(_ line: String) {
        if let waiter = lineWaiter {
            lineWaiter = nil
            waiter.resume(returning: line)
            return
        }
        if line.contains(ACPProtocol.pairResultPrefix) {
            return
        }
        guard let msg = ACPProtocol.decodeLine(line) else { return }

        if let method = msg.method {
            if method == "session/update" || method.hasSuffix("/session_notification") {
                if let params = msg.params?.objectValue {
                    applyNotificationMeta(params["_meta"]?.objectValue)
                    if let update = params["update"]?.objectValue {
                        let kind = update["sessionUpdate"]?.stringValue ?? ""
                        if kind == "current_mode_update" || kind == "currentModeUpdate" {
                            let modeId = update["currentModeId"]?.stringValue
                                ?? update["modeId"]?.stringValue
                                ?? ""
                            chrome.planMode = modeId.lowercased().contains("plan")
                            publishChrome()
                        } else if kind == "model_changed" || kind == "modelChanged" {
                            if let model = update["model_id"]?.stringValue
                                ?? update["modelId"]?.stringValue
                                ?? update["currentModelId"]?.stringValue {
                                chrome.modelId = model
                                currentModelId = model
                                onModelChanged?(model)
                            }
                            if let effort = update["reasoning_effort"]?.stringValue
                                ?? update["reasoningEffort"]?.stringValue
                                ?? update["effort"]?.stringValue {
                                chrome.modelEffort = effort
                            }
                            publishChrome()
                        } else if kind == "goal_updated" || kind == "goalUpdated" {
                            applyGoalUpdate(update)
                        } else {
                            if kind == "tool_call" {
                                let title = update["title"]?.stringValue ?? ""
                                if !title.isEmpty {
                                    setTurnActivity(title)
                                }
                            } else if kind == "agent_thought_chunk" {
                                setTurnActivity("Thinking…")
                            } else if kind == "agent_message_chunk" {
                                setTurnActivity("Responding…")
                            }
                            tracker.handleSessionUpdate(update)
                        }
                    }
                }
            } else if method == "x.ai/git_head_changed" {
                if let params = msg.params?.objectValue {
                    chrome.gitBranch = params["branch"]?.stringValue
                    chrome.isWorktree = params["isWorktree"]?.boolValue ?? false
                    chrome.mainRepo = params["mainRepo"]?.stringValue
                    publishChrome()
                }
            } else if method == "x.ai/queue/changed" {
                // Upstream turn_status queue hint — entries[] length when present.
                if let params = msg.params?.objectValue {
                    let entries = params["entries"]?.arrayValue ?? []
                    chrome.queuedPromptCount = entries.count
                    publishChrome()
                }
            } else if method == "x.ai/mcp/init_progress" {
                if let params = msg.params?.objectValue {
                    chrome.mcpTotal = params["total"]?.intValue
                    chrome.mcpConnected = params["connected"]?.intValue
                    publishChrome()
                }
            } else if method == "x.ai/mcp_initialized" {
                chrome.mcpTotal = nil
                chrome.mcpConnected = nil
                publishChrome()
            } else if method == "x.ai/sessions/changed" {
                if let params = msg.params?.objectValue {
                    applyRosterChanged(params)
                }
            } else if method == "x.ai/settings/update" {
                // Remote settings snapshot — subscription tier / gates only when present.
                if let params = msg.params?.objectValue,
                   let tier = params["subscription_tier_display"]?.stringValue
                    ?? params["subscriptionTierDisplay"]?.stringValue,
                   !tier.isEmpty {
                    // Tier alone is not a credits chip; billing poll owns percent.
                    _ = tier
                }
            } else if method == "session/request_permission" {
                pendingPermissionID = msg.id
                let params = msg.params?.objectValue
                let toolCall = params?["toolCall"]?.objectValue
                let title = permissionTitle(toolCall: toolCall)
                let options = parsePermissionOptions(params?["options"])
                setTurnActivity("Waiting…")
                if alwaysApprove {
                    if let pick = autoApproveOption(from: options) {
                        respondToPermission(optionId: pick)
                    } else {
                        respondToPermission(approved: true, alwaysApprove: true)
                    }
                } else {
                    onPermissionRequest?(PermissionRequest(
                        message: title,
                        title: toolCall?["title"]?.stringValue,
                        options: options,
                        requestId: msg.id
                    ))
                }
            }
            return
        }

        if let idVal = msg.id {
            let id: Int?
            switch idVal {
            case .int(let i): id = i
            case .string(let s): id = Int(s)
            default: id = nil
            }
            if let id, let cont = pendingRequests.removeValue(forKey: id) {
                if let error = msg.error {
                    let parts = [error.message, error.data].compactMap { $0 }.filter { !$0.isEmpty }
                    cont.resume(throwing: ACPClientError.rpc(parts.joined(separator: ": ")))
                } else {
                    cont.resume(returning: msg)
                }
            }
            // session/prompt result carries stopReason even if id type mismatched above.
            if let stop = msg.result?["stopReason"]?.stringValue, !stop.isEmpty {
                tracker.finalizeStreaming()
                tracker.collapseFinishedThoughts()
                isRunning = false
                clearTurnTimers()
                Task { await refreshSessionInfo() }
            }
            return
        }
    }

    private func applyNotificationMeta(_ meta: [String: ACPProtocol.JSONValue]?) {
        guard let meta else { return }
        if let used = meta["totalTokens"]?.intValue {
            chrome.contextUsed = used
            if isRunning {
                if let baseline = turnTokenBaseline {
                    chrome.turnTokensUsed = max(0, used - baseline)
                } else {
                    chrome.turnTokensUsed = used
                }
            }
            publishChrome()
        }
    }

    private func applyGoalUpdate(_ update: [String: ACPProtocol.JSONValue]) {
        let status = (update["status"]?.stringValue ?? "").lowercased()
        let phase = (update["phase"]?.stringValue ?? "").lowercased()
        if status == "cleared" || status == "complete" {
            chrome.goalPhaseLabel = nil
            chrome.goalActive = false
            publishChrome()
            return
        }
        let label: String
        switch phase {
        case "planning": label = "Planning"
        case "executing": label = "Executing"
        case "idle": label = "Idle"
        default:
            if status.contains("pause") {
                label = "Paused"
            } else if !status.isEmpty {
                label = status.replacingOccurrences(of: "_", with: " ").capitalized
            } else {
                label = "Active"
            }
        }
        chrome.goalPhaseLabel = label
        chrome.goalActive = status == "active" || status.isEmpty
        publishChrome()
    }

    private func applyBillingResult(_ result: ACPProtocol.JSONValue?) {
        guard let result else { return }
        let config = result["config"]?.objectValue ?? result.objectValue
        guard let config else { return }
        if let pct = config["creditUsagePercent"]?.doubleValue
            ?? config["credit_usage_percent"]?.doubleValue
            ?? config["usagePct"]?.doubleValue {
            chrome.creditsUsedPercent = pct
            publishChrome()
        }
    }

    private func applyRosterChanged(_ params: [String: ACPProtocol.JSONValue]) {
        if let removed = params["removed"]?.arrayValue {
            for idVal in removed {
                if let id = idVal.stringValue {
                    rosterById.removeValue(forKey: id)
                }
            }
        }
        if let upserted = params["upserted"]?.arrayValue {
            for item in upserted {
                if let entry = parseRosterEntry(item) {
                    rosterById[entry.id] = entry
                }
            }
        }
        let sorted = rosterById.values.sorted { a, b in
            (a.lastChangeUnixMs ?? 0) > (b.lastChangeUnixMs ?? 0)
        }
        onRosterChanged?(sorted)
    }

    /// Upstream `acp_handler/permissions.rs` title patterns.
    private func permissionTitle(toolCall: [String: ACPProtocol.JSONValue]?) -> String {
        guard let toolCall else { return "Allow?" }
        if let title = toolCall["title"]?.stringValue, !title.isEmpty {
            return "Allow \(title)?"
        }
        let kind = (toolCall["kind"]?.stringValue ?? "").lowercased()
        switch kind {
        case "edit": return "Allow Edit?"
        case "execute": return "Allow Execute?"
        case "delete": return "Allow Delete?"
        default: return "Allow?"
        }
    }

    private func parsePermissionOptions(_ value: ACPProtocol.JSONValue?) -> [PermissionOption] {
        guard let value, case .array(let arr) = value else { return [] }
        return arr.compactMap { item -> PermissionOption? in
            guard case .object(let obj) = item else { return nil }
            let optionId = obj["optionId"]?.stringValue ?? obj["option_id"]?.stringValue
            let name = obj["name"]?.stringValue
            let kind = obj["kind"]?.stringValue ?? ""
            guard let optionId, let name else { return nil }
            return PermissionOption(optionId: optionId, name: name, kind: kind)
        }
    }

    private func autoApproveOption(from options: [PermissionOption]) -> String? {
        if let always = options.first(where: {
            $0.kind.lowercased().contains("allowalways") || $0.kind == "allow_always"
        }) {
            return always.optionId
        }
        if let once = options.first(where: {
            $0.kind.lowercased().contains("allowonce") || $0.kind == "allow_once"
        }) {
            return once.optionId
        }
        return options.first?.optionId
    }

    /// Pull context window from session/new or session/info payloads when present.
    private func applyContextWindow(from result: [String: ACPProtocol.JSONValue]) {
        if let models = result["models"]?.objectValue {
            if let cw = models["contextWindow"]?.intValue
                ?? models["context_window"]?.intValue
                ?? models["contextWindowTokens"]?.intValue,
               cw > 0 {
                chrome.contextTotal = cw
            }
            // availableModels[{id}].contextWindow
            if chrome.contextTotal == nil,
               let mid = models["currentModelId"]?.stringValue,
               let avail = models["availableModels"]?.objectValue
                ?? models["available_models"]?.objectValue,
               let entry = avail[mid]?.objectValue,
               let cw = entry["contextWindow"]?.intValue
                ?? entry["context_window"]?.intValue
                ?? entry["contextWindowTokens"]?.intValue,
               cw > 0 {
                chrome.contextTotal = cw
            }
        }
        if let cw = result["contextWindowTokens"]?.intValue
            ?? result["context_window_tokens"]?.intValue,
           cw > 0 {
            chrome.contextTotal = cw
        }
    }

    private func fail(_ message: String, showInScrollback: Bool = false) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        handshakeTask?.cancel()
        handshakeTask = nil
        lastError = message
        isRunning = false
        sessionReady = false
        chrome.turnActivity = nil
        publishChrome()
        teardownTransport()
        if showInScrollback {
            tracker.appendError(message)
        }
    }
}

enum ACPClientError: LocalizedError, Equatable {
    case notConnected
    case encodeFailed
    case handshakeFailed(String)
    case pairingRequired
    case pairingFailed(String)
    case timeout
    case cancelled
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .encodeFailed: return "Failed to encode request"
        case .handshakeFailed(let m): return m
        case .pairingRequired: return "Paste the Secret from `grok agent serve`"
        case .pairingFailed(let m): return m
        case .timeout: return "Companion timed out"
        case .cancelled: return "Cancelled"
        case .rpc(let m): return m
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
