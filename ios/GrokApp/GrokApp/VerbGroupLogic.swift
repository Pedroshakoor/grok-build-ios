// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Upstream `VerbGroupKind` + `verb_group_header_label` (subset for iOS fold).
enum VerbGroupKind: Equatable {
    case file, skill, search, dir, webFetch, webSearch, command, editFile, other

    func verb(running: Bool) -> String {
        let pair: (String, String)
        switch self {
        case .file, .skill: pair = ("Read", "Reading")
        case .search, .webSearch: pair = ("Searched", "Searching")
        case .dir: pair = ("Listed", "Listing")
        case .webFetch: pair = ("Fetched", "Fetching")
        case .command, .other: pair = ("Ran", "Running")
        case .editFile: pair = ("Edited", "Editing")
        }
        return running ? pair.1 : pair.0
    }

    func noun(count: Int) -> String {
        let oneMany: (String, String)
        switch self {
        case .file, .editFile: oneMany = ("file", "files")
        case .skill: oneMany = ("skill", "skills")
        case .search: oneMany = ("pattern", "patterns")
        case .dir: oneMany = ("dir", "dirs")
        case .webFetch, .webSearch: oneMany = ("website", "websites")
        case .command: oneMany = ("command", "commands")
        case .other: oneMany = ("tool", "tools")
        }
        return count == 1 ? oneMany.0 : oneMany.1
    }

    static func from(toolKind: String?, title: String?, detail: String?) -> VerbGroupKind? {
        let k = (toolKind ?? "").lowercased()
        let path = detail ?? title ?? ""
        if k.contains("read") || k == "read_file" || k == "readfile" {
            if path.lowercased().contains("skill.md") { return .skill }
            return .file
        }
        if k.contains("search") || k == "grep" || k == "glob" || k.contains("web_search") || k.contains("websearch") {
            return k.contains("web") ? .webSearch : .search
        }
        if k.contains("list") || k == "ls" || k == "listdir" { return .dir }
        if k.contains("fetch") || k.contains("web_fetch") { return .webFetch }
        if k.contains("edit") || k.contains("write") || k.contains("patch") { return .editFile }
        if k.contains("execute") || k == "bash" || k == "shell" || k == "run" { return .command }
        if k == "tool" || title != nil { return .other }
        return nil
    }
}

struct VerbGroupFold: Identifiable, Equatable {
    let id: UUID
    var memberIDs: [UUID]
    var label: String
    var isExpanded: Bool
    var running: Bool
}

enum VerbGroupLogic {
    /// Upstream `group_header_chrome_prefix` — ◈ (diamond_dotted U+25C8).
    static let chromePrefix = "\u{25C8} "

    /// Build aggregated label or fallback `N tool calls & thoughts`.
    static func headerLabel(for members: [ScrollbackEntry]) -> String {
        struct Bucket {
            let kind: VerbGroupKind
            var count: Int
        }
        var buckets: [Bucket] = []
        var running = false
        for entry in members {
            guard entry.kind == .tool else { continue }
            guard let kind = VerbGroupKind.from(
                toolKind: entry.toolKind,
                title: entry.toolTitle,
                detail: entry.toolDetail
            ) else { continue }
            if entry.isStreaming || entry.toolStatus == "in_progress" { running = true }
            if let idx = buckets.firstIndex(where: { $0.kind == kind }) {
                buckets[idx].count += 1
            } else {
                buckets.append(Bucket(kind: kind, count: 1))
            }
        }
        if buckets.isEmpty {
            return "\(members.count) tool calls & thoughts"
        }
        let segments = buckets.enumerated().map { i, b in
            let prefix = i == 0 ? "" : ", "
            return "\(prefix)\(b.kind.verb(running: running)) \(b.count) \(b.kind.noun(count: b.count))"
        }.joined()
        return segments
    }

    static func fullHeader(for members: [ScrollbackEntry]) -> String {
        chromePrefix + headerLabel(for: members)
    }

    /// Whether an entry can join a verb-group run.
    static func isFoldableMember(_ entry: ScrollbackEntry, showThinking: Bool) -> Bool {
        switch entry.kind {
        case .tool:
            return entry.isCollapsed && !entry.isStreaming
                && entry.toolStatus != "in_progress"
        case .thinking:
            return showThinking && entry.isCollapsed && !entry.isStreaming
                && entry.thinkingMode == .collapsed
        default:
            return false
        }
    }

    /// Stable group id from member entry ids (survives display refreshes).
    static func stableGroupID(for members: [ScrollbackEntry]) -> UUID {
        let seed = members.map(\.id.uuidString).joined(separator: "|")
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, byte) in seed.utf8.enumerated() {
            bytes[i % 16] ^= byte
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Fold consecutive finished collapsed tool/thinking runs.
    static func fold(
        _ entries: [ScrollbackEntry],
        expandedGroupIDs: Set<UUID>,
        showThinking: Bool
    ) -> ([ScrollbackEntry], [VerbGroupFold]) {
        var output: [ScrollbackEntry] = []
        var groups: [VerbGroupFold] = []
        var i = 0
        while i < entries.count {
            guard isFoldableMember(entries[i], showThinking: showThinking) else {
                output.append(entries[i])
                i += 1
                continue
            }
            var j = i
            var members: [ScrollbackEntry] = []
            while j < entries.count, isFoldableMember(entries[j], showThinking: showThinking) {
                members.append(entries[j])
                j += 1
            }
            let toolMembers = members.filter { $0.kind == .tool }
            if toolMembers.count >= 1 {
                let groupID = stableGroupID(for: members)
                let expanded = expandedGroupIDs.contains(groupID)
                let label = fullHeader(for: members)
                let running = members.contains { $0.isStreaming || $0.toolStatus == "in_progress" }
                groups.append(VerbGroupFold(
                    id: groupID,
                    memberIDs: members.map(\.id),
                    label: label,
                    isExpanded: expanded,
                    running: running
                ))
                output.append(ScrollbackEntry(
                    id: groupID,
                    kind: .verbGroup,
                    text: label,
                    isCollapsed: !expanded
                ))
                if expanded {
                    output.append(contentsOf: members)
                }
                i = j
            } else {
                output.append(entries[i])
                i += 1
            }
        }
        return (output, groups)
    }
}
