// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Upstream welcome (`xai-grok-pager` welcome/): top_bar + braille logo + menu.
/// No bottom prompt on Welcome — start via New worktree / Resume / Setup.
struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        GeometryReader { geo in
            // Geometry can be 0 on first pass — don't hide logo briefly.
            let height = geo.size.height > 100 ? geo.size.height : 900
            VStack(spacing: 0) {
                welcomeTopBar(theme: theme)

                Spacer(minLength: 12)

                WelcomeLogoView(theme: theme, windowHeightPoints: height)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(menuRows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.promptBorder.opacity(0.35))
                                .frame(height: 1)
                        }
                        welcomeRow(label: row.label, shortcut: row.shortcut, theme: theme, action: row.action)
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 420)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "#141414").ignoresSafeArea())
        }
        .background(theme.bgBase.ignoresSafeArea())
    }

    @ViewBuilder
    private func welcomeTopBar(theme: GrokTheme) -> some View {
        let loc = CompanionConfig.welcomeLocation()
        let cwd = model.chrome.cwd.isEmpty ? loc.cwd : model.chrome.cwd
        let branch = model.chrome.gitBranch ?? loc.gitBranch
        let worktree = model.chrome.isWorktree || loc.isWorktree
        if cwd.isEmpty && branch == nil {
            Color.clear.frame(height: 8)
        } else {
            HStack(spacing: 6) {
                if let branch {
                    Text(branch.isEmpty ? "⎇ detached" : "⎇ \(branch)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textPrimary.opacity(0.75))
                        .lineLimit(1)
                }
                if worktree {
                    Text("worktree ")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentUser)
                }
                if !cwd.isEmpty {
                    Text(SessionChrome(cwd: cwd).cwdDisplay)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.grayDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private struct MenuRow {
        let label: String
        let shortcut: String
        let action: () -> Void
    }

    private var menuRows: [MenuRow] {
        var rows: [MenuRow] = [
            MenuRow(label: "New worktree", shortcut: "ctrl+w", action: {
                guard model.canStartSession else { model.showOnboarding(); return }
                model.startNewSession()
            }),
            MenuRow(label: "Resume session", shortcut: "ctrl+s", action: {
                guard model.canStartSession else { model.showOnboarding(); return }
                model.resumeSessionFromWelcome()
            }),
        ]
        if model.hasChangelog {
            rows.append(MenuRow(label: "Changelog", shortcut: "", action: {
                model.showChangelog()
            }))
        }
        rows.append(MenuRow(label: "Setup", shortcut: "", action: {
            model.showOnboarding()
        }))
        rows.append(MenuRow(label: "Quit", shortcut: "ctrl+q", action: {
            model.quitFromWelcome()
        }))
        return rows
    }

    private func welcomeRow(label: String, shortcut: String, theme: GrokTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.body.weight(.semibold).monospaced())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AppModel())
}
