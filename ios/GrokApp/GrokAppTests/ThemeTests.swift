// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import GrokApp

final class ThemeTests: XCTestCase {
    private func tokens(named name: String) throws -> [String: String] {
        // Prefer app bundle (hosted tests); fall back to shared/themes on disk.
        let bundled =
            Bundle(for: AppModel.self).url(forResource: name, withExtension: "json", subdirectory: "themes")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "themes")
        let url: URL
        if let bundled {
            url = bundled
        } else {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // GrokAppTests
                .deletingLastPathComponent() // ios/GrokApp
                .deletingLastPathComponent() // ios
                .deletingLastPathComponent() // GROK APP
            url = root.appendingPathComponent("shared/themes/\(name).json")
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["tokens"] as? [String: String])
    }

    func testGrokNightJSONMatchesUpstreamGroknightRs() throws {
        let json = try tokens(named: "groknight")
        XCTAssertEqual(json["bg_terminal"], "#0a0a0a")
        XCTAssertEqual(json["bg_base"], "#141414")
        XCTAssertEqual(json["bg_highlight"], "#242424")
        XCTAssertEqual(json["text_primary"], "#e1e1e1")
        XCTAssertEqual(json["text_secondary"], "#c8c8c8")
        XCTAssertEqual(json["accent_assistant"], "#bb9af7")
        XCTAssertEqual(json["accent_system"], "#7aa2f7")
        XCTAssertEqual(json["accent_error"], "#f7768e")
        XCTAssertEqual(json["accent_success"], "#9ece6a")
        XCTAssertEqual(json["command"], "#e0af68")
        XCTAssertEqual(json["path"], "#ff9e64")
        XCTAssertEqual(json["running"], "#7dcfff")
        XCTAssertEqual(json["prompt_border"], "#323237")
        XCTAssertEqual(json["prompt_border_active"], "#505058")
    }

    func testGrokDayJSONMatchesUpstreamGrokdayRs() throws {
        let json = try tokens(named: "grokday")
        XCTAssertEqual(json["bg_terminal"], "#f5f5f5")
        XCTAssertEqual(json["bg_base"], "#eeeeee")
        XCTAssertEqual(json["text_primary"], "#262626")
        XCTAssertEqual(json["accent_assistant"], "#7d4bc6")
    }

    func testLoadGrokNightFromBundle() {
        let theme = GrokTheme.load(named: "GrokNight")
        XCTAssertEqual(theme.name.lowercased(), "groknight")
        XCTAssertTrue(theme.bgBase.matchesHex("#141414"))
        XCTAssertTrue(theme.accentAssistant.matchesHex("#bb9af7"))
    }

    func testFallbackGrokNightMatchesJSON() throws {
        let json = try tokens(named: "groknight")
        let fallback = GrokTheme.grokNightFallback
        XCTAssertTrue(fallback.bgTerminal.matchesHex(json["bg_terminal"] ?? ""))
        XCTAssertTrue(fallback.bgBase.matchesHex(json["bg_base"] ?? ""))
        XCTAssertTrue(fallback.accentAssistant.matchesHex(json["accent_assistant"] ?? ""))
    }
}
