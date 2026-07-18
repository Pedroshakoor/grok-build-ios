// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Upstream welcome logo (`views/welcome/logo.rs`).
/// Assets: exact `logo05.txt` / `logo07.txt` from pager.
/// Rendered as a single monospaced block (per-glyph views froze the welcome menu for seconds).
struct WelcomeLogoView: View {
    let theme: GrokTheme
    let windowHeightPoints: CGFloat

    private var windowRows: Int {
        max(1, Int(windowHeightPoints / 14.0))
    }

    /// `pick_logo`: phone always has room — prefer logo07; never blank on first layout.
    private var logoText: String? {
        if windowHeightPoints < 100 {
            return Self.loadAsset("logo07") ?? Self.loadAsset("logo05")
        }
        if windowRows < 22 { return Self.loadAsset("logo05") ?? Self.loadAsset("logo07") }
        if windowRows < 26 { return Self.loadAsset("logo05") ?? Self.loadAsset("logo07") }
        return Self.loadAsset("logo07") ?? Self.loadAsset("logo05")
    }

    var body: some View {
        Group {
            if let logo = logoText {
                Text(logo)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private static func loadAsset(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text.trimmingCharacters(in: CharacterSet.newlines)
    }
}
