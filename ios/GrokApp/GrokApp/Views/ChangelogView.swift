// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Bundled release notes — title from first `#` heading only.
struct ChangelogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        VStack(spacing: 0) {
            HStack {
                Button("←") { model.showWelcome() }
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                Text(model.changelogTitle)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.command)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.bgBase)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.promptBorder).frame(height: 1)
            }

            ScrollView {
                Text(model.changelogBody)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(theme.bgTerminal)
        }
        .background(theme.bgBase)
    }
}
