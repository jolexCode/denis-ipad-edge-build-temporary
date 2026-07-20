//
//  FoundationModelsService.swift
//  DenisVoice
//
//  DENIS_APPLE_FOUNDATION_EDGE_ORGAN_V1
//
//  Five specialized LanguageModelSession instances for Apple Foundation Models.
//  Smart routing: max 2 sessions per turn to avoid CPU/thermal pressure.
//
//  Authority: candidate_only for all frames.
//  This service NEVER writes to Persona surface, memory, or identity.

#if canImport(FoundationModels)

import Foundation
import FoundationModels
import CryptoKit

@available(iOS 26.0, macOS 26.0, *)
final class FoundationModelsService: Sendable {

    private let model = SystemLanguageModel.default
    private let sessions: [AppleEdgeSession: LanguageModelSession]
    private let encoder = JSONEncoder()

    init() {
        var built: [AppleEdgeSession: LanguageModelSession] = [:]

        built[.intent] = LanguageModelSession(
            model: model,
            instructions: """
            You are the Apple edge semantic organ of Denis.
            Analyze the user's input and extract primary intent, alternative
            plausible intents, ambiguity, and confidence.
            Never claim authority, execute actions, or produce final Persona output.
            Return candidates faithfully.
            """
        )

        built[.entities] = LanguageModelSession(
            model: model,
            instructions: """
            You are the entity extraction organ of Denis.
            Identify all explicit and implicit entities, resolve coreferences,
            extract temporal and spatial contextual references.
            Be thorough but precise. Mark entities with confidence scores.
            """
        )

        built[.dialogue] = LanguageModelSession(
            model: model,
            instructions: """
            You are the dialogue analysis organ of Denis.
            Summarize the conversation so far, identify open threads,
            determine the current dialogue phase, and propose a candidate
            response for the canonical Persona to evaluate.
            Never produce final output. Always mark candidates clearly.
            """
        )

        built[.emotion] = LanguageModelSession(
            model: model,
            instructions: """
            You are the emotional analysis organ of Denis.
            Detect emotional pressure (0.0 calm to 1.0 intense), tone,
            urgency, implicit unspoken needs, and satisfaction signals.
            Be honest about uncertainty. Do not project emotions that are
            not evidenced by the input.
            """
        )

        built[.tools] = LanguageModelSession(
            model: model,
            instructions: """
            You are the action candidate generator for Denis.
            Given the user's input, suggest possible actions with typed
            arguments. Flag missing arguments and estimate risk level.
            Never execute actions directly. Always produce candidates
            with clear rationale.
            """
        )

        self.sessions = built
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    var isModelAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    // MARK: - Smart Routing

    func routeInput(_ text: String) -> AppleEdgeRoutingDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < 40 && !trimmed.contains("?") {
            return .intentOnly
        }

        let lower = trimmed.lowercased()
        let actionPrefixes = ["install ", "run ", "create ", "fix ", "send ",
                              "open ", "close ", "delete ", "set ", "enable "]
        if actionPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return .intentAndTools
        }

        let emotionalMarkers = ["!", "please", "urgent", "help", "worried",
                                "angry", "frustrated", "excited", "sad",
                                "annoyed", "confused", "afraid"]
        if emotionalMarkers.contains(where: { lower.contains($0) }) {
            return .intentAndEmotion
        }

        if trimmed.count > 100 || trimmed.contains("\n") ||
           trimmed.components(separatedBy: " ").count > 20 {
            return .intentAndEntities
        }

