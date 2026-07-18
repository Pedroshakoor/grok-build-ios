// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// `@` file attach — pager uses in-prompt fuzzy; phone keeps a list screen.
/// Empty list when companion has no files (no invented fake paths).
struct FilePickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("←") { model.showAgent() }
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                Text("@")
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

            HStack(spacing: 0) {
                Text("❯ ")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.accentUser)
                TextField("Filter…", text: $model.fileFilter)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.bgTerminal)

            if model.filteredWorkspaceFiles.isEmpty {
                Text(model.fileFilter.isEmpty ? " No files from companion yet. " : " No matches. ")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .background(theme.bgTerminal)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.filteredWorkspaceFiles, id: \.self) { path in
                            Button { model.insertFileReference(path) } label: {
                                Text(path)
                                    .font(.body.monospaced())
                                    .foregroundStyle(theme.path)
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
        .task { await model.refreshWorkspaceFiles() }
    }
}
