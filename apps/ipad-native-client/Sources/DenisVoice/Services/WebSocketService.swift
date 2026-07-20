import Foundation
import UIKit
import Starscream

@MainActor
class WebSocketService: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastCommand: String = ""
    @Published var protocolVersion: String = "2.0"
    @Published var lastHeartbeatSent: Date?
    @Published var bytesSent: Int64 = 0

    private var socket: WebSocket?
    private var reconnectWork: DispatchWorkItem?
    private var pingTimer: Timer?
    private var heartbeatTimer: Timer?
    private let canaryURL: URL
    private(set) var sessionId: String

    let receivedCommands = AsyncStreamPipe()

    var onHeartbeat: (() -> HeartbeatFrame?)?
    var onRegistration: (() -> NodeRegistrationFrame?)?

    init() {
        let vendor = UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "unknown"
        sessionId = "ipad-native-\(vendor)"
        let configured = UserDefaults.standard.string(forKey: "denis.edge.canary_url")
            ?? Bundle.main.object(forInfoDictionaryKey: "DenisEdgeCanaryURL") as? String
            ?? "ws://denis-edge.local:18132/ws/ipad-audio"
        canaryURL = URL(string: configured)!
    }

    func connect() {
        guard connectionState != .connecting else { return }
        disconnect()
        connectionState = .connecting
        lastCommand = "Conectando..."

        var req = URLRequest(url: canaryURL)
        req.timeoutInterval = 10
        req.setValue("denis-ipad-native/\(protocolVersion)", forHTTPHeaderField: "User-Agent")
        socket = WebSocket(request: req)
        socket?.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleEvent(event) }
        }
        socket?.connect()
    }

    func disconnect() {
        pingTimer?.invalidate(); pingTimer = nil
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        reconnectWork?.cancel(); reconnectWork = nil
        socket?.disconnect(); socket = nil
        connectionState = .disconnected
        lastCommand = "Desconectado"
    }

    func sendAudioFrame(_ frame: AudioFrame) {
        let msg = CanaryMessage.micAudio(
            sessionId: sessionId,
            format: "pcm_s16le",
            sampleRate: Int(frame.sampleRate),
            channels: frame.channels,
            data: frame.toBase64(),
            timestampMs: frame.timestampMs
        )
        send(msg)
    }

    func forwardAudioFeatureFrame(_ frame: AudioFeatureFrame) {
        let msg = CanaryMessage.audioFeatureFrame(dict: frame.dictionary)
        send(msg)
    }

    func forwardVisionFeatureFrame(_ frame: VisionFeatureFrame) {
        let msg = CanaryMessage.visionFeatureFrame(dict: frame.dictionary)
        send(msg)
    }

    func forwardMultimodalFeatureFrame(_ frame: MultimodalFeatureFrame) {
        let msg = CanaryMessage.multimodalFeatureFrame(dict: frame.dictionary)
        send(msg)
    }

    func forwardHeartbeat(_ frame: HeartbeatFrame) {
        let msg = CanaryMessage.heartbeat(dict: frame.dictionary)
        send(msg)
    }

    func forwardRasaBoost(_ frame: RasaFeatureBoost) {
        let msg = CanaryMessage.rasaBoost(dict: frame.dictionary)
        send(msg)
    }

    func forwardParlaiBoost(_ frame: ParlAIContextBoost) {
        let msg = CanaryMessage.parlaiBoost(dict: frame.dictionary)
        send(msg)
    }

    func send(_ message: CanaryMessage) {
        guard let text = message.encode() else { return }
        bytesSent += Int64(text.utf8.count)
        socket?.write(string: text)
    }

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        bytesSent += Int64(data.count)
        socket?.write(string: text)
    }

    func sendBinary(_ data: Data) {
        bytesSent += Int64(data.count)
        socket?.write(data: data)
    }

    private func handleEvent(_ event: WebSocketEvent) {
        switch event {
        case .connected:
            connectionState = .connected
            lastCommand = "Conectado v\(protocolVersion)"
            sendClientReady()
            startPing()
            startHeartbeat()
            receivedCommands.yield(("connected", [:]))

        case .disconnected(let reason, _):
            connectionState = .disconnected
            lastCommand = "Desconectado: \(reason)"
            receivedCommands.yield(("disconnected", ["reason": reason]))
            scheduleReconnect()

        case .text(let text):
            handleText(text)

        case .binary(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleText(text)
            } else {
                receivedCommands.yield(("binary", ["data": data.base64EncodedString()]))
            }

        case .error(let error):
            connectionState = .failed(error?.localizedDescription ?? "unknown")
            lastCommand = "Error: \(error?.localizedDescription ?? "desconocido")"
            scheduleReconnect()

        case .cancelled:
            connectionState = .disconnected
            lastCommand = "Cancelado"

        case .viabilityChanged(let viable):
            if !viable { lastCommand = "Red no disponible" }

        case .reconnectSuggested:
            scheduleReconnect()

        case .peerClosed:
            lastCommand = "Peer cerró conexión"
            scheduleReconnect()

        default:
            break
        }
    }

    private func handleText(_ text: String) {
        guard let parsed = CanaryMessage.decode(text) else { return }
        switch parsed.type {
        case "ack":
            if connectionState != .connected {
                connectionState = .connected
                lastCommand = "Conectado"
            }
        case "session_state":
            if let ver = parsed.dict["protocol_version"] as? String {
                protocolVersion = ver
            }
        case "audio_feature_frame_receipt":
            lastCommand = "Audio recibido"
        case "vision_feature_frame_receipt":
            lastCommand = "Frame visual recibido"
        case "heartbeat_ack":
            lastHeartbeatSent = Date()
        case "pong":
            break
        case "register_node":
            if let reg = onRegistration?() {
                let msg = CanaryMessage.nodeRegistration(dict: reg.dictionary)
                send(msg)
            }
        default:
            lastCommand = parsed.type
            receivedCommands.yield((parsed.type, parsed.dict))
        }
    }

    private func sendClientReady() {
        let msg = CanaryMessage.clientReady(
            sessionId: sessionId,
            payload: [
                "platform": "ipad_native",
                "device": UIDevice.current.model,
                "protocol_version": protocolVersion,
                "capabilities": "full",
            ]
        )
        send(msg)
    }

    private func sendPing() {
        send(.ping)
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self = self, let beat = self.onHeartbeat?() else { return }
            self.forwardHeartbeat(beat)
        }
    }

    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.connect() }
        }
        reconnectWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: work)
    }
}

class AsyncStreamPipe {
    private var continuation: AsyncStream<(String, [String: Any])>.Continuation?
    lazy var stream: AsyncStream<(String, [String: Any])> = {
        AsyncStream { [weak self] cont in
            self?.continuation = cont
        }
    }()

    func yield(_ value: (String, [String: Any])) {
        continuation?.yield(value)
    }
}
