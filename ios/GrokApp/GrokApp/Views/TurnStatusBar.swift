// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Upstream turn_status: braille + activity + phaseTimer … turnTimer ⇣Nk [stop].
struct TurnStatusBar: View {
    let activity: String?
    let isRunning: Bool
    let turnStartedAt: Date?
    let phaseStartedAt: Date?
    let turnTokensUsed: Int?
    var queuedPromptCount: Int = 0
    let theme: GrokTheme
    let onStop: () -> Void

    private static let upstreamFrames = [
        "\u{280b}", "\u{2819}", "\u{2839}", "\u{2838}",
        "\u{283c}", "\u{2834}", "\u{2826}", "\u{2827}",
    ]

    @State private var frameIndex = 0
    @State private var now = Date()
    private let spinnerTimer = Timer.publish(every: 0.133, on: .main, in: .common).autoconnect()
    private let clockTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        if isRunning || queuedPromptCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if isRunning {
                    HStack(spacing: 6) {
                        Text(Self.upstreamFrames[frameIndex % Self.upstreamFrames.count])
                            .font(.body.monospaced())
                            .foregroundStyle(theme.running)
                            .frame(width: 14, alignment: .center)
                        Text(activity ?? "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.running)
                            .lineLimit(1)
                        if let phaseStartedAt {
                            Text(" \(FormatDuration.turnTimer(since: phaseStartedAt, now: now))")
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.gray)
                        }
                        Spacer(minLength: 4)
                        if let turnStartedAt {
                            HStack(spacing: 4) {
                                Text(FormatDuration.turnTimer(since: turnStartedAt, now: now))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.gray)
                                if let tokens = turnTokensUsed, tokens > 0 {
                                    Text("\u{21E3}\(FormatDuration.formatTokensShort(tokens))")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(theme.gray)
                                }
                            }
                        }
                        Button("[stop]", action: onStop)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.accentError)
                    }
                }
                // Upstream turn_status queue hint (only when agent reports queue).
                if queuedPromptCount > 0 {
                    Text("· \(queuedPromptCount) queued — Enter to send now")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                        .padding(.leading, isRunning ? 22 : 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.bgHighlight.opacity(0.35))
            .onReceive(spinnerTimer) { _ in
                frameIndex = (frameIndex + 1) % Self.upstreamFrames.count
            }
            .onReceive(clockTimer) { _ in
                now = .now
            }
        }
    }
}
