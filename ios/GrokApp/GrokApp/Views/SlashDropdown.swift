// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Slash command dropdown — name column + summary (pager slash_dropdown layout).
struct SlashDropdown: View {
    let commands: [SlashCommand]
    let theme: GrokTheme
    let onSelect: (SlashCommand) -> Void

    private var nameWidth: CGFloat {
        let longest = commands.map(\.name.count).max() ?? 8
        return CGFloat(max(longest, 8)) * 8.5
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.promptBorder)
                .frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(commands) { command in
                        Button {
                            onSelect(command)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(command.name)
                                    .font(.body.monospaced())
                                    .foregroundStyle(theme.command)
                                    .frame(width: nameWidth, alignment: .leading)
                                Text(command.summary)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if command.id != commands.last?.id {
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

#Preview {
    SlashDropdown(
        commands: SlashCommand.builtins,
        theme: .grokNightFallback,
        onSelect: { _ in }
    )
}
