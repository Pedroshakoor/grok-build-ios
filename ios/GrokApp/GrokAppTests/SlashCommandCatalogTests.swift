// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import GrokApp

final class SlashCommandCatalogTests: XCTestCase {
    func testResolveAlias() {
        XCTAssertEqual(SlashCommandCatalog.resolve("/t"), "/theme")
        XCTAssertEqual(SlashCommandCatalog.resolve("/clear"), "/new")
    }

    func testCatalogIncludesPlan() {
        XCTAssertTrue(SlashCommandCatalog.builtins.contains { $0.id == "plan" })
    }

    func testCatalogIncludesUpstreamDocsCommands() {
        let ids = Set(SlashCommandCatalog.builtins.map(\.id))
        for required in ["new", "resume", "theme", "settings", "always-approve", "plan", "quit", "model", "compact"] {
            XCTAssertTrue(ids.contains(required), "missing /\(required)")
        }
    }
}
