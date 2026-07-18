// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Agent session: upstream pager chrome only (status + scrollback + turn + prompt).
struct AgentSessionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        VStack(spacing: 0) {
            AgentStatusBar(
                chrome: model.chrome,
                theme: theme,
                isConnected: model.acp.sessionReady || (model.acp.isConnected && model.acp.isPaired),
                onBack: { model.showWelcome() }
            )
            if let banner = model.reconnectBanner {
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.textSecondary)
                        .frame(width: 6, height: 6)
                    Text(banner)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 0)
                    if banner.contains("Setup") {
                        Button("Setup") { model.showOnboarding() }
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.bgBase)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.promptBorder).frame(height: 1)
                }
            }
            ScrollbackView(
                entries: model.messages,
                theme: theme,
                showTimestamps: model.showTimestamps,
                onToggleFold: { id in model.acp.tracker.toggleFold(id: id) },
                onOpenMermaid: { source in await model.renderMermaidPNG(source: source) }
            )
            .background(theme.bgTerminal)
            if let permission = model.permissionRequest {
                PermissionBanner(
                    message: permission.message,
                    options: permission.options,
                    selectedOptionId: permission.selectedOptionId,
                    theme: theme,
                    onSelect: { model.selectPermission(optionId: $0) }
                )
            }
            if model.isThemeDraft {
                ThemeSuggestDropdown(
                    themes: model.availableThemes,
                    activeTheme: model.themeName,
                    theme: theme,
                    onSelect: { model.selectThemeFromDraft($0) }
                )
            } else if model.atFileQuery != nil {
                FileSuggestDropdown(
                    files: model.filteredAtFiles,
                    theme: theme,
                    onSelect: { model.insertAtFile($0) }
                )
                .task { await model.refreshWorkspaceFiles() }
            } else if model.draft.hasPrefix("/") {
                SlashDropdown(
                    commands: model.filteredSlashCommands,
                    theme: theme,
                    onSelect: { cmd in
                        model.draft = cmd.name + " "
                    }
                )
            }
            TurnStatusBar(
                activity: model.chrome.turnActivity,
                isRunning: model.acp.isRunning,
                turnStartedAt: model.chrome.turnStartedAt,
                phaseStartedAt: model.chrome.phaseStartedAt,
                turnTokensUsed: model.chrome.turnTokensUsed,
                queuedPromptCount: model.chrome.queuedPromptCount,
                theme: theme,
                onStop: { model.stopTurn() }
            )
            PromptBar(
                draft: $model.draft,
                isFocused: $model.isPromptFocused,
                modelLine: model.chrome.promptInfoLine,
                theme: theme,
                onSend: { model.sendDraft() }
            )
            .onChange(of: model.draft) { _, newValue in
                if newValue.contains("@") {
                    Task { await model.refreshWorkspaceFiles() }
                }
            }
        }
        .background(theme.bgBase)
    }
}

#Preview {
    AgentSessionView()
        .environmentObject(AppModel())
}
