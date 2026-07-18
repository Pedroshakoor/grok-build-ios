// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Agent message markdown — full parse when available, inline fallback.
/// Mermaid fences are split out for `mermaid_content` affordance row (no PNG on iOS).
enum MarkdownLite {
    enum Segment: Equatable {
        case markdown(String)
        case mermaid(String)
    }

    static func segments(_ raw: String) -> [Segment] {
        var out: [Segment] = []
        var rest = raw
        while let open = rest.range(of: "```", options: []) {
            let before = String(rest[..<open.lowerBound])
            if !before.isEmpty { out.append(.markdown(before)) }
            let afterOpen = rest[open.upperBound...]
            guard let nl = afterOpen.firstIndex(of: "\n") else {
                out.append(.markdown("```" + afterOpen))
                return out
            }
            let info = String(afterOpen[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = afterOpen.index(after: nl)
            let bodyAndRest = String(afterOpen[bodyStart...])
            guard let close = bodyAndRest.range(of: "```") else {
                out.append(.markdown("```" + info + "\n" + bodyAndRest))
                return out
            }
            let body = String(bodyAndRest[..<close.lowerBound])
            if isMermaidInfo(info) {
                out.append(.mermaid(body.trimmingCharacters(in: .newlines)))
            } else {
                out.append(.markdown("```\(info)\n\(body)```"))
            }
            rest = String(bodyAndRest[close.upperBound...])
        }
        if !rest.isEmpty { out.append(.markdown(rest)) }
        return out.isEmpty ? [.markdown(raw)] : out
    }

    private static func isMermaidInfo(_ info: String) -> Bool {
        info.split(whereSeparator: { $0.isWhitespace }).first.map { $0.lowercased() == "mermaid" } ?? false
    }

    static func attributed(_ raw: String) -> AttributedString {
        if let parsed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            return parsed
        }
        let normalized = normalizeHeaders(raw)
        if let parsed = try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return parsed
        }
        return AttributedString(raw)
    }

    private static func normalizeHeaders(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let s = String(line)
            if let match = s.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let rest = s[match.upperBound...].trimmingCharacters(in: .whitespaces)
                return "**\(rest)**"
            }
            return s
        }.joined(separator: "\n")
    }
}
