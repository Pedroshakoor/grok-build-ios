// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// In-prompt `@` file suggest (same slot as SlashDropdown).
struct FileSuggestDropdown: View {
    let files: [String]
    let theme: GrokTheme
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.promptBorder)
                .frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    if files.isEmpty {
                        Text("No files")
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(files, id: \.self) { path in
                            Button {
                                onSelect(path)
                            } label: {
                                Text(path)
                                    .font(.body.monospaced())
                                    .foregroundStyle(theme.path)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if path != files.last {
                                Rectangle()
                                    .fill(theme.promptBorder.opacity(0.5))
                                    .frame(height: 1)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .background(theme.bgHighlight)
        }
    }
}
