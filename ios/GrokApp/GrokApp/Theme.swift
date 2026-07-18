// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct GrokTheme: Equatable {
    let name: String
    let bgTerminal: Color
    let bgBase: Color
    let bgHighlight: Color
    let bgLight: Color
    let textPrimary: Color
    let textSecondary: Color
    /// Upstream `gray` — `theme.muted()` for collapsed tool/thinking headers.
    let gray: Color
    let grayDim: Color
    let accentUser: Color
    let accentAssistant: Color
    let accentThinking: Color
    let accentSystem: Color
    let accentError: Color
    let accentSuccess: Color
    let accentTool: Color
    let accentPlan: Color
    let command: Color
    let path: Color
    let running: Color
    let promptBorder: Color
    let promptBorderActive: Color
    let diffDeleteBg: Color
    let diffDeleteFg: Color
    let diffInsertBg: Color
    let diffInsertFg: Color

    /// Heuristic for mermaid render theme (companion `__mermaid-render --theme`).
    var isDark: Bool {
        let n = name.lowercased()
        if n.contains("day") || n.contains("light") { return false }
        if n.contains("night") || n.contains("dark") || n.contains("moon") || n.contains("oscura") {
            return true
        }
        return true
    }

    static let grokNightFallback = GrokTheme(
        name: "GrokNight",
        bgTerminal: Color(hex: "#0a0a0a"),
        bgBase: Color(hex: "#141414"),
        bgHighlight: Color(hex: "#242424"),
        bgLight: Color(hex: "#242424"),
        textPrimary: Color(hex: "#e1e1e1"),
        textSecondary: Color(hex: "#c8c8c8"),
        gray: Color(hex: "#6c6c6c"),
        grayDim: Color(hex: "#585858"),
        accentUser: Color(hex: "#c8c8c8"),
        accentAssistant: Color(hex: "#bb9af7"),
        accentThinking: Color(hex: "#bb9af7"),
        accentSystem: Color(hex: "#7aa2f7"),
        accentError: Color(hex: "#f7768e"),
        accentSuccess: Color(hex: "#9ece6a"),
        accentTool: Color(hex: "#787878"),
        accentPlan: Color(hex: "#ffdb8d"),
        command: Color(hex: "#e0af68"),
        path: Color(hex: "#ff9e64"),
        running: Color(hex: "#7dcfff"),
        promptBorder: Color(hex: "#323237"),
        promptBorderActive: Color(hex: "#505058"),
        diffDeleteBg: Color(hex: "#420e14"),
        diffDeleteFg: Color(hex: "#f7768e"),
        diffInsertBg: Color(hex: "#063806"),
        diffInsertFg: Color(hex: "#9ece6a")
    )

    static func availableThemeNames() -> [String] {
        let bundled = ["GrokNight", "GrokDay", "TokyoNight", "RosePineMoon", "OscuraMidnight", "auto"]
        return bundled
    }

    static func load(named themeName: String) -> GrokTheme {
        let key = themeName.lowercased().replacingOccurrences(of: " ", with: "")
        let fileName: String
        let fallback: GrokTheme
        switch key {
        case "grokday", "day": fileName = "grokday"; fallback = grokNightFallback
        case "tokyonight": fileName = "tokyonight"; fallback = grokNightFallback
        case "rosepinemoon", "rosepine-moon": fileName = "rosepine-moon"; fallback = grokNightFallback
        case "oscuramidnight", "oscura-midnight": fileName = "oscura-midnight"; fallback = grokNightFallback
        case "auto": fileName = "auto"; fallback = grokNightFallback
        default: fileName = "groknight"; fallback = grokNightFallback
        }

        let url = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "themes")
            ?? Bundle.main.url(forResource: fileName, withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(ThemeJSON.self, from: data)
        else { return fallback }
        return json.theme(named: themeName.isEmpty ? fallback.name : themeName)
    }
}

private struct ThemeJSON: Decodable {
    let name: String
    let tokens: ThemeTokens

    func theme(named defaultName: String) -> GrokTheme {
        let t = tokens
        return GrokTheme(
            name: name.isEmpty ? defaultName : name,
            bgTerminal: Color(hex: t.bg_terminal),
            bgBase: Color(hex: t.bg_base),
            bgHighlight: Color(hex: t.bg_highlight),
            bgLight: Color(hex: t.bg_light ?? t.bg_highlight),
            textPrimary: Color(hex: t.text_primary),
            textSecondary: Color(hex: t.text_secondary),
            gray: Color(hex: t.gray ?? "#6c6c6c"),
            grayDim: Color(hex: t.gray_dim ?? "#585858"),
            accentUser: Color(hex: t.accent_user ?? t.text_secondary),
            accentAssistant: Color(hex: t.accent_assistant),
            accentThinking: Color(hex: t.accent_thinking ?? t.accent_assistant),
            accentSystem: Color(hex: t.accent_system),
            accentError: Color(hex: t.accent_error),
            accentSuccess: Color(hex: t.accent_success),
            accentTool: Color(hex: t.accent_tool),
            accentPlan: Color(hex: t.accent_plan ?? "#ffdb8d"),
            command: Color(hex: t.command),
            path: Color(hex: t.path),
            running: Color(hex: t.running),
            promptBorder: Color(hex: t.prompt_border),
            promptBorderActive: Color(hex: t.prompt_border_active),
            diffDeleteBg: Color(hex: t.diff_delete_bg ?? "#420e14"),
            diffDeleteFg: Color(hex: t.diff_delete_fg ?? "#f7768e"),
            diffInsertBg: Color(hex: t.diff_insert_bg ?? "#063806"),
            diffInsertFg: Color(hex: t.diff_insert_fg ?? "#9ece6a")
        )
    }
}

private struct ThemeTokens: Decodable {
    let bg_terminal: String
    let bg_base: String
    let bg_highlight: String
    let bg_light: String?
    let text_primary: String
    let text_secondary: String
    let gray: String?
    let gray_dim: String?
    let accent_user: String?
    let accent_assistant: String
    let accent_thinking: String?
    let accent_system: String
    let accent_error: String
    let accent_success: String
    let accent_tool: String
    let accent_plan: String?
    let command: String
    let path: String
    let running: String
    let prompt_border: String
    let prompt_border_active: String
    let diff_delete_bg: String?
    let diff_delete_fg: String?
    let diff_insert_bg: String?
    let diff_insert_fg: String?
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func rgbBytes() -> (UInt8, UInt8, UInt8) {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (UInt8(round(r * 255)), UInt8(round(g * 255)), UInt8(round(b * 255)))
        }
        return (0, 0, 0)
    }

    func matchesHex(_ hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let expected = (UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF))
        let actual = rgbBytes()
        return actual.0 == expected.0 && actual.1 == expected.1 && actual.2 == expected.2
    }
}
