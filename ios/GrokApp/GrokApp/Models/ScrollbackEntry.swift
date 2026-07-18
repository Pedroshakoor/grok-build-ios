// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum ScrollbackKind: String, Codable, Equatable {
    case user
    case assistant
    case thinking
    case tool
    case diff
    case plan
    case error
    case system
    case verbGroup
}

/// Upstream `DisplayMode` for thinking/tool fold (`scrollback/types.rs`).
enum ThinkingDisplayMode: String, Equatable {
    case collapsed
    case truncated
    case expanded
}

struct ScrollbackEntry: Identifiable, Equatable {
    let id: UUID
    let kind: ScrollbackKind
    var text: String
    let timestamp: Date
    var isStreaming: Bool
    var isCollapsed: Bool
    /// Thinking only — mirrors upstream DisplayMode (default Truncated while running).
    var thinkingMode: ThinkingDisplayMode
    var toolTitle: String?
    var toolKind: String?
    var toolStatus: String?
    var toolDetail: String?
    var toolCallId: String?
    var diffHunks: [DiffHunk]?
    /// Upstream ThinkingBlock elapsed (ms) for "Thought for Xs".
    var thoughtElapsedMs: Int64?
    var thoughtStartedAt: Date?

    init(
        id: UUID = UUID(),
        kind: ScrollbackKind,
        text: String,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        isCollapsed: Bool = false,
        thinkingMode: ThinkingDisplayMode = .collapsed,
        toolTitle: String? = nil,
        toolKind: String? = nil,
        toolStatus: String? = nil,
        toolDetail: String? = nil,
        toolCallId: String? = nil,
        diffHunks: [DiffHunk]? = nil,
        thoughtElapsedMs: Int64? = nil,
        thoughtStartedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.isCollapsed = isCollapsed
        self.thinkingMode = thinkingMode
        self.toolTitle = toolTitle
        self.toolKind = toolKind
        self.toolStatus = toolStatus
        self.toolDetail = toolDetail
        self.toolCallId = toolCallId
        self.diffHunks = diffHunks
        self.thoughtElapsedMs = thoughtElapsedMs
        self.thoughtStartedAt = thoughtStartedAt
    }
}

struct SlashCommand: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let aliases: [String]

    init(id: String, name: String, summary: String, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.aliases = aliases
    }

    static let fallback: [SlashCommand] = [
        SlashCommand(id: "new", name: "/new", summary: "Start a new session", aliases: ["clear"]),
        SlashCommand(id: "resume", name: "/resume", summary: "Resume a previous session"),
        SlashCommand(id: "theme", name: "/theme", summary: "Switch theme", aliases: ["t"]),
        SlashCommand(id: "settings", name: "/settings", summary: "Open settings", aliases: ["config"]),
        SlashCommand(id: "always-approve", name: "/always-approve", summary: "Toggle always-approve"),
        SlashCommand(id: "plan", name: "/plan", summary: "Toggle plan mode"),
        SlashCommand(id: "quit", name: "/quit", summary: "Background the app", aliases: ["exit"]),
    ]

    static var builtins: [SlashCommand] { SlashCommandCatalog.builtins }
}

enum AppScreen: Equatable {
    case welcome
    case onboarding
    case settings
    case pagerSettings
    case agent
    case dashboard
    case themePicker
    case filePicker
    case sessionPicker
    case changelog
}

enum ConnectionPhase: Equatable {
    case idle
    case checking
    case succeeded
    case failed(String)
}

/// Upstream dashboard row subset (`views/dashboard/`) — expand as multi-agent ACP lands.
struct DashboardRowModel: Identifiable, Equatable {
    enum State: Equatable {
        case working
        case needsInput
        case idle
    }

    let id: UUID
    /// ACP session id when row comes from `x.ai/session/list`.
    var sessionId: String?
    var title: String
    var state: State
    var indent: Int
    var activity: String?
    var ageLabel: String?
    /// Upstream filled/hollow diamonds: ◆ working/awaiting, ◇ idle
    var bullet: String

    init(
        id: UUID = UUID(),
        sessionId: String? = nil,
        title: String,
        state: State,
        indent: Int = 0,
        activity: String? = nil,
        ageLabel: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.state = state
        self.indent = indent
        self.activity = activity
        self.ageLabel = ageLabel
        switch state {
        case .working, .needsInput: self.bullet = "◆"
        case .idle: self.bullet = "◇"
        }
    }
}

/// ACP `PermissionOption` row from `session/request_permission`.
struct PermissionOption: Equatable, Identifiable {
    let optionId: String
    let name: String
    let kind: String

    var id: String { optionId }
}

struct PermissionRequest: Equatable {
    let message: String
    let title: String?
    let options: [PermissionOption]
    let requestId: ACPProtocol.JSONValue?
    var selectedOptionId: String?

    init(
        message: String,
        title: String? = nil,
        options: [PermissionOption] = [],
        requestId: ACPProtocol.JSONValue?,
        selectedOptionId: String? = nil
    ) {
        self.message = message
        self.title = title
        self.options = options
        self.requestId = requestId
        self.selectedOptionId = selectedOptionId
    }
}

struct SessionListEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let cwd: String
}

/// Live roster row from `x.ai/sessions/list` / `x.ai/sessions/changed`.
struct RosterSessionEntry: Identifiable, Equatable {
    enum Activity: Equatable {
        case working
        case idle
        case needsInput
        case dormant
        case completed
        case dead
    }

    let id: String
    var title: String?
    var cwd: String
    var activity: Activity
    var lastChangeUnixMs: Int64?

    var dashboardState: DashboardRowModel.State {
        switch activity {
        case .working: return .working
        case .needsInput: return .needsInput
        default: return .idle
        }
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if !cwd.isEmpty { return cwd }
        return id
    }

    var ageLabel: String? {
        guard let ms = lastChangeUnixMs, ms > 0 else { return nil }
        let age = Date().timeIntervalSince1970 - Double(ms) / 1000.0
        if age < 0 { return nil }
        if age < 60 { return "\(Int(age))s" }
        if age < 3600 { return "\(Int(age / 60))m" }
        if age < 86_400 { return "\(Int(age / 3600))h" }
        return "\(Int(age / 86_400))d"
    }
}
