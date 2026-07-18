// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Resume session picker (`SessionPickerEntry` rows: cwd / title / id).
struct SessionPickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        VStack(spacing: 0) {
            HStack {
                Button("←") { model.showWelcome() }
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                Text("Resume session")
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

            if model.isLoadingSessions {
                Text("Loading…")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.sessionListEntries.isEmpty {
                Text("No sessions")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.sessionListEntries) { entry in
                            Button {
                                model.resumeSession(id: entry.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.body.monospaced())
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(2)
                                    if !entry.cwd.isEmpty {
                                        Text(entry.cwd)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(theme.path)
                                            .lineLimit(1)
                                    }
                                    Text(entry.id)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .background(theme.bgBase)
        .task { await model.refreshSessionList() }
    }
}
