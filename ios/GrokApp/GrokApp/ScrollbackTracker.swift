// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Maps ACP `session/update` events into scrollback mutations (pager tracker subset).
/// Thinking modes follow `ThinkingBlock` in upstream `scrollback/blocks/thinking.rs`.
@MainActor
final class ScrollbackTracker {
    private(set) var entries: [ScrollbackEntry] = []
    private var streamingAssistantID: UUID?
    private var streamingThoughtID: UUID?
    private var toolEntries: [String: UUID] = [:]
    private(set) var expandedVerbGroupIDs: Set<UUID> = []

    var onChange: (([ScrollbackEntry]) -> Void)?

    func reset() {
        entries.removeAll()
        streamingAssistantID = nil
        streamingThoughtID = nil
        toolEntries.removeAll()
        expandedVerbGroupIDs.removeAll()
        notify()
    }

    func appendUser(_ text: String) {
        entries.append(ScrollbackEntry(kind: .user, text: text))
        notify()
    }

    func appendSystem(_ text: String) {
        entries.append(ScrollbackEntry(kind: .system, text: text))
        notify()
    }

    func appendError(_ text: String) {
        entries.append(ScrollbackEntry(kind: .error, text: text))
        notify()
    }

    func handleSessionUpdate(_ update: [String: ACPProtocol.JSONValue]) {
        let kind = update["sessionUpdate"]?.stringValue ?? ""
        switch kind {
        case "agent_message_chunk":
            guard let content = update["content"]?.objectValue,
                  let text = content["text"]?.stringValue, !text.isEmpty else { return }
            appendAssistantChunk(text)
        case "agent_thought_chunk":
            guard let content = update["content"]?.objectValue,
                  let text = content["text"]?.stringValue, !text.isEmpty else { return }
            appendThoughtChunk(text)
        case "tool_call":
            finalizeStreaming()
            let toolId = update["toolCallId"]?.stringValue ?? UUID().uuidString
            let title = update["title"]?.stringValue ?? update["kind"]?.stringValue ?? "Tool"
            let toolKind = update["kind"]?.stringValue
            let status = update["status"]?.stringValue ?? "in_progress"
            let input = jsonSnippet(update["rawInput"])
            let entry = ScrollbackEntry(
                kind: .tool,
                text: title,
                isCollapsed: true,
                toolTitle: title,
                toolKind: toolKind,
                toolStatus: status,
                toolDetail: input,
                toolCallId: toolId
            )
            entries.append(entry)
            toolEntries[toolId] = entry.id
            notify()
        case "tool_call_update":
            let toolId = update["toolCallId"]?.stringValue ?? ""
            let status = update["status"]?.stringValue ?? "updated"
            let output = jsonSnippet(update["rawOutput"])
            if let diffTitle = parseEditDiff(from: update) {
                handleEditDiff(title: diffTitle.title, hunks: diffTitle.hunks)
            }
            if let existing = toolEntries[toolId], let idx = entries.firstIndex(where: { $0.id == existing }) {
                var e = entries[idx]
                e.toolStatus = status
                if let title = update["title"]?.stringValue { e.toolTitle = title }
                if let k = update["kind"]?.stringValue { e.toolKind = k }
                if !output.isEmpty { e.toolDetail = (e.toolDetail ?? "") + "\n" + output }
                entries[idx] = e
            } else {
                entries.append(ScrollbackEntry(
                    kind: .tool,
                    text: update["title"]?.stringValue ?? "Tool",
                    isCollapsed: true,
                    toolTitle: update["title"]?.stringValue,
                    toolKind: update["kind"]?.stringValue,
                    toolStatus: status,
                    toolDetail: output,
                    toolCallId: toolId
                ))
            }
            if status == "completed" || status == "failed" {
                finalizeStreaming()
                collapseFinishedThoughts()
            }
            notify()
        case "plan":
            finalizeStreaming()
            // Body only — no invented "plan" / "Plan updated" chrome.
            let planText = planEntriesText(update["entries"])
            guard !planText.isEmpty else { return }
            entries.append(ScrollbackEntry(kind: .plan, text: planText))
            notify()
        default:
            break
        }
    }

    func handleEditDiff(title: String, hunks: [DiffHunk]) {
        finalizeStreaming()
        entries.append(ScrollbackEntry(kind: .diff, text: title, diffHunks: hunks))
        notify()
    }

    private func appendAssistantChunk(_ text: String) {
        if let id = streamingAssistantID, let idx = entries.firstIndex(where: { $0.id == id }) {
            var e = entries[idx]
            e.text += text
            e.isStreaming = true
            entries[idx] = e
        } else {
            finalizeThought()
            let entry = ScrollbackEntry(kind: .assistant, text: text, isStreaming: true)
            streamingAssistantID = entry.id
            entries.append(entry)
        }
        notify()
    }

