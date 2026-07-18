// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CommonCrypto
import Network
import Security

/// Captures the leaf cert fingerprint during a TLS handshake (TOFU / first pair).
final class TLSFingerprintCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    var fingerprint: String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ fp: String) {
        lock.lock()
        value = fp
        lock.unlock()
    }

    func clear() {
        lock.lock()
        value = nil
        lock.unlock()
    }
}

enum CompanionTLS {
    /// - Parameters:
    ///   - pinnedFingerprint: When set, require exact/prefix match (re-pair).
    ///   - capture: When pin is empty, accept the leaf once (TOFU) and record its fingerprint.
    static func connectionParameters(
        useTLS: Bool,
        pinnedFingerprint: String?,
        capture: TLSFingerprintCapture? = nil
    ) -> NWParameters {
        guard useTLS else { return .tcp }
        let tls = NWProtocolTLS.Options()
        let expected = pinnedFingerprint?
            .lowercased()
            .filter(\.isHexDigit) ?? ""

        if !expected.isEmpty {
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, trust, complete in
                    guard let fp = leafFingerprint(trust: trust) else {
                        complete(false)
                        return
                    }
                    let match = fp == expected
                        || (expected.count >= 16 && expected.count < 64 && fp.hasPrefix(expected))
                    if match { capture?.set(fp) }
                    complete(match)
                },
                DispatchQueue.global(qos: .userInitiated)
            )
        } else {
            // PIN-only first pair: trust this leaf, remember fingerprint after PIN succeeds.
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, trust, complete in
                    guard let fp = leafFingerprint(trust: trust) else {
                        complete(false)
                        return
                    }
                    capture?.set(fp)
                    complete(true)
                },
                DispatchQueue.global(qos: .userInitiated)
            )
        }
        return NWParameters(tls: tls)
    }

    /// Must use `sec_trust_copy_ref` — `unsafeBitCast` to SecTrust crashes (SIGSEGV).
    private static func leafFingerprint(trust: sec_trust_t) -> String? {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue() as SecTrust
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
              let cert = chain.first else { return nil }
        let data = SecCertificateCopyData(cert) as Data
        return SHA256.hex(data)
    }
}

private enum SHA256 {
    static func hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
