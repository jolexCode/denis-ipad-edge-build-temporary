import Foundation
import UIKit

@MainActor
class AppState: ObservableObject {
    @Published var isConnected = false
    @Published var nodeId: String
    @Published var registeredInNeo4j = false
    @Published var lastRegistration: Date?
    @Published var systemUptime: TimeInterval = 0
    @Published var appStartTime: Date

    let webSocket = WebSocketService()
    let audio = AudioService()
    let vision = VisionService()
    let ml = MLService()
    let worker = WorkerService()
    let vad = VADService()
    let stt = STTService()
    let faceID = FaceIDService()
    let foundationModels = FoundationModelsService()
    let bargeIn = BargeInManager()
    let frameFactory = FrameFactory()
    let tts = LocalTTSService()

    #if canImport(FoundationModels)
    let appleEdgeTransport = AppleEdgeTransport()
    lazy var presence = ContinuousPresenceCoordinator(
        edge: foundationModels,
        transport: appleEdgeTransport
    )
    #endif

    init() {
        let vendor = UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "unknown"
        nodeId = "ipad-m1-\(vendor)"
        appStartTime = Date()
        configureServices()
    }

    func configureServices() {
        let wsSessionId = webSocket.sessionId
        frameFactory.nodeId = wsSessionId

        audio.configure { [weak self] frame in
            guard let self = self else { return }
            let ff = self.frameFactory
            let vadActive = self.vad.isVoiceActive
            let featureFrame = ff.makeAudioFeatureFrame(
                data: frame.data,
                sampleRate: Int(frame.sampleRate),
                channels: frame.channels,
                durationMs: frame.durationMs,
                vadActive: vadActive,
                rmsLevel: self.vad.voiceLevel,
                peakLevel: self.vad.voiceLevel
            )
            self.webSocket.forwardAudioFeatureFrame(featureFrame)
        }

        audio.injectServices(vad: vad, stt: stt, bargeIn: bargeIn)
        presence.configure(audio: audio, tts: tts)
        bargeIn.onBargeIn = { [weak self] in self?.tts.stop() }

        vision.configure { [weak self] pixelBuffer, position in
            guard let self = self,
                  let visionFrame = self.frameFactory.makeVisionFeatureFrame(
                    pixelBuffer: pixelBuffer, cameraPosition: position)
            else { return }
            self.webSocket.forwardVisionFeatureFrame(visionFrame)
        } onFace: { [weak self] pixelBuffer in
            self?.faceID.detectFaces(in: pixelBuffer)
            self?.faceID.checkAttention(in: pixelBuffer)
        }
        vision.faceIDService = faceID

        worker.configure(
            websocket: webSocket,
            audio: audio,
            vision: vision,
            stt: stt,
            faceID: faceID,
            frameFactory: frameFactory
        )

        stt.onTranscript = { [weak self] text, confidence in
            guard let self = self else { return }
            self.audio.lastTranscript = text
            let boost = self.frameFactory.makeRasaBoost(
                transcript: text,
                confidence: confidence,
                intent: "stt_transcript",
                entities: ["source": "on_device_stt"]
            )
            self.webSocket.forwardRasaBoost(boost)
            self.presence.observeTranscript(text)
        }

        webSocket.onRegistration = { [weak self] in
            guard let self = self else { return nil }
            return NodeRegistrationFrame(
                nodeId: self.nodeId,
                device: UIDevice.current.model,
                systemVersion: UIDevice.current.systemVersion,
                capabilities: self.worker.capabilities,
                mlInfo: self.ml.systemInfo,
                authority: .edgeWorker
            )
        }

        webSocket.onHeartbeat = { [weak self] in
            guard let self = self else { return nil }
            return self.frameFactory.makeHeartbeat(
                audioActive: self.audio.state == .recording,
                visionActive: self.vision.isActive,
                mlActive: self.ml.isReady,
                capabilities: self.worker.capabilities,
                batteryLevel: 1.0
            )
        }

        Task {
            for await command in webSocket.receivedCommands.stream {
                let type = command.type
                let payload = command.payload
                if type == "connected" {
                    isConnected = true
                    await registerNode()
                } else if type == "disconnected" {
                    isConnected = false
                } else {
                    worker.handleCommand(type, payload: payload)
                }
            }
        }
    }

    func registerNode() async {
        guard let reg = webSocket.onRegistration?() else { return }
        let msg = CanaryMessage.nodeRegistration(dict: reg.dictionary)
        webSocket.send(msg)
        registeredInNeo4j = true
        lastRegistration = Date()
    }

    func startCapture() {
        try? audio.startCapture()
        try? vision.startCapture(position: .back)
        faceID.configure()
    }

    func stopCapture() {
        audio.stopCapture()
        vision.stopCapture()
        faceID.logout()
    }

    #if canImport(FoundationModels)
    func startAppleEdge() {
        presence.start()
    }

    func stopAll() {
        presence.stop()
    }
    #endif

    var uptimeFormatted: String {
        let interval = Date().timeIntervalSince(appStartTime)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
