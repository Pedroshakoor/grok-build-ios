// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Scrollback aligned with upstream `xai-grok-pager` block semantics only.
/// Strings/modes from `scrollback/blocks/thinking.rs`, `user.rs`, `agent.rs`, `tool/*`.
struct ScrollbackView: View {
    let entries: [ScrollbackEntry]
    let theme: GrokTheme
    var showTimestamps: Bool = AppSettings.showTimestamps
    var onToggleFold: ((UUID) -> Void)?
    var onOpenMermaid: ((String) async -> Data?)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        ScrollbackRow(
                            entry: entry,
                            theme: theme,
                            showTimestamps: showTimestamps,
                            onToggleFold: onToggleFold,
                            onOpenMermaid: onOpenMermaid
                        )
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

struct ScrollbackRow: View {
    let entry: ScrollbackEntry
    let theme: GrokTheme
    var showTimestamps: Bool = true
    var onToggleFold: ((UUID) -> Void)?
    var onOpenMermaid: ((String) async -> Data?)?

    var body: some View {
        let row = HStack(alignment: .top, spacing: 0) {
            // Upstream: thinking accent only when not Collapsed; agent message has no accent.
            Rectangle()
                .fill(accentColor)
                .frame(width: showAccentColumn ? 3 : 0)
            content
                .padding(.horizontal, 12)
                .padding(.vertical, entry.kind == .user ? 6 : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(entry.kind == .user ? theme.bgLight.opacity(0.55) : Color.clear)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())

        // Only foldable blocks are buttons — disabled Button dims label colors (was making
        // assistant/user look grey vs Thought). Matches pager: tap toggles fold only.
        if entry.kind == .thinking || entry.kind == .tool || entry.kind == .verbGroup {
            Button {
                onToggleFold?(entry.id)
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var showAccentColumn: Bool {
        switch entry.kind {
        case .thinking:
            // thinking.rs accent(): None when Collapsed
            return entry.thinkingMode != .collapsed
        case .assistant, .system, .plan:
            return false
        case .user:
            // user.rs: accent() → None; accent_background → bg_light (not accent_user bar)
            return false
        case .tool:
            // read.rs / edit / list_dir / search: accent() → None
            return toolShowsAccentColumn
        case .diff, .error:
            return true
        case .verbGroup:
            return false
        }
    }
    private var toolShowsAccentColumn: Bool {
        let k = (entry.toolKind ?? "").lowercased()
        switch k {
        case "read", "read_file", "readfile",
             "edit", "write", "write_file", "apply_patch", "edit_file",
             "search", "grep", "glob",
             "list_dir", "listdir", "ls":
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .user:
            HStack(alignment: .top, spacing: 0) {
                if showTimestamps {
                    Text("\(FormatDuration.messageTimestamp(entry.timestamp)) ")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.gray)
                }
                Text("❯ ")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.accentUser)
                Text(entry.text)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
            }

        case .verbGroup:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.text)
                    .font(.body.monospaced().weight(.bold))
                    .foregroundStyle(theme.gray)
                    .lineLimit(1)
            }

        case .thinking:
            thinkingContent

        case .tool:
            // tool/*: ◆ bullet + collapsed_line (muted when collapsed)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("◆")
                        .font(.body.monospaced())
                        .foregroundStyle(entry.isCollapsed ? theme.textSecondary : theme.accentTool)
                    Text(toolCollapsedHeader)
                        .font(.body.monospaced())
                        .foregroundStyle(entry.isCollapsed ? theme.textSecondary : theme.textPrimary)
                        .lineLimit(entry.isCollapsed ? 1 : 4)
                }
                if !entry.isCollapsed, let detail = entry.toolDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(16)
                        .padding(.leading, 16)
                }
            }

