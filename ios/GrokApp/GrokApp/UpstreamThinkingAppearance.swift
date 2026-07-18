// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Copied from upstream `xai-grok-pager-render` appearance + `thinking.rs`.
/// Source: `crates/codegen/xai-grok-pager-render/src/appearance/config.rs` (`ThinkingConfig`)
/// and `crates/codegen/xai-grok-pager/src/scrollback/blocks/thinking.rs`.
enum UpstreamThinkingAppearance {
    /// `ThinkingConfig::default().bg_blend` — 0.7 (raw toml `bg_blend = 70`).
    static let bgBlend: CGFloat = 0.7
    /// `ThinkingConfig::default().truncated_lines`
    static let truncatedLines = 3
    /// `ThinkingConfig::default().header_bright`
    static let headerBright = false
    /// `ThinkingConfig::default().header`
    static let header = true
    /// `ToolConfig::default().dim_details` — Thinking `" for Xs"` uses dimmest gray.
    static let dimDetails = true
    /// `ToolConfig::default().muted_collapsed`
    static let mutedCollapsed = true
}

extension Color {
    /// Upstream `blend_channel` / `blend_color` in
    /// `xai-grok-pager-render/src/render/color.rs`:
    /// `result = base * (1 - opacity) + original * opacity`
    /// - opacity 0 → base (bg)
    /// - opacity 1 → original (fg)
    func blended(towardBase base: Color, opacity: CGFloat) -> Color {
        let o = UIColor(self)
        let b = UIColor(base)
        var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        o.getRed(&or, green: &og, blue: &ob, alpha: &oa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = opacity
        return Color(
            red: br * (1 - t) + or * t,
            green: bg * (1 - t) + og * t,
            blue: bb * (1 - t) + ob * t
        )
    }
}

extension GrokTheme {
    /// Thinking body fg after `blend_line_with_default(bg_base, text_primary, bg_blend)`.
    var thinkingBodyForeground: Color {
        textPrimary.blended(towardBase: bgBase, opacity: UpstreamThinkingAppearance.bgBlend)
    }

    /// `theme.muted()` → `gray` (groknight `#6c6c6c`).
    var thinkingHeaderLabel: Color { gray }

    /// `theme.dim()` / `gray_dim` when `dim_details` — Thinking `" for Xs"`.
    var thinkingHeaderDetail: Color {
        UpstreamThinkingAppearance.dimDetails ? grayDim : gray
    }
}
