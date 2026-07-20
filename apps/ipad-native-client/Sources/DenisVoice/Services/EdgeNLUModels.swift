// EdgeNLUModels.swift — Canonical type definitions for Apple Foundation Edge organ.
// NO duplicate type names. @Generable structs inside #if canImport(FoundationModels).
// Plain Codable structs used by other files are OUTSIDE the guard.

import Foundation
import CryptoKit
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Platform-Agnostic Codable Types (usable from all platforms)

@Generable
struct EdgeIntentFrame: Codable, Sendable {
    let primaryIntent: String
    let alternativeIntents: [String]
    let entities: [EdgeEntity]
    let topics: [String]
    let ambiguous: Bool
    let ambiguityReason: String?
    let emotionalPressure: Double
    let normalizedMeaning: String
}

/// Entity extracted from user input — used both nested in EdgeIntentFrame and standalone
@Generable
struct EdgeEntity: Codable, Sendable {
    let type: String
    let value: String
}

@Generable
struct EdgeDialogueFrame: Codable, Sendable {
    let summary: String
    let currentTopic: String
    let suggestedNextTurn: String?
    let turnCount: Int
    let ambiguityDetected: Bool
}

@Generable
struct EdgeEmotionFrame: Codable, Sendable {
    let tone: String
    let urgency: Double
    let emotionalPressure: Double
    let implicitNeeds: [String]
}

@Generable
struct EdgeActionCandidate: Codable, Sendable {
    let tool: String
    let arguments: [String: String]
    let safetyLevel: String
    let confidence: Double
    let reasoning: String
}

// MARK: - Envelope & Discriminated Union

enum EdgeFunction: String, Codable, Sendable {
    case intent, entities, dialogue, emotion, tools
}

enum EdgePayload: Codable, Sendable {
    case intent(EdgeIntentFrame)
    case entities([EdgeEntity])
    case dialogue(EdgeDialogueFrame)
    case emotion(EdgeEmotionFrame)
    case tools(EdgeActionCandidate)

    private enum CodingKeys: String, CodingKey { case type, data }
    private enum Discriminator: String, Codable {
        case intent, entities, dialogue, emotion, tools
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .intent(let v):    try c.encode(Discriminator.intent,    forKey: .type); try c.encode(v, forKey: .data)
        case .entities(let v):  try c.encode(Discriminator.entities,  forKey: .type); try c.encode(v, forKey: .data)
        case .dialogue(let v):  try c.encode(Discriminator.dialogue,  forKey: .type); try c.encode(v, forKey: .data)
        case .emotion(let v):   try c.encode(Discriminator.emotion,   forKey: .type); try c.encode(v, forKey: .data)
        case .tools(let v):     try c.encode(Discriminator.tools,     forKey: .type); try c.encode(v, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Discriminator.self, forKey: .type)
        switch type {
        case .intent:    self = .intent(try c.decode(EdgeIntentFrame.self, forKey: .data))
        case .entities:  self = .entities(try c.decode([EdgeEntity].self, forKey: .data))
        case .dialogue:  self = .dialogue(try c.decode(EdgeDialogueFrame.self, forKey: .data))
        case .emotion:   self = .emotion(try c.decode(EdgeEmotionFrame.self, forKey: .data))
        case .tools:     self = .tools(try c.decode(EdgeActionCandidate.self, forKey: .data))
        }
    }
}

struct AppleEdgeEnvelope: Codable, Sendable {
    let schema: String
    let deviceId: String
    let sessionId: String
    let turnId: String
    let function: EdgeFunction
    let inputHash: String?
    let sourceText: String?
    let edgeStage: String
    let timestamp: TimeInterval
    let candidateOnly: Bool
    let semanticAuthority: Bool
    let identityAuthority: Bool
    let mutationAuthority: Bool
    let payload: EdgePayload

    enum CodingKeys: String, CodingKey {
        case schema, deviceId, sessionId, turnId, function
        case inputHash = "input_hash"
        case sourceText = "source_text"
        case edgeStage = "edge_stage"
        case timestamp
        case candidateOnly = "candidate_only"
        case semanticAuthority = "semantic_authority"
        case identityAuthority = "identity_authority"
        case mutationAuthority = "mutation_authority"
        case payload
    }

    init(
        schema: String = "DENIS_APPLE_EDGE_FRAME_V1",
        deviceId: String,
        sessionId: String,
        turnId: String,
        function: EdgeFunction,
        inputHash: String? = nil,
        sourceText: String? = nil,
        edgeStage: String = "initial",
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        payload: EdgePayload
    ) {
        self.schema = schema
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.turnId = turnId
        self.function = function
        self.inputHash = inputHash
        self.sourceText = sourceText
        self.edgeStage = edgeStage
        self.timestamp = timestamp
        self.candidateOnly = true
        self.semanticAuthority = false
        self.identityAuthority = false
        self.mutationAuthority = false
        self.payload = payload
    }
}