    private func appendThoughtChunk(_ text: String) {
        if let id = streamingThoughtID, let idx = entries.firstIndex(where: { $0.id == id }) {
            var e = entries[idx]
            e.text += text
            e.isStreaming = true
            // Upstream collapse_mode(running) → Truncated (body visible).
            if e.thinkingMode == .collapsed {
                e.thinkingMode = .truncated
            }
            entries[idx] = e
        } else {
            finalizeAssistant()
            // streaming() + default_display_mode Truncated while running.
            let entry = ScrollbackEntry(
                kind: .thinking,
                text: text,
                isStreaming: true,
                isCollapsed: false,
                thinkingMode: .truncated,
                thoughtStartedAt: Date()
            )
            streamingThoughtID = entry.id
            entries.append(entry)
        }
        notify()
    }

    func finalizeStreaming() {
        finalizeAssistant()
        finalizeThought()
    }

    private func finalizeAssistant() {
        guard let id = streamingAssistantID, let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var e = entries[idx]
        e.isStreaming = false
        entries[idx] = e
        streamingAssistantID = nil
    }

    private func finalizeThought() {
        guard let id = streamingThoughtID, let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var e = entries[idx]
        e.isStreaming = false
        // finished_display_mode → Collapsed
        e.isCollapsed = true
        e.thinkingMode = .collapsed
        if e.thoughtElapsedMs == nil, let start = e.thoughtStartedAt {
            e.thoughtElapsedMs = Int64(Date().timeIntervalSince(start) * 1000)
        }
        entries[idx] = e
        streamingThoughtID = nil
    }

    func toggleFold(id: UUID) {
        if let entry = entries.first(where: { $0.id == id }), entry.kind == .verbGroup {
            if expandedVerbGroupIDs.contains(id) {
                expandedVerbGroupIDs.remove(id)
            } else {
                expandedVerbGroupIDs.insert(id)
            }
            notify()
            return
        }
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var e = entries[idx]
        if e.kind == .thinking {
            // thinking.rs next_fold_mode
            if e.isStreaming {
                e.thinkingMode = (e.thinkingMode == .expanded) ? .truncated : .expanded
            } else {
                e.thinkingMode = (e.thinkingMode == .collapsed) ? .expanded : .collapsed
            }
            e.isCollapsed = (e.thinkingMode == .collapsed)
        } else if e.kind == .tool {
            e.isCollapsed.toggle()
        } else {
            return
        }
        entries[idx] = e
        notify()
    }

    func toggleThoughtCollapse(id: UUID) { toggleFold(id: id) }
    func toggleToolCollapse(id: UUID) { toggleFold(id: id) }

    /// Collapse finished thoughts (upstream: thinking → Collapsed on turn end).
    func collapseFinishedThoughts() {
        for idx in entries.indices where entries[idx].kind == .thinking && !entries[idx].isStreaming {
            entries[idx].isCollapsed = true
            entries[idx].thinkingMode = .collapsed
        }
        notify()
    }

    private func planEntriesText(_ value: ACPProtocol.JSONValue?) -> String {
        guard let value else { return "" }
        if case .string(let s) = value { return s }
        if case .array(let arr) = value {
            return arr.compactMap { item -> String? in
                guard case .object(let o) = item else { return item.stringValue }
                let content = o["content"]?.stringValue ?? o["text"]?.stringValue
                let status = o["status"]?.stringValue
                if let content, let status { return "[\(status)] \(content)" }
                return content
            }.joined(separator: "\n")
        }
        return jsonSnippet(value)
    }

    private func jsonSnippet(_ value: ACPProtocol.JSONValue?) -> String {
        guard let value else { return "" }
        if case .string(let s) = value { return s }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s.count > 400 ? String(s.prefix(400)) + "…" : s
    }

    private func notify() {
        onChange?(displayEntries())
    }

    /// Display layer: verb-group fold + thinking visibility.
    func displayEntries(showThinking: Bool = AppSettings.showThinkingBlocks) -> [ScrollbackEntry] {
        var base = entries
        if !showThinking {
            base = base.filter { $0.kind != .thinking }
        }
        return VerbGroupLogic.fold(base, expandedGroupIDs: expandedVerbGroupIDs, showThinking: showThinking).0
    }

    private func parseEditDiff(from update: [String: ACPProtocol.JSONValue]) -> (title: String, hunks: [DiffHunk])? {
        guard let content = update["content"]?.arrayValue ?? update["fields"]?.objectValue?["content"]?.arrayValue else {
            return nil
        }
        var hunks: [DiffHunk] = []
        var path = update["title"]?.stringValue ?? "Edit"
        for item in content {
            guard case .object(let obj) = item else { continue }
            let type = obj["type"]?.stringValue ?? ""
            guard type == "diff" else { continue }
            let filePath = obj["path"]?.stringValue ?? obj["file_path"]?.stringValue ?? path
            path = filePath
            let oldText = obj["oldText"]?.stringValue ?? obj["old_text"]?.stringValue ?? ""
            let newText = obj["newText"]?.stringValue ?? obj["new_text"]?.stringValue ?? ""
            let oldLines = oldText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            hunks.append(DiffHunk(oldLines: oldLines, newLines: newLines, path: filePath))
        }
        guard !hunks.isEmpty else { return nil }
        return (path, hunks)
    }
}

struct DiffHunk: Equatable, Identifiable {
    let id = UUID()
    let oldLines: [String]
    let newLines: [String]
    let path: String
}
