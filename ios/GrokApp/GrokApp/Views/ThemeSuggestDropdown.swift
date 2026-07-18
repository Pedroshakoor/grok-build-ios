// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// In-prompt `/theme` suggest list (`slash/commands/theme.rs` suggest_args).
struct ThemeSuggestDropdown: View {
    let themes: [String]
    let activeTheme: String
    let theme: GrokTheme
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.promptBorder)
                .frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(themes, id: \.self) { name in
                        Button {
                            onSelect(name)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(name)
                                    .font(.body.monospaced())
                                    .foregroundStyle(theme.textPrimary)
                                    .frame(width: 140, alignment: .leading)
                                if name == activeTheme {
                                    Text("(active)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if name != themes.last {
                            Rectangle()
                                .fill(theme.promptBorder.opacity(0.5))
                                .frame(height: 1)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(theme.bgHighlight)
        }
    }
}
