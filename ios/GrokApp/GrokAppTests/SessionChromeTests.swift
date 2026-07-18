// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import GrokApp

final class SessionChromeTests: XCTestCase {
    func testFmtTokensMatchesUpstreamContextBar() {
        XCTAssertEqual(SessionChrome.fmtTokens(0), "0")
        XCTAssertEqual(SessionChrome.fmtTokens(999), "999")
        XCTAssertEqual(SessionChrome.fmtTokens(1200), "1.2K")
        XCTAssertEqual(SessionChrome.fmtTokens(12_300), "12K")
        XCTAssertEqual(SessionChrome.fmtTokens(1_500_000), "1.5M")
    }

    func testContextChipRequiresBothUsedAndTotal() {
        var chrome = SessionChrome()
        chrome.contextUsed = 12_300
        XCTAssertTrue(chrome.statusRightChips.isEmpty, "lone used count must not render")
        chrome.contextTotal = 1_000_000
        XCTAssertEqual(chrome.statusRightChips, ["12K / 1.0M"])
    }

    func testMcpAndCreditsChipsOnlyWhenPayloadPresent() {
        var chrome = SessionChrome()
        chrome.mcpConnected = 1
        chrome.mcpTotal = 0
        XCTAssertTrue(chrome.statusRightChips.isEmpty, "MCP seed total==0 must not chip")
        chrome.mcpTotal = 4
        XCTAssertEqual(chrome.statusRightChips, ["MCP (1/4)"])
        chrome.creditsUsedPercent = 25
        XCTAssertEqual(chrome.statusRightChips, ["MCP (1/4)", "Credits used: 25%"])
        chrome.goalPhaseLabel = "Executing"
        chrome.goalActive = true
        XCTAssertEqual(
            chrome.statusRightChips,
            ["Goal: Executing", "MCP (1/4)", "Credits used: 25%"]
        )
    }

    func testFormatTurnTimerMatchesUpstream() {
        XCTAssertEqual(FormatDuration.formatTurnTimer(5.2), "5.2s")
        XCTAssertEqual(FormatDuration.formatTurnTimer(32), "32s")
        XCTAssertEqual(FormatDuration.formatTurnTimer(80), "1m20s")
        XCTAssertEqual(FormatDuration.formatTurnTimer(3725), "1h2m")
    }

    func testAppSettingsDefaultsMatchUpstream() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "GROK_SHOW_TIMESTAMPS")
        defaults.removeObject(forKey: "GROK_SHOW_THINKING_BLOCKS")
        XCTAssertTrue(AppSettings.showTimestamps)
        XCTAssertTrue(AppSettings.showThinkingBlocks)
    }

    func testVerbGroupHeaderUsesDottedDiamond() {
        let members = [
            ScrollbackEntry(kind: .tool, text: "Read a.rs", isCollapsed: true, toolKind: "read", toolStatus: "completed"),
            ScrollbackEntry(kind: .tool, text: "Read b.rs", isCollapsed: true, toolKind: "read", toolStatus: "completed"),
        ]
        let label = VerbGroupLogic.fullHeader(for: members)
        XCTAssertTrue(label.hasPrefix("\u{25C8} "))
        XCTAssertTrue(label.contains("Read 2 files"))
    }

    func testBundledLogosMatchUpstreamBytes() throws {
        let names = ["logo05", "logo07"]
        for name in names {
            let bundled = try XCTUnwrap(
                Bundle(for: AppModel.self).url(forResource: name, withExtension: "txt")
                    ?? Bundle.main.url(forResource: name, withExtension: "txt")
            )
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let upstream = root
                .appendingPathComponent("upstream-grok-build/crates/codegen/xai-grok-pager/assets/logo/\(name).txt")
            let a = try Data(contentsOf: bundled)
            let b = try Data(contentsOf: upstream)
            XCTAssertEqual(a, b, "\(name).txt must be byte-identical to upstream")
        }
    }
}
