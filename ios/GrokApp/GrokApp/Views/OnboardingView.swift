// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Field?
    @State private var showAdvanced = false
    @State private var showLegacyBridge = false
    var isSettings: Bool = false

    private enum Field { case apiKey, host, port, secret, fingerprint }

    private var isChecking: Bool {
        if case .checking = model.connectionPhase { return true }
        return false
    }

    private var isConnectedOK: Bool {
        if case .succeeded = model.connectionPhase { return true }
        return model.acp.sessionReady
    }

    var body: some View {
        let theme = model.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(theme: theme)
                secretConnectSection(theme: theme)
                connectionStatus(theme: theme)

                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    advancedSection(theme: theme)
                }
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
                .tint(theme.textPrimary)

                if showAdvanced {
                    DisclosureGroup("Legacy LAN bridge (Bonjour + PIN)", isExpanded: $showLegacyBridge) {
                        legacyBridgeSection(theme: theme)
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .tint(theme.textPrimary)
                }

                if model.hasAPIKey || !model.apiKeyDraft.isEmpty {
                    Button("Sign out") { model.signOut() }
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .disabled(isChecking)
                }
            }
            .padding(24)
        }
        .background(theme.bgBase)
        .onAppear {
            model.loadConnectionDrafts()
            if model.acpHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.acpHostDraft = "127.0.0.1"
            }
            if model.acpPortDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.acpPortDraft == "7391" {
                model.acpPortDraft = String(CompanionConfig.defaultWebSocketPort)
            }
        }
        .onChange(of: showLegacyBridge) { _, browsing in
            if browsing {
                model.startLegacyBonjourBrowse()
            } else {
                model.stopLegacyBonjourBrowse()
                model.clearBonjourPreference()
            }
        }
        .onDisappear { model.stopLegacyBonjourBrowse() }
    }

    private func header(theme: GrokTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("← Back") { model.showWelcome() }
                .font(.body.monospaced())
                .foregroundStyle(theme.textSecondary)
                .disabled(isChecking)
            Text(isSettings ? "Connection" : "Setup")
                .font(.title3.monospaced().weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Run official `grok agent serve` on your Mac. Paste the Secret here.")
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func secretConnectSection(theme: GrokTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac terminal (official CLI)")
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
            Text("export XAI_API_KEY=xai-...\ngrok agent serve\n# copy the Secret line")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))

            Text("Secret")
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
            TextField("from grok agent serve", text: $model.pairPinDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.title3.monospaced())
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(focused == .secret ? theme.textPrimary : theme.promptBorder, lineWidth: 1))
                .focused($focused, equals: .secret)
                .disabled(isChecking || isConnectedOK)

            if isConnectedOK {
                HStack(spacing: 8) {
                    Circle().fill(theme.accentSuccess).frame(width: 6, height: 6)
                    Text("connected")
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            } else {
                Button {
                    model.connectWithPINAndVerify()
                } label: {
                    HStack(spacing: 8) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(theme.textPrimary)
                        }
                        Text(isChecking ? "connecting…" : "connect")
                            .font(.body.monospaced())
                            .foregroundStyle(theme.bgBase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
            }
        }
    }

    @ViewBuilder
    private func connectionStatus(theme: GrokTheme) -> some View {
        switch model.connectionPhase {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                Circle().fill(theme.textSecondary).frame(width: 6, height: 6)
                Text("connecting…")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
            }
        case .succeeded:
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    model.finishSetupAfterSuccessfulConnect()
                } label: {
                    Text("continue")
                        .font(.body.monospaced())
                        .foregroundStyle(theme.bgBase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(theme.accentError).frame(width: 6, height: 6).padding(.top, 4)
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }

    private func advancedSection(theme: GrokTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("host / port for grok agent serve (default 127.0.0.1:2419)")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.textSecondary)
            TextField("host", text: $model.acpHostDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .padding(10)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                .focused($focused, equals: .host)
                .disabled(isChecking)
            TextField("port", text: $model.acpPortDraft)
                .keyboardType(.numberPad)
                .font(.caption.monospaced())
                .padding(10)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                .focused($focused, equals: .port)
                .disabled(isChecking)
            SecureField("optional phone API key", text: $model.apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .padding(10)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                .focused($focused, equals: .apiKey)
                .disabled(isChecking)
        }
        .padding(.top, 8)
    }

    private func legacyBridgeSection(theme: GrokTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Experimental Python TLS bridge on LAN — not the default path.")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.textSecondary)
            if model.companionBrowser.peers.isEmpty {
                Text("No Bonjour peers found")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(model.companionBrowser.peers) { peer in
                    Button {
                        model.selectBonjourPeer(peer)
                    } label: {
                        HStack {
                            Text(peer.name)
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            if let short = peer.fingerprintShort {
                                Text(short)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(theme.bgTerminal)
                        .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("TLS cert fingerprint (optional)", text: $model.fingerprintDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .padding(10)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                .focused($focused, equals: .fingerprint)
                .disabled(isChecking)
        }
        .padding(.top, 8)
    }
}
