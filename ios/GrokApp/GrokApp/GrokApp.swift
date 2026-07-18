// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
struct GrokApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                // Hard bg so launch never flashes the default white window.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "#141414").ignoresSafeArea())
                .background(model.theme.bgBase.ignoresSafeArea())
                .preferredColorScheme(model.themeName.lowercased().contains("day") ? .light : .dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.reconnectTransportIfNeeded()
                    }
                }
        }
    }
}
