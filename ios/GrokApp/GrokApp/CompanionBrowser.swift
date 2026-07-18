// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network

struct CompanionPeer: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    /// Full SHA-256 DER fingerprint from Bonjour TXT `fp=` (64 hex).
    let fingerprint: String?
    /// First 16 hex for UI.
    var fingerprintShort: String? {
        guard let fingerprint, fingerprint.count >= 16 else { return fingerprint }
        return String(fingerprint.prefix(16))
    }
}

/// Bonjour browser for `_grok-build._tcp` companions on the local network.
@MainActor
final class CompanionBrowser: ObservableObject {
    @Published private(set) var peers: [CompanionPeer] = []
    @Published private(set) var isBrowsing = false
    @Published var lastError: String?

    private var browser: NWBrowser?

    func start() {
        stop()
        lastError = nil
        let descriptor = NWBrowser.Descriptor.bonjour(type: CompanionConfig.bonjourType, domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser
        isBrowsing = true

        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready: self.isBrowsing = true
                case .failed(let error):
                    self.isBrowsing = false
                    self.lastError = error.localizedDescription
                case .cancelled: self.isBrowsing = false
                default: break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.peers = results.compactMap { result in
                    let fp = Self.txtFingerprint(result.metadata)
                    guard case .service(let name, _, _, _) = result.endpoint else {
                        return CompanionPeer(
                            id: String(describing: result.endpoint),
                            name: "Grok Build",
                            endpoint: result.endpoint,
                            fingerprint: fp
                        )
                    }
                    return CompanionPeer(id: name, name: name, endpoint: result.endpoint, fingerprint: fp)
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }

        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    /// Prefer full `fp=` (64 hex). Fall back to legacy short `fps=` / short `fp=`.
    private static func txtFingerprint(_ metadata: NWBrowser.Result.Metadata) -> String? {
        guard case .bonjour(let txt) = metadata else { return nil }
        let dict = txt.dictionary
        if let full = dict["fp"]?.lowercased().filter(\.isHexDigit), full.count == 64 {
            return full
        }
        if let fps = dict["fps"]?.lowercased().filter(\.isHexDigit), !fps.isEmpty {
            return fps
        }
        if let fp = dict["fp"]?.lowercased().filter(\.isHexDigit), !fp.isEmpty {
            return fp
        }
        return nil
    }
}
