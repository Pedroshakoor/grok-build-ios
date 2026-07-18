// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.screen {
        case .welcome:
            WelcomeView()
        case .onboarding, .settings:
            OnboardingView(isSettings: model.screen == .settings)
        case .pagerSettings:
            PagerSettingsView()
        case .agent:
            AgentSessionView()
        case .dashboard:
            DashboardView()
        case .themePicker:
            ThemePickerView()
        case .filePicker:
            FilePickerView()
        case .sessionPicker:
            SessionPickerView()
        case .changelog:
            ChangelogView()
        }
    }
}