        case .assistant:
            HStack(alignment: .top, spacing: 0) {
                if showTimestamps {
                    Text("\(FormatDuration.messageTimestamp(entry.timestamp)) ")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.gray)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(MarkdownLite.segments(entry.text).enumerated()), id: \.offset) { _, seg in
                        switch seg {
                        case .markdown(let text):
                            Text(MarkdownLite.attributed(text))
                                .font(agentFont)
                                .foregroundStyle(theme.textPrimary)
                                .textSelection(.enabled)
                        case .mermaid(let source):
                            MermaidBlockView(
                                source: source,
                                theme: theme,
                                onOpenImage: onOpenMermaid
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .plan:
            // ACP `plan` update — body only (no invented "plan" chip)
            Text(entry.text)
                .font(.body.monospaced())
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)

        case .diff:
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.path)
                if let hunks = entry.diffHunks {
                    ForEach(hunks) { hunk in
                        DiffHunkView(hunk: hunk, theme: theme)
                    }
                }
            }

        case .error:
            Text(entry.text)
                .font(.body.monospaced())
                .foregroundStyle(theme.accentError)

        case .system:
            Text(entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var thinkingContent: some View {
        // Upstream thinking.rs DisplayMode — same terminal cell size as AgentMessage;
        // hierarchy is muted header + bg_blend body (not a larger/brighter header).
        switch entry.thinkingMode {
        case .collapsed:
            thinkingHeader
        case .truncated:
            VStack(alignment: .leading, spacing: 4) {
                if UpstreamThinkingAppearance.header { thinkingHeader }
                if !entry.text.isEmpty {
                    if thoughtLineCount > UpstreamThinkingAppearance.truncatedLines {
                        Text("…")
                            .font(thinkingFont)
                            .foregroundStyle(theme.thinkingHeaderLabel)
                    }
                    Text(truncatedThoughtBody)
                        .font(thinkingFont)
                        .foregroundStyle(theme.thinkingBodyForeground)
                        .textSelection(.enabled)
                }
            }
        case .expanded:
            VStack(alignment: .leading, spacing: 4) {
                if UpstreamThinkingAppearance.header { thinkingHeader }
                Text(entry.text)
                    .font(thinkingFont)
                    .foregroundStyle(theme.thinkingBodyForeground)
                    .textSelection(.enabled)
            }
        }
    }

    /// Same face as agent body (terminal = one cell size). Weight/color carry hierarchy.
    private var thinkingFont: Font { .body }

    private var agentFont: Font { .body }

    /// thinking.rs `header_line`: label = muted().bold(); detail = muted()
    /// (ToolConfig.dim_details → gray_dim for `" for Xs"`).
    private var thinkingHeader: some View {
        Group {
            if entry.isStreaming {
                Text("Thinking…")
                    .font(thinkingFont.weight(.bold))
                    .foregroundStyle(theme.thinkingHeaderLabel)
            } else if let time = formattedThoughtTime {
                HStack(spacing: 0) {
                    Text("Thought")
                        .font(thinkingFont.weight(.bold))
                        .foregroundStyle(theme.thinkingHeaderLabel)
                    Text(" for \(time)")
                        .font(thinkingFont)
                        .foregroundStyle(theme.thinkingHeaderDetail)
                }
            } else {
                Text("Thought")
                    .font(thinkingFont.weight(.bold))
                    .foregroundStyle(theme.thinkingHeaderLabel)
            }
        }
    }

    /// thinking.rs `format_time`
    private var formattedThoughtTime: String? {
        let ms: Int64
        if let stored = entry.thoughtElapsedMs, stored > 0 {
            ms = stored
        } else if entry.isStreaming, let start = entry.thoughtStartedAt {
            ms = Int64(Date().timeIntervalSince(start) * 1000)
        } else {
            return nil
        }
        let secs = Double(ms) / 1000.0
        if secs < 60.0 {
            return String(format: "%.1fs", secs)
        }
        let mins = Int(secs / 60.0)
        let remaining = secs - Double(mins) * 60.0
        return String(format: "%dm%.0fs", mins, remaining)
    }

    private var thoughtLineCount: Int {
        entry.text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var truncatedThoughtBody: String {
        let lines = entry.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let n = UpstreamThinkingAppearance.truncatedLines
        if lines.count <= n { return entry.text }
        return lines.suffix(n).joined(separator: "\n")
    }

    /// Collapsed tool header from upstream tool kind prefixes (Read/Run/Edit/…).
    private var toolCollapsedHeader: String {
        ToolCollapsedHeader.format(kind: entry.toolKind, title: entry.toolTitle, detail: entry.toolDetail)
    }

    private var accentColor: Color {
        switch entry.kind {
        case .user: return .clear
        case .assistant: return .clear
        case .thinking:
            return entry.isStreaming ? theme.accentThinking : theme.accentThinking.opacity(0.85)
        case .tool, .diff: return theme.accentTool
        case .plan: return .clear
        case .verbGroup: return .clear
        case .error: return theme.accentError
        case .system: return .clear
        }
    }
}

/// Upstream tool collapsed_line prefixes (`scrollback/blocks/tool/*.rs`).
enum ToolCollapsedHeader {
    static func format(kind: String?, title: String?, detail: String?) -> String {
        let rawKind = (kind ?? "").lowercased()
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pathOrCmd = firstPathOrCommand(from: detail) ?? title

        // read.rs: SKILL.md reads render as "Skill {skill_name}".
        if isSkillRead(path: pathOrCmd) || isSkillRead(path: title) {
            let skill = skillName(from: pathOrCmd) ?? skillName(from: title) ?? title
            return skill.isEmpty ? "Skill" : "Skill \(skill)"
        }

        switch rawKind {
        case "read", "read_file", "readfile":
            return "Read \(basename(pathOrCmd))"
        case "execute", "bash", "shell", "run":
            if !title.isEmpty, !title.lowercased().hasPrefix("run") {
                return "Run \(title)"
            }
            return title.hasPrefix("Run ") ? title : "Run \(pathOrCmd)"
        case "edit", "write", "write_file", "apply_patch", "edit_file":
            return title.isEmpty ? "Edit \(basename(pathOrCmd))" : title
        case "search", "grep", "glob":
            return title.isEmpty ? "Search \(pathOrCmd)" : title
        case "list_dir", "listdir", "ls":
            return title.isEmpty ? "List \(pathOrCmd)" : title
        case "web_fetch", "webfetch", "fetch":
            return title.isEmpty ? "Fetch \(pathOrCmd)" : title
        case "web_search", "websearch":
            // web_search.rs default label: "Web Search "
            let q = pathOrCmd.isEmpty ? title : pathOrCmd
            return q.isEmpty ? "Web Search" : "Web Search \(q)"
        case "skill":
            return title.isEmpty ? "Skill" : "Skill \(title)"
        default:
            // Prefer ACP title when present (agent already formats many tools).
            return title.isEmpty ? "Tool" : title
        }
    }

    private static func isSkillRead(path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix("skill.md") || lower.contains("/skill.md") || lower == "skill.md"
    }

    private static func skillName(from path: String) -> String? {
        // …/skills/{name}/SKILL.md → name
        let parts = path.split(separator: "/").map(String.init)
        guard let idx = parts.firstIndex(where: { $0.lowercased() == "skill.md" }), idx > 0 else {
            return nil
        }
        return parts[idx - 1]
    }

    private static func basename(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        return (trimmed as NSString).lastPathComponent
    }

    private static func firstPathOrCommand(from detail: String?) -> String? {
        guard let detail, !detail.isEmpty else { return nil }
        if let data = detail.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["path", "file", "file_path", "command", "cmd", "query", "url"] {
                if let s = obj[key] as? String, !s.isEmpty { return s }
            }
        }
        return detail.split(separator: "\n").first.map(String.init)
    }
}

struct DiffHunkView: View {
    let hunk: DiffHunk
    let theme: GrokTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hunk.path).font(.caption2.monospaced()).foregroundStyle(theme.path)
            ForEach(hunk.oldLines, id: \.self) { line in
                Text("- \(line)").font(.caption2.monospaced()).foregroundStyle(theme.diffDeleteFg)
            }
            ForEach(hunk.newLines, id: \.self) { line in
                Text("+ \(line)").font(.caption2.monospaced()).foregroundStyle(theme.diffInsertFg)
            }
        }
        .padding(6)
        .background(theme.bgHighlight.opacity(0.4))
    }
}
