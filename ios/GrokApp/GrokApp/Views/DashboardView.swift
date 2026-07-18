// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Upstream dashboard surface (`views/dashboard/render.rs`).
/// Live roster via `x.ai/sessions/list` + `x.ai/sessions/changed`.
/// Dense peek without attach is pager-local only — open row uses session/load.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let theme = model.theme
        let rows = model.dashboardRows
        VStack(spacing: 0) {
            HStack {
                Button(action: { model.showWelcome() }) {
                    Text("←")
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                Text(dashboardTitle(rows: rows))
                    .font(.body.weight(.semibold).monospaced())
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button(action: { model.startNewSessionFromDashboard() }) {
                    Text("[+ New Agent]")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.bgBase)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.promptBorder).frame(height: 1)
            }

            if rows.isEmpty {
                // Exact upstream empty hint (render_dashboard_banner).
                Text(" No sessions yet — Esc to dispatch one. ")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            Button {
                                model.openDashboardRow(row)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(row.bullet)
                                        .font(.body.monospaced())
                                        .foregroundStyle(theme.textSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.title)
                                            .font(.body.monospaced())
                                            .foregroundStyle(theme.textPrimary)
                                            .lineLimit(1)
                                        if let activity = row.activity {
                                            Text(activity)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(theme.running)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if let age = row.ageLabel {
                                        Text(age)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                }
                                .padding(.leading, CGFloat(row.indent) * 16)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgTerminal)
    }

    /// `Dashboard · N agents · M working` / `… awaiting` — render.rs title_parts.
    private func dashboardTitle(rows: [DashboardRowModel]) -> String {
        let top = rows.filter { $0.indent == 0 }
        let total = top.count
        let working = top.filter { $0.state == .working }.count
        let awaiting = top.filter { $0.state == .needsInput }.count
        let agentWord = total == 1 ? "agent" : "agents"
        var parts = ["Dashboard", "\(total) \(agentWord)"]
        if working > 0 { parts.append("\(working) working") }
        if awaiting > 0 { parts.append("\(awaiting) awaiting") }
        return parts.joined(separator: " · ")
    }
}
