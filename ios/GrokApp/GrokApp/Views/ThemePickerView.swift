// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// `/theme` suggest list — upstream shows `(active)` on the current theme (theme.rs).
/// Phone: still a screen; labels match pager suggest_args, not invented chrome.
struct ThemePickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("←") { model.showAgent() }
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                Text("/theme")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.command)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.bgBase)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.promptBorder).frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.availableThemes, id: \.self) { name in
                        Button {
                            model.setTheme(name)
                            model.showAgent()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(name)
                                    .font(.body.monospaced())
                                    .foregroundStyle(theme.textPrimary)
                                    .frame(width: 120, alignment: .leading)
                                if model.themeName == name {
                                    Text("(active)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle()
                            .fill(theme.promptBorder.opacity(0.35))
                            .frame(height: 1)
                            .padding(.leading, 12)
                    }
                }
            }
            .background(theme.bgTerminal)
        }
        .background(theme.bgBase)
    }
}
