// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Slash commands from bundled `slash-commands.json` (upstream `04-slash-commands.md`).
enum SlashCommandCatalog {
    private struct Root: Decodable {
        let commands: [Entry]
    }

    private struct Entry: Decodable {
        let name: String
        let aliases: [String]
    }

    static let all: [SlashCommand] = load()

    /// Phase 5+: show full upstream docs catalog; local handlers for a few, rest forwarded to agent.
    static var builtins: [SlashCommand] {
        all.isEmpty ? SlashCommand.fallback : all
    }

    static func resolve(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let token = String(parts[0].dropFirst()).lowercased()
        let rest = parts.count > 1 ? " " + parts[1] : ""
        for cmd in all {
            if cmd.id == token || cmd.aliases.contains(token) {
                return "/" + cmd.id + rest
            }
        }
        return trimmed
    }

    private static func load() -> [SlashCommand] {
        guard let url = Bundle.main.url(forResource: "slash-commands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data)
        else {
            return SlashCommand.fallback
        }
        return root.commands.map { entry in
            SlashCommand(
                id: entry.name,
                name: "/\(entry.name)",
                summary: summaryFor(entry.name),
                aliases: entry.aliases
            )
        }
    }

    private static func summaryFor(_ name: String) -> String {
        // Wording aligned with upstream 04-slash-commands.md where practical.
        switch name {
        case "new": return "Start a new session"
        case "resume": return "Resume a previous session"
        case "theme": return "Switch theme"
        case "settings": return "Open settings"
        case "always-approve": return "Toggle always-approve"
        case "plan": return "Toggle plan mode"
        case "quit": return "Quit the application"
        case "dashboard": return "Open the agent dashboard"
        default: return name
        }
    }
}

// Keep agentSubset for any legacy call sites during transition.
extension SlashCommandCatalog {
    static let agentSubset: Set<String> = Set(all.map(\.id))
}
