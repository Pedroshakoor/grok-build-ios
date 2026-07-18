// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// UserDefaults-backed appearance toggles (`appearance/cache.rs` defaults).
enum AppSettings {
    private static let showTimestampsKey = "GROK_SHOW_TIMESTAMPS"
    private static let showThinkingBlocksKey = "GROK_SHOW_THINKING_BLOCKS"

    static var showTimestamps: Bool {
        get {
            if UserDefaults.standard.object(forKey: showTimestampsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showTimestampsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showTimestampsKey) }
    }

    static var showThinkingBlocks: Bool {
        get {
            if UserDefaults.standard.object(forKey: showThinkingBlocksKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showThinkingBlocksKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showThinkingBlocksKey) }
    }
}