struct DenisEdgeCapabilityManifest: Codable, Sendable {
    let schema = "DENIS_IPAD_EDGE_CAPABILITY_MANIFEST_V1"
    let nodeId: String
    let manifestVersion = "1"
    let capabilities: [String]
    let backends: [String]
    let integrations: [String]
    let supportsStreaming = true
    let supportsCancellation = true
    let maxInflight = 2
    let candidateOnly = true
    let semanticAuthority = false
    let mutationAuthority = false

    static func current(nodeId: String) -> Self {
        .init(
            nodeId: nodeId,
            capabilities: [
                "continuous_presence_without_hotword",
                "local_stt_partial_and_final",
                "local_tts_high_quality",
                "voice_activity_detection",
                "barge_in",
                "apple_foundation_models_candidates",
                "structured_generation",
                "multimodal_edge_preprocessing",
                "candidate_chunk_streaming",
                "server_defined_edge_modules",
                "background_audio_presence",
            ],
            backends: [
                "apple_intelligence_on_device", "foundation_models_dynamic_session",
                "coreml_model_connector", "vision_request_connector",
                "natural_language_connector", "sound_analysis_connector",
                "metal_compute_connector", "ane", "gpu", "cpu"
            ],
            integrations: [
                "denis_symbolic_nlu",
                "rasa_speculative_candidate",
                "parlai_speculative_candidate",
                "pipecat_full_duplex_transport",
                "moshi_three_line_conversation_mux",
                "denis_persona_admission",
                "thought_fabric_presence",
            ]
        )
    }
}

struct SpeculativeCandidateInput: Codable, Sendable {
    let source: String
    let text: String
    let confidence: Double
    let metadata: [String: String]
}

struct MoshiConversationLines: Codable, Sendable {
    let humanPresence: String
    let speculativeEnrichment: String
    let admittedPersonaContext: String
}

struct EdgeWorkRequest: Codable, Sendable {
    let schema: String
    let requestId: String
    let sessionId: String
    let turnId: String
    let userText: String
    let symbolicNLUContext: [String: String]
    let speculativeCandidates: [SpeculativeCandidateInput]
    let moshiLines: MoshiConversationLines?
    let requestedFunctions: [EdgeFunction]
    let deadlineMs: Int
    let cancelPreviousTurn: Bool
    let moduleInvocations: [EdgeModuleInvocation]?
}

struct EdgeModuleInvocation: Codable, Sendable {
    let moduleId: String
    let connector: String
    let instructions: String
    let input: String
    let options: [String: String]
}

struct EdgeModuleResult: Codable, Sendable {
    let moduleId: String
    let connector: String
    let output: String
    let elapsedMs: Double
    let error: String?
}

struct EdgeModuleResultEnvelope: Codable, Sendable {
    let schema = "DENIS_APPLE_EDGE_MODULE_RESULTS_V1"
    let requestId: String
    let sessionId: String
    let turnId: String
    let results: [EdgeModuleResult]
    let candidateOnly = true
    let semanticAuthority = false
    let mutationAuthority = false
}

struct PersonaSurfaceResponse: Codable, Sendable {
    let type: String
    let sessionId: String?
    let turnId: String?
    let text: String
    let meaningActRef: String?
    let elapsedMs: Double?

    enum CodingKeys: String, CodingKey {
        case type, text
        case sessionId = "session_id"
        case turnId = "turn_id"
        case meaningActRef = "meaning_act_ref"
        case elapsedMs = "elapsed_ms"
    }
}

// MARK: - Error Domain

enum AppleEdgeError: Error, LocalizedError {
    case modelUnavailable(String)
    case notInitialized
    case encodingFailed(String)
    case decodingFailed(String)
    case sessionFailed(String)
    case timeout(String)
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let r): return "Model unavailable: \(r)"
        case .notInitialized: return "Foundation Models session not initialized"
        case .encodingFailed(let m): return "Encoding failed: \(m)"
        case .decodingFailed(let m): return "Decoding failed: \(m)"
        case .sessionFailed(let m): return "Session failed: \(m)"
        case .timeout(let m): return "Timeout: \(m)"
        case .transportFailed(let m): return "Transport failed: \(m)"
        }
    }
}

// MARK: - Transport Configuration

struct AppleEdgeConfig: Sendable {
    let websocketURL: URL
    let deviceId: String
    let reconnectMaxBackoffSeconds: Double
    let deduplicationWindowSeconds: TimeInterval
    let maxQueueSize: Int
    let sendTimeoutSeconds: TimeInterval

