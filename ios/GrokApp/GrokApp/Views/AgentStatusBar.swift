// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Upstream agent status bar: left git+cwd · right chips + link dot.
struct AgentStatusBar: View {
    let chrome: SessionChrome
    let theme: GrokTheme
    let isConnected: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Text("←")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)

            if chrome.isWorktree {
                Text("worktree ")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.textSecondary)
            }

            if let git = chrome.gitDisplay {
                Text(git)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.textPrimary.opacity(0.8))
                    .lineLimit(1)
            }

            if !chrome.cwdDisplay.isEmpty {
                Text(chrome.cwdDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ForEach(Array(chrome.statusRightChips.enumerated()), id: \.offset) { index, chip in
                if index > 0 {
                    Text(" │ ")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textSecondary.opacity(0.45))
                }
                Text(chip)
                    .font(.caption2.monospaced())
                    .foregroundStyle(chip == "plan" ? theme.accentPlan : theme.textSecondary)
                    .lineLimit(1)
            }

            // Link status — top right, tiny dot only (no colored chrome).
            Circle()
                .fill(isConnected ? theme.accentSuccess : theme.accentError)
                .frame(width: 6, height: 6)
                .padding(.leading, 6)
                .accessibilityLabel(isConnected ? "connected" : "disconnected")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgBase)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.promptBorder).frame(height: 1)
        }
    }
}
