// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Dynamic ACP permission options (`permission_view.rs` numbered radio rows).
struct PermissionBanner: View {
    let message: String
    let options: [PermissionOption]
    let selectedOptionId: String?
    let theme: GrokTheme
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.body.weight(.semibold).monospaced())
                .foregroundStyle(theme.command)
            VStack(alignment: .leading, spacing: 6) {
                if options.isEmpty {
                    fallbackRow("Allow once", selected: false) { onSelect("allow-once") }
                    fallbackRow("Reject", selected: false) { onSelect("reject-once") }
                } else {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        optionRow(index: index + 1, option: option)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgHighlight)
    }

    private func optionRow(index: Int, option: PermissionOption) -> some View {
        let selected = option.optionId == selectedOptionId
        return Button {
            onSelect(option.optionId)
        } label: {
            HStack(spacing: 8) {
                Text("\(index) ")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.accentUser)
                Text(selected ? "(●)" : "(○)")
                    .font(.body.monospaced())
                    .foregroundStyle(selected ? theme.textPrimary : theme.gray)
                Text(option.name)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fallbackRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(selected ? "(●)" : "(○)")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.gray)
                Text(title)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
