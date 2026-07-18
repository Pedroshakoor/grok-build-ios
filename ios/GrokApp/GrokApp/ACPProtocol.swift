// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Typed JSON-RPC models for Agent Client Protocol (ACP).
enum ACPProtocol {
    static let xaiAPIKeyMethodID = "xai.api_key"
    /// Official Grok Build coding model — lock after session/new so chat models (e.g. grok-4.3) are not used.
    static let preferredBuildModelId = "grok-build-0.1"
    static let workspaceListMethod = "workspace/list"
    static let sessionsListMethod = "x.ai/sessions/list"
    static let companionMermaidRenderMethod = "x.ai/companion/mermaid_render"
    static let companionConfigGetMethod = "x.ai/companion/config_get"
    static let companionConfigSetMethod = "x.ai/companion/config_set"
    static let billingMethod = "x.ai/billing"
    static let pairPrefix = "grok_pair"
    static let pairResultPrefix = "grok_pair_result"

    struct JSONRPCRequest: Encodable {
        let jsonrpc = "2.0"
        let method: String
        let params: JSONValue
        let id: Int
    }

    struct JSONRPCResponse: Decodable {
        let jsonrpc: String?
        let id: JSONValue?
        let result: JSONValue?
        let error: JSONRPCError?
        let method: String?
        let params: JSONValue?
    }

    struct JSONRPCError: Decodable {
        let code: Int?
        let message: String?
        let data: String?
    }

    struct PairRequest: Encodable {
        let grok_pair: PairBody
    }

    struct PairBody: Encodable {
        var pin: String?
        var token: String?
    }

    struct PairResultEnvelope: Decodable {
        let grok_pair_result: PairResult
    }

    struct PairResult: Decodable {
        let ok: Bool
        let token: String?
        let error: String?
    }

    enum JSONValue: Codable, Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null; return }
            if let v = try? container.decode(Bool.self) { self = .bool(v); return }
            if let v = try? container.decode(Int.self) { self = .int(v); return }
            if let v = try? container.decode(Double.self) { self = .double(v); return }
            if let v = try? container.decode(String.self) { self = .string(v); return }
            if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
            if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .int(let v): try container.encode(v)
            case .double(let v): try container.encode(v)
            case .bool(let v): try container.encode(v)
            case .object(let v): try container.encode(v)
            case .array(let v): try container.encode(v)
            case .null: try container.encodeNil()
            }
        }

        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }

        var intValue: Int? {
            switch self {
            case .int(let i): return i
            case .double(let d): return Int(d)
            case .string(let s): return Int(s)
            default: return nil
            }
        }

        var boolValue: Bool? {
            if case .bool(let b) = self { return b }
            return nil
        }

        var doubleValue: Double? {
            switch self {
            case .double(let d): return d
            case .int(let i): return Double(i)
            case .string(let s): return Double(s)
            default: return nil
            }
        }

        var objectValue: [String: JSONValue]? {
            if case .object(let o) = self { return o }
            return nil
        }

        var arrayValue: [JSONValue]? {
            if case .array(let a) = self { return a }
            return nil
        }

        subscript(key: String) -> JSONValue? {
            objectValue?[key]
        }
    }

    static func encodeLine<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        guard let data = try? encoder.encode(value) else { return nil }
        guard var line = String(data: data, encoding: .utf8) else { return nil }
        line = line.replacingOccurrences(of: "\\/", with: "/")
        line.append("\n")
        return Data(line.utf8)
    }

    static func decodeLine(_ line: String) -> JSONRPCResponse? {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONRPCResponse.self, from: data)
    }

    static func decodePairResult(_ line: String) -> PairResult? {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PairResultEnvelope.self, from: data).grok_pair_result
    }

    static func initializeParams() -> JSONValue {
        .object([
            "protocolVersion": .int(1),
            "clientCapabilities": .object([
                "fs": .object([
                    "readTextFile": .bool(false),
                    "writeTextFile": .bool(false),
                ]),
            ]),
        ])
    }

    static func authenticateParams(apiKey: String?) -> JSONValue {
        var meta: [String: JSONValue] = [:]
        if let apiKey, !apiKey.isEmpty {
            meta["xaiApiKey"] = .string(apiKey)
        }
        return .object([
            "methodId": .string(xaiAPIKeyMethodID),
            "_meta": .object(meta),
        ])
    }

    static func sessionNewParams() -> JSONValue {
        // Official `grok agent serve` requires an absolute cwd (relative "." → -32602).
        .object([
            "cwd": .string(CompanionConfig.workspaceCwd()),
            "mcpServers": .array([]),
        ])
    }

    static func sessionSetModelParams(sessionId: String, modelId: String) -> JSONValue {
        .object([
            "sessionId": .string(sessionId),
            "modelId": .string(modelId),
        ])
    }

    static func sessionPromptParams(sessionId: String, text: String) -> JSONValue {
        .object([
            "sessionId": .string(sessionId),
            "prompt": .array([
                .object(["type": .string("text"), "text": .string(text)]),
            ]),
        ])
    }

    struct JSONRPCReply: Encodable {
        let jsonrpc: String
        let id: JSONValue
        let result: JSONValue
    }

    static func permissionReply(id: JSONValue, optionId: String) -> JSONRPCReply {
        JSONRPCReply(
            jsonrpc: "2.0",
            id: id,
            result: .object([
                "outcome": .object([
                    "outcome": .string("selected"),
                    "optionId": .string(optionId),
                ]),
            ])
        )
    }

    /// Fallback when ACP options are absent (legacy bool path).
    static func permissionReply(id: JSONValue, approved: Bool, alwaysApprove: Bool) -> JSONRPCReply {
        let outcome = approved
            ? (alwaysApprove ? "selectedAllowAlways" : "selectedAllowOnce")
            : "selectedRejectOnce"
        return JSONRPCReply(
            jsonrpc: "2.0",
            id: id,
            result: .object([
                "outcome": .string(outcome),
                "approved": .bool(approved),
                "always_approve": .bool(alwaysApprove),
            ])
        )
    }

    static func sessionLoadParams(sessionId: String) -> JSONValue {
        .object([
            "sessionId": .string(sessionId),
            "cwd": .string("."),
            "mcpServers": .array([]),
        ])
    }
}
