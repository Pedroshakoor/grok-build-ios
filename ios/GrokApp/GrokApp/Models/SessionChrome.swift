// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Live agent chrome fields mirrored from upstream pager status / prompt info.
struct SessionChrome: Equatable {
    var cwd: String = ""
    var gitBranch: String?
    var isWorktree: Bool = false
    var mainRepo: String?
    var modelId: String = ""
    var modelEffort: String?
    var planMode: Bool = false
    var alwaysApprove: Bool = false
    /// Context used — only from ACP `_meta.totalTokens` / session info (never invent).
    var contextUsed: Int?
    /// Model context window — only when agent reports it (never invent a total).
    var contextTotal: Int?
    var turnActivity: String?
    var turnStartedAt: Date?
    var phaseStartedAt: Date?
    var turnTokensUsed: Int?
    /// Queued prompts from `x.ai/queue/changed` — turn_status hint `· N queued`.
    var queuedPromptCount: Int = 0
    var sessionId: String?

    /// From `x.ai/mcp/init_progress` — chip only when total > 0 (`agent_status.rs`).
    var mcpConnected: Int?
    var mcpTotal: Int?

    /// From `goal_updated` session update — phase label when active/paused.
    var goalPhaseLabel: String?
    var goalActive: Bool = false

    /// From `x.ai/billing` poll — `Credits used: N%` when known.
    var creditsUsedPercent: Double?

    var loadingTitle: String {
        if let sid = sessionId, !sid.isEmpty {
            return "session \(sid.prefix(8))"
        }
        return "loading..."
    }

    /// Prompt info line: `{model} ({effort}) · plan · always-approve`
    var promptInfoLine: String {
        var parts: [String] = []
        var model = modelId
        if let effort = modelEffort, !effort.isEmpty {
            model = "\(modelId) (\(effort))"
        }
        if !model.isEmpty { parts.append(model) }
        if planMode { parts.append("plan") }
        if alwaysApprove { parts.append("always-approve") }
        return parts.joined(separator: " · ")
    }

    /// Right-side chips. Only when ACP/companion provides data (never invent).
    var statusRightChips: [String] {
        var chips: [String] = []
        if planMode { chips.append("plan") }
        if let goal = goalPhaseLabel, !goal.isEmpty {
            chips.append(goalActive ? "Goal: \(goal)" : "Goal: \(goal)")
        }
        if let total = mcpTotal, total > 0 {
            let connected = mcpConnected ?? 0
            chips.append("MCP (\(connected)/\(total))")
        }
        if let pct = creditsUsedPercent {
            chips.append(String(format: "Credits used: %.0f%%", pct))
        }
        if let used = contextUsed, let total = contextTotal, total > 0 {
            chips.append("\(Self.fmtTokens(UInt64(max(0, used)))) / \(Self.fmtTokens(UInt64(total)))")
        }
        return chips
    }

    var cwdDisplay: String {
        let path = cwd
        guard !path.isEmpty else { return "" }
        if let home = ProcessInfo.processInfo.environment["HOME"], path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var gitDisplay: String? {
        guard let branch = gitBranch else { return nil }
        let icon = "⎇"
        if branch.isEmpty { return "\(icon) detached" }
        return "\(icon) \(branch)"
    }

    /// Upstream `context_bar::fmt_tokens` — ≤4 chars, uppercase K/M (rounds .1K).
    static func fmtTokens(_ n: UInt64) -> String {
        if n < 1_000 {
            return "\(n)"
        } else if n < 10_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        } else if n < 1_000_000 {
            return "\(n / 1_000)K"
        } else if n < 10_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000.0)
        } else {
            return "\(n / 1_000_000)M"
        }
    }
}