    static var production: AppleEdgeConfig {
        let configured = UserDefaults.standard.string(forKey: "denis.edge.websocket_url")
            ?? Bundle.main.object(forInfoDictionaryKey: "DenisEdgeWebSocketURL") as? String
            ?? "ws://denis-edge.local:18093/ws/ipad"
        return AppleEdgeConfig(
            websocketURL: URL(string: configured)!,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown-ipad",
            reconnectMaxBackoffSeconds: 30.0,
            deduplicationWindowSeconds: 300.0,
            maxQueueSize: 8,
            sendTimeoutSeconds: 30.0
        )
    }
}

// MARK: - Foundation Models Sessions (iPadOS 26+ only)

#if canImport(FoundationModels)

/// Five specialized Foundation Models sessions
enum AppleEdgeSession: String, CaseIterable, Sendable {
    case intent    = "apple.edge.intent"
    case entities  = "apple.edge.entities"
    case dialogue  = "apple.edge.dialogue"
    case emotion   = "apple.edge.emotion"
    case tools     = "apple.edge.tools"
}

/// Per-session configuration with system instructions
struct EdgeSessionConfig: Sendable {
    let session: AppleEdgeSession
    let systemInstruction: String
    let maxResponseTokens: Int
    let temperature: Double

    static let intent = EdgeSessionConfig(
        session: .intent,
        systemInstruction: """
        You are the Apple edge semantic organ of Denis. Analyze the input and emit \
        structured semantic evidence. Never claim authority, execute actions, or produce \
        final Persona output. Return candidates and ambiguities faithfully.
        """,
        maxResponseTokens: 512,
        temperature: 0.3
    )
    static let entities = EdgeSessionConfig(
        session: .entities,
        systemInstruction: """
        You extract named entities, types, values, coreferences, and contextual references \
        from user input. Be precise and faithful. Never claim semantic authority.
        """,
        maxResponseTokens: 512,
        temperature: 0.2
    )
    static let dialogue = EdgeSessionConfig(
        session: .dialogue,
        systemInstruction: """
        You summarize the current dialogue turn and suggest the next logical step. \
        Detect topic shifts and ambiguity. Never claim Persona authority.
        """,
        maxResponseTokens: 384,
        temperature: 0.4
    )
    static let emotion = EdgeSessionConfig(
        session: .emotion,
        systemInstruction: """
        You detect emotional tone, urgency, and implicit needs from user input. \
        Be faithful to the evidence. Never claim semantic authority.
        """,
        maxResponseTokens: 256,
        temperature: 0.3
    )
    static let tools = EdgeSessionConfig(
        session: .tools,
        systemInstruction: """
        You propose action candidates based on the user input. Return tool name, \
        arguments, safety level, and confidence. Never execute actions yourself.
        """,
        maxResponseTokens: 512,
        temperature: 0.2
    )

    /// Return the config for a given session
    static func forSession(_ session: AppleEdgeSession) -> EdgeSessionConfig {
        switch session {
        case .intent:   return .intent
        case .entities: return .entities
        case .dialogue: return .dialogue
        case .emotion:  return .emotion
        case .tools:    return .tools
        }
    }
}

/// Smart routing decision for which sessions to activate per turn
struct AppleEdgeRoutingDecision: Sendable {
    let sessions: [AppleEdgeSession]
    let reason: String

    static func decide(intent: String, isAmbiguous: Bool, isEmotional: Bool, isExecutable: Bool) -> AppleEdgeRoutingDecision {
        var sessions: [AppleEdgeSession] = [.intent]
        var reasons: [String] = ["always intent"]

        if isAmbiguous || intent == "ambiguous" {
            sessions.append(.entities)
            reasons.append("ambiguity → entities")
        }
        if isEmotional {
            sessions.append(.emotion)
            reasons.append("emotional → emotion")
        }
        if isExecutable || intent == "action" {
            sessions.append(.tools)
            reasons.append("executable → tools")
        }

        // Cap at 2 sessions to limit latency
        let selected = Array(sessions.prefix(2))
        return AppleEdgeRoutingDecision(
            sessions: selected,
            reason: reasons.joined(separator: "; ")
        )
    }

    // Static convenience properties for common patterns
    static let intentOnly = AppleEdgeRoutingDecision(
        sessions: [.intent], reason: "simple intent only"
    )
    static let intentAndEntities = AppleEdgeRoutingDecision(
        sessions: [.intent, .entities], reason: "intent + entity resolution"
    )
    static let intentAndEmotion = AppleEdgeRoutingDecision(
        sessions: [.intent, .emotion], reason: "intent + emotional context"
    )
    static let intentAndTools = AppleEdgeRoutingDecision(
        sessions: [.intent, .tools], reason: "intent + tool/action candidate"
    )
}

#endif