        return .intentAndEntities
    }

    // MARK: - Analysis

    func analyze(_ text: String) async throws -> EdgeIntentFrame {
        guard case .available = model.availability else {
            throw AppleEdgeError.modelUnavailable("SystemLanguageModel not available")
        }

        let decision = routeInput(text)

        guard let session = sessions[.intent] else {
            throw AppleEdgeError.notInitialized
        }

        let response = try await session.respond(
            to: text,
            generating: EdgeIntentFrame.self
        )
        return response.content
    }

    /// Fuse symbolic NLU, Rasa/ParlAI speculative candidates and the Moshi
    /// three-line state on the M1. Inputs remain evidence; output remains a
    /// candidate for Denis Persona admission.
    func analyze(_ request: EdgeWorkRequest) async throws -> EdgeIntentFrame {
        let speculative = request.speculativeCandidates.map {
            "[\($0.source) confidence=\($0.confidence)] \($0.text)"
        }.joined(separator: "\n")
        let symbolic = request.symbolicNLUContext
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let lines: String
        if let moshi = request.moshiLines {
            lines = "human=\(moshi.humanPresence)\nenrichment=\(moshi.speculativeEnrichment)\npersona=\(moshi.admittedPersonaContext)"
        } else {
            lines = "unavailable"
        }
        let prompt = """
        USER INPUT:
        \(request.userText)

        SYMBOLIC NLU CONTEXT:
        \(symbolic)

        RASA/PARLAI/PIPECAT SPECULATIVE CANDIDATES:
        \(speculative)

        MOSHI THREE-LINE STATE:
        \(lines)

        Fuse this evidence. Do not treat speculative candidates as facts and do
        not produce a final Persona response.
        """
        return try await analyze(prompt)
    }

    func executeModules(_ request: EdgeWorkRequest) async -> EdgeModuleResultEnvelope {
        var results: [EdgeModuleResult] = []
        for invocation in request.moduleInvocations ?? [] {
            let started = Date()
            guard invocation.connector == "foundation_models" else {
                results.append(.init(moduleId: invocation.moduleId, connector: invocation.connector, output: "", elapsedMs: 0, error: "connector_not_available_for_dynamic_text_module"))
                continue
            }
            do {
                guard case .available = model.availability else {
                    throw AppleEdgeError.modelUnavailable("SystemLanguageModel not available")
                }
                let dynamicSession = LanguageModelSession(model: model, instructions: invocation.instructions)
                let response = try await dynamicSession.respond(to: invocation.input)
                results.append(.init(moduleId: invocation.moduleId, connector: invocation.connector, output: response.content, elapsedMs: Date().timeIntervalSince(started) * 1000, error: nil))
            } catch {
                results.append(.init(moduleId: invocation.moduleId, connector: invocation.connector, output: "", elapsedMs: Date().timeIntervalSince(started) * 1000, error: error.localizedDescription))
            }
        }
        return .init(requestId: request.requestId, sessionId: request.sessionId, turnId: request.turnId, results: results)
    }

    func analyzeFull(_ text: String) async throws -> [String: Any] {
        guard case .available = model.availability else {
            throw AppleEdgeError.modelUnavailable("SystemLanguageModel not available")
        }

        var results: [String: Any] = [:]
        let decision = routeInput(text)

        for edgeSession in decision.sessions {
            guard let session = sessions[edgeSession] else { continue }

            switch edgeSession {
            case .intent:
                let r = try await session.respond(to: text, generating: EdgeIntentFrame.self)
                results["intent"] = try encodeToDict(r.content)
            case .entities:
                let r = try await session.respond(to: text, generating: EdgeEntity.self)
                results["entities"] = try encodeToDict(r.content)
            case .dialogue:
                let r = try await session.respond(to: text, generating: EdgeDialogueFrame.self)
                results["dialogue"] = try encodeToDict(r.content)
            case .emotion:
                let r = try await session.respond(to: text, generating: EdgeEmotionFrame.self)
                results["emotion"] = try encodeToDict(r.content)
            case .tools:
                let r = try await session.respond(to: text, generating: EdgeActionCandidate.self)
                results["tools"] = try encodeToDict(r.content)
            }
        }

        results["routing_decision"] = decision.reason
        return results
    }

    // MARK: - Envelope

    /// Wraps a typed @Generable frame into the canonical envelope
    /// for transport to nodo1 edge ingress.
    ///
    /// The `candidate_only` and `semantic_authority = false` flags are
    /// declared in the envelope schema, not in the init — they are
    /// structural invariants of the edge organ, not per-request toggles.
    func encodeEnvelope(function: EdgeFunction, payload: EdgePayload, sourceText: String? = nil, edgeStage: String = "initial") -> AppleEdgeEnvelope {
        return AppleEdgeEnvelope(
            deviceId: UIDevice.current.name,
            sessionId: UUID().uuidString,
            turnId: UUID().uuidString,
            function: function,
            sourceText: sourceText,
            edgeStage: edgeStage,
            payload: payload
        )
    }
    // MARK: - Helpers

    private func encodeToDict<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

// Type-erased Encodable wrapper for JSON encoding
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { _encode = value.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

#endif
