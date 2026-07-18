// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Upstream `util::format_duration` / `turn_status::format_turn_timer`.
enum FormatDuration {
    static func turnTimer(since start: Date, now: Date = .now) -> String {
        formatTurnTimer(now.timeIntervalSince(start))
    }

    static func formatTurnTimer(_ interval: TimeInterval) -> String {
        let totalSecs = Int(interval)
        if totalSecs < 10 {
            return String(format: "%.1fs", interval)
        }
        if totalSecs < 60 {
            return "\(totalSecs)s"
        }
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        if mins < 60 {
            return "\(mins)m\(secs)s"
        }
        let hours = mins / 60
        let remainingMins = mins % 60
        return "\(hours)h\(remainingMins)m"
    }

    /// Short token count for turn status (`turn_status::format_tokens_short`).
    static func formatTokensShort(_ tokens: Int) -> String {
        let n = UInt64(max(0, tokens))
        if n < 1_000 { return "\(n)" }
        if n < 10_000 { return String(format: "%.2fk", Double(n) / 1_000.0) }
        if n < 100_000 { return String(format: "%.1fk", Double(n) / 1_000.0) }
        if n < 1_000_000 { return "\(n / 1_000)k" }
        if n < 10_000_000 { return String(format: "%.2fm", Double(n) / 1_000_000.0) }
        return String(format: "%.1fm", Double(n) / 1_000_000.0)
    }

    /// Upstream short message timestamp (`entry_renderer` h:mm AM/PM).
    static func messageTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
