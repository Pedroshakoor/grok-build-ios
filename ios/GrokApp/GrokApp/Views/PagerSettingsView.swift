// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Pager-local + shell-owned settings (`settings/defs.rs`).
/// Shell keys read/write Mac `~/.grok/config.toml` via companion RPC.
struct PagerSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private let mermaidChoices = ["auto", "on", "off"]
    private let permissionChoices = ["default", "ask", "auto", "always_approve"]

    var body: some View {
        let theme = model.theme
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("←") { model.showWelcome() }
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary)
                Text("Settings")
                    .font(.body.weight(.semibold).monospaced())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.bgBase)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.promptBorder).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Appearance", theme: theme)
                    toggleRow(
                        label: "Show timestamps",
                        description: "Show clock time next to user messages and agent responses.",
                        isOn: Binding(
                            get: { model.shellConfig["show_timestamps"] ?? model.showTimestamps },
                            set: { newValue in
                                model.showTimestamps = newValue
                                AppSettings.showTimestamps = newValue
                                Task { await model.setShellBool("show_timestamps", newValue) }
                            }
                        ),
                        theme: theme
                    )
                    divider(theme)
                    toggleRow(
                        label: "Show thinking blocks",
                        description: "Show agent thinking/reasoning blocks in the scrollback while streaming.",
                        isOn: Binding(
                            get: { model.shellConfig["show_thinking_blocks"] ?? model.showThinkingBlocks },
                            set: { newValue in
                                model.showThinkingBlocks = newValue
                                AppSettings.showThinkingBlocks = newValue
                                model.refreshDisplayedMessages()
                                Task { await model.setShellBool("show_thinking_blocks", newValue) }
                            }
                        ),
                        theme: theme
                    )
                    divider(theme)
                    toggleRow(
                        label: "Group tool calls",
                        description: "Fold consecutive read/search/list tool calls into one summary row.",
                        isOn: Binding(
                            get: { model.shellConfig["group_tool_verbs"] ?? true },
                            set: { newValue in
                                model.shellConfig["group_tool_verbs"] = newValue
                                Task { await model.setShellBool("group_tool_verbs", newValue) }
                            }
                        ),
                        theme: theme
                    )
                    divider(theme)
                    enumRow(
                        label: "Render Mermaid diagrams",
                        description: "auto/on add a clickable row to open the rendered diagram; off shows raw source.",
                        value: model.shellConfigStrings["render_mermaid"] ?? "auto",
                        choices: mermaidChoices,
                        theme: theme
                    ) { choice in
                        Task { await model.setShellString("render_mermaid", choice) }
                    }
                    divider(theme)
                    Button {
                        model.draft = "/theme "
                        model.showAgent()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Theme")
                                .font(.body.monospaced())
                                .foregroundStyle(theme.textPrimary)
                            Text("Color theme for the pager UI. Current: \(model.themeName)")
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    sectionHeader("Agent", theme: theme)
                    enumRow(
                        label: "Permission mode",
                        description: "Default / Ask / Auto / Always approve for tool permissions.",
                        value: model.shellConfigStrings["permission_mode"] ?? "default",
                        choices: permissionChoices,
                        theme: theme
                    ) { choice in
                        Task { await model.setShellString("permission_mode", choice) }
                    }
                    divider(theme)
                    toggleRow(
                        label: "Remember tool approvals",
                        description: "Show Always allow options in permission prompts. Restart may be required.",
                        isOn: Binding(
                            get: { model.shellConfig["remember_tool_approvals"] ?? false },
                            set: { newValue in
                                model.shellConfig["remember_tool_approvals"] = newValue
                                Task { await model.setShellBool("remember_tool_approvals", newValue) }
                            }
                        ),
                        theme: theme
                    )

                    sectionHeader("Phone", theme: theme)
                    Button {
                        model.showCompanionSettings()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Companion")
                                .font(.body.monospaced())
                                .foregroundStyle(theme.textPrimary)
                            Text("API key and Mac companion connection (phone-only).")
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(theme.bgTerminal)
        }
        .background(theme.bgBase)
        .task { await model.reloadShellConfig() }
    }

    private func sectionHeader(_ title: String, theme: GrokTheme) -> some View {
        Text(title.uppercased())
            .font(.caption2.monospaced())
            .foregroundStyle(theme.gray)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func divider(_ theme: GrokTheme) -> some View {
        Rectangle()
            .fill(theme.promptBorder.opacity(0.35))
            .frame(height: 1)
            .padding(.leading, 12)
    }

    private func toggleRow(
        label: String,
        description: String,
        isOn: Binding<Bool>,
        theme: GrokTheme
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                Text(description)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .tint(theme.accentSuccess)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func enumRow(
        label: String,
        description: String,
        value: String,
        choices: [String],
        theme: GrokTheme,
        onPick: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.body.monospaced())
                .foregroundStyle(theme.textPrimary)
            Text(description)
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Button(choice) { onPick(choice) }
                        .font(.caption.monospaced())
                        .foregroundStyle(choice == value ? theme.accentSystem : theme.textSecondary)
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}
