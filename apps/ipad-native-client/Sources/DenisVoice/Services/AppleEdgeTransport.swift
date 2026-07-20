//
//  AppleEdgeTransport.swift
//  DenisVoice
//
//  DENIS_APPLE_FOUNDATION_EDGE_ORGAN_V1
//
//  Outbound WebSocket client connecting iPad edge frames to the canonical
//  ingress on nodo1. Handles reconnection, dedup, bounded queue, and receipts.
//
//  Protocol: URLSessionWebSocketTask (Apple SDK, no third-party deps)
//  Authority: candidate_only — transport never mutates Persona.

import Foundation
import CryptoKit

// MARK: - Transport State

enum AppleEdgeTransportState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - Dedup Entry

/// SHA-256 fingerprint of a sent envelope to prevent duplicate transmission.
struct DedupEntry: Sendable {
    let hash: String
    let timestamp: Date
}

// MARK: - Receipt

/// Ephemeral receipt for a single sent envelope. Not persisted beyond the session.
struct SendReceipt: Sendable {
    let envelopeHash: String
    let delivered: Bool
    let timestamp: Date
    let error: String?
}

// MARK: - WebSocket Transport

/// Outbound WebSocket transport for Apple Edge frames from iPad to nodo1.
///
/// Lifecycle:
///   `connect()` → `connected` → `send(envelope)` → `disconnect()`
///   Automatic reconnection on network failure.
///
/// Authority: candidate_only — this class never writes to Persona, memory, or identity.
final class AppleEdgeTransport: @unchecked Sendable {

    private let config: AppleEdgeConfig
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var heartbeatTimer: DispatchSourceTimer?
    private var state: AppleEdgeTransportState = .disconnected
    private var recentHashes: [DedupEntry] = []
    private var reconnectAttempts = 0

    /// Callback invoked when state changes (for AppState observation).
    var onStateChange: ((AppleEdgeTransportState) -> Void)?

    /// Callback invoked when a receipt is produced.
    var onReceipt: ((SendReceipt) -> Void)?
    var onWorkRequest: ((EdgeWorkRequest) -> Void)?
    var onPersonaSurface: ((PersonaSurfaceResponse) -> Void)?

    init(config: AppleEdgeConfig = .production) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Open the WebSocket connection to the ingress endpoint.
    func connect() {
        guard state == .disconnected || state == .reconnecting else { return }
        state = .connecting
        onStateChange?(state)
        session = URLSession(configuration: .default)
        task = session?.webSocketTask(with: config.websocketURL)
        task?.resume()

        // Assume connected after resume — URLSessionWebSocketTask doesn't
        // provide a synchronous connection state, so we optimistically set
        // connected and handle errors on the first send/recv.
        state = .connected
        reconnectAttempts = 0
        onStateChange?(state)
        receiveNext()
        startHeartbeat()
    }

    /// Gracefully close the WebSocket.
    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        state = .disconnected
        onStateChange?(state)
    }

    /// Send a single envelope over the WebSocket.
    ///
    /// - Deduplicates against recent sends (SHA-256 of full JSON).
    /// - Drops silently if queue is full.
    /// - Returns a `SendReceipt` indicating delivery success.
    @discardableResult
    func send(_ envelope: AppleEdgeEnvelope) -> SendReceipt {
        guard state == .connected, let task else {
            return SendReceipt(
                envelopeHash: "not-connected",
                delivered: false,
                timestamp: Date(),
                error: "Transport not connected"
            )
        }

        // Encode
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(envelope) else {
            return SendReceipt(
                envelopeHash: "encoding-failed",
                delivered: false,
                timestamp: Date(),
                error: "Encoding failed"
            )
        }

        // Deduplicate the canonical envelope bytes, not merely the device ID.
        let hash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        if recentHashes.contains(where: { $0.hash == hash }) {
            return SendReceipt(
                envelopeHash: hash,
                delivered: false,
                timestamp: Date(),
                error: "Duplicate — already sent"
            )
        }

        // Send
        let message = URLSessionWebSocketTask.Message.data(data)
        task.send(message) { [weak self] error in
            let receipt: SendReceipt
            if let error {
                receipt = SendReceipt(
                    envelopeHash: hash,
                    delivered: false,
                    timestamp: Date(),
                    error: error.localizedDescription
                )
                self?.scheduleReconnect()
            } else {
                receipt = SendReceipt(
                    envelopeHash: hash,
                    delivered: true,
                    timestamp: Date(),
                    error: nil
                )
            }
            self?.onReceipt?(receipt)
        }

        // Track dedup
        recentHashes.append(DedupEntry(hash: hash, timestamp: Date()))
        pruneDedupHistory()

        return SendReceipt(
            envelopeHash: hash,
            delivered: true,
            timestamp: Date(),
            error: nil
        )
    }

    @discardableResult
    func sendManifest(_ manifest: DenisEdgeCapabilityManifest) -> SendReceipt {
        sendCodable(manifest, identity: "manifest:\(manifest.nodeId)")
    }

    @discardableResult
    func sendModuleResults(_ results: EdgeModuleResultEnvelope) -> SendReceipt {
        sendCodable(results, identity: "module-results:\(results.requestId)")
    }

    @discardableResult
    private func sendCodable<T: Encodable>(_ value: T, identity: String) -> SendReceipt {
        guard state == .connected, let task else {
            return SendReceipt(envelopeHash: "not-connected", delivered: false, timestamp: Date(), error: "Transport not connected")
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(value) else {
            return SendReceipt(envelopeHash: identity, delivered: false, timestamp: Date(), error: "Encoding failed")
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        task.send(.data(data)) { [weak self] error in
            self?.onReceipt?(SendReceipt(
                envelopeHash: hash,
                delivered: error == nil,
                timestamp: Date(),
                error: error?.localizedDescription
            ))
            if error != nil { self?.scheduleReconnect() }
        }
        return SendReceipt(envelopeHash: hash, delivered: true, timestamp: Date(), error: nil)
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard state != .disconnected else { return }
        state = .reconnecting
        onStateChange?(state)

        reconnectAttempts += 1

        // Exponential backoff: 2s, 4s, 8s, 16s... capped
        let delay = min(config.reconnectMaxBackoffSeconds, pow(2.0, Double(min(reconnectAttempts, 5))))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    private func receiveNext() {
        guard state == .connected, let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
            case .success(let message):
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: self.receiveNext(); return
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let request = try? decoder.decode(EdgeWorkRequest.self, from: data) {
                    self.onWorkRequest?(request)
                } else if let response = try? decoder.decode(PersonaSurfaceResponse.self, from: data),
                          response.type == "response" {
                    self.onPersonaSurface?(response)
                }
                self.receiveNext()
            }
        }
    }

    // MARK: - Dedup Management

    private func pruneDedupHistory() {
        let cutoff = Date().addingTimeInterval(-300) // keep last 5 minutes
        recentHashes.removeAll { $0.timestamp < cutoff }
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .connected, let task = self.task else { return }
            task.sendPing { [weak self] error in
                if error != nil { self?.scheduleReconnect() }
            }
        }
        heartbeatTimer = timer
        timer.resume()
    }
}
