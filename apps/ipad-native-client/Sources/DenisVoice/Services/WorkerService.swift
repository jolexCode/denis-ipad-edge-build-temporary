import Foundation
import AVFoundation

@MainActor
class WorkerService: ObservableObject {
    @Published var activeTask: String = ""
    @Published var taskHistory: [WorkerTask] = []
    @Published var capabilities: CapabilitySet

    private weak var webSocket: WebSocketService?
    private weak var audio: AudioService?
    private weak var vision: VisionService?
    private weak var stt: STTService?
    private weak var faceID: FaceIDService?
    private weak var frameFactory: FrameFactory?

    struct WorkerTask: Identifiable, Codable {
        let id: String
        let type: String
        let status: TaskStatus
        let receivedAt: Date
        var completedAt: Date?
        var result: String?

        enum TaskStatus: String, Codable {
            case received, processing, completed, failed
        }
    }

    override init() {
        capabilities = CapabilitySet()
    }

    func configure(websocket: WebSocketService, audio: AudioService,
                   vision: VisionService, stt: STTService,
                   faceID: FaceIDService, frameFactory: FrameFactory) {
        self.webSocket = websocket
        self.audio = audio
        self.vision = vision
        self.stt = stt
        self.faceID = faceID
        self.frameFactory = frameFactory
    }

    func handleCommand(_ type: String, payload: [String: Any]) {
        let task = WorkerTask(
            id: UUID().uuidString.prefix(8).lowercased(),
            type: type,
            status: .received,
            receivedAt: Date()
        )
        taskHistory.append(task)
        activeTask = type
        processCommand(task, payload: payload)
    }

    private func processCommand(_ task: WorkerTask, payload: [String: Any]) {
        updateTask(task.id, status: .processing)

        switch task.type {
        case "start_audio_capture":
            do {
                try audio?.startCapture()
                completeTask(task.id, result: "audio_capture_active")
            } catch {
                failTask(task.id, error: error.localizedDescription)
            }

        case "stop_audio_capture":
            audio?.stopCapture()
            completeTask(task.id, result: "audio_capture_stopped")

        case "play_tts":
            if let urlStr = payload["audio_url"] as? String, let url = URL(string: urlStr) {
                audio?.playTTS(url: url)
                completeTask(task.id, result: "tts_playing")
            } else if let text = payload["text"] as? String {
                completeTask(task.id, result: "tts_requested: \(text.prefix(40))")
            } else {
                failTask(task.id, error: "formato_tts_invalido")
            }

        case "start_vision":
            let position: AVCaptureDevice.Position = (payload["camera"] as? String == "front") ? .front : .back
            do {
                try vision?.startCapture(position: position)
                completeTask(task.id, result: "vision_active_\(position == .front ? "front" : "back")")
            } catch {
                failTask(task.id, error: error.localizedDescription)
            }

        case "stop_vision":
            vision?.stopCapture()
            completeTask(task.id, result: "vision_stopped")

        case "start_stt":
            stt?.checkAvailability()
            completeTask(task.id, result: stt?.isAvailable == true ? "stt_available" : "stt_unavailable")

        case "stop_stt":
            stt?.stopRecognition()
            completeTask(task.id, result: "stt_stopped")

        case "authenticate":
            Task {
                let result = await faceID?.authenticate() ?? false
                completeTask(task.id, result: result ? "authenticated" : "auth_failed")
            }

        case "logout":
            faceID?.logout()
            completeTask(task.id, result: "logged_out")

        case "face_detect":
            completeTask(task.id, result: faceID?.faceDetected == true ? "face_present" : "no_face")

        case "toggle_barge_in":
            audio?.isBargeInActive.toggle()
            completeTask(task.id, result: "barge_in_\(audio?.isBargeInActive == true ? "enabled" : "disabled")")

        case "toggle_mute":
            audio?.toggleMute()
            completeTask(task.id, result: audio?.isMuted == true ? "muted" : "unmuted")

        case "ping":
            completeTask(task.id, result: "pong")

        case "capabilities":
            if let ws = webSocket, let ff = frameFactory {
                let heartbeat = ff.makeHeartbeat(
                    audioActive: audio?.state == .recording,
                    visionActive: vision?.isActive == true,
                    mlActive: false,
                    capabilities: capabilities,
                    batteryLevel: 1.0
                )
                ws.forwardHeartbeat(heartbeat)
            }
            completeTask(task.id, result: "capabilities_sent")

        case "node_registration":
            if let ws = webSocket, let ff = frameFactory {
                let nodeId = ws.sessionId
                let reg = NodeRegistrationFrame(
                    nodeId: nodeId,
                    device: UIDevice.current.model,
                    systemVersion: UIDevice.current.systemVersion,
                    capabilities: capabilities,
                    mlInfo: [:],
                    authority: .edgeWorker
                )
                let msg = CanaryMessage.nodeRegistration(dict: reg.dictionary)
                ws.send(msg)
            }
            completeTask(task.id, result: "registration_sent")

        case "rasa_boost":
            if let transcript = payload["transcript"] as? String {
                let confidence = payload["confidence"] as? Float ?? 0.5
                let intent = payload["intent"] as? String ?? "unknown"
                let entities = payload["entities"] as? [String: String] ?? [:]
                if let ws = webSocket, let ff = frameFactory {
                    let boost = ff.makeRasaBoost(transcript: transcript, confidence: confidence,
                                                  intent: intent, entities: entities)
                    ws.forwardRasaBoost(boost)
                }
                completeTask(task.id, result: "rasa_boost_sent")
            } else {
                failTask(task.id, error: "missing_transcript")
            }

        case "parlai_boost":
            if let context = payload["context"] as? String {
                let turnId = payload["turn_id"] as? String ?? UUID().uuidString
                if let ws = webSocket, let ff = frameFactory {
                    let boost = ff.makeParlaiBoost(context: context, turnId: turnId)
                    ws.forwardParlaiBoost(boost)
                }
                completeTask(task.id, result: "parlai_boost_sent")
            } else {
                failTask(task.id, error: "missing_context")
            }

        case "send_audio_feature":
            if let audioDataStr = payload["data"] as? String,
               let audioData = Data(base64Encoded: audioDataStr) {
                let sampleRate = payload["sample_rate"] as? Int ?? 16000
                if let ws = webSocket, let ff = frameFactory {
                    let frame = ff.makeAudioFeatureFrame(
                        data: audioData, sampleRate: sampleRate, channels: 1,
                        durationMs: payload["duration_ms"] as? Int ?? 100,
                        vadActive: payload["vad"] as? Bool ?? false,
                        rmsLevel: payload["rms"] as? Float ?? 0,
                        peakLevel: payload["peak"] as? Float ?? 0
                    )
                    ws.forwardAudioFeatureFrame(frame)
                }
                completeTask(task.id, result: "audio_feature_sent")
            } else {
                failTask(task.id, error: "missing_audio_data")
            }

        default:
            completeTask(task.id, result: "comando_no_implementado: \(task.type)")
        }

        if task.type != "ping" {
            activeTask = ""
        }
    }

    private func updateTask(_ id: String, status: WorkerTask.TaskStatus) {
        if let idx = taskHistory.firstIndex(where: { $0.id == id }) {
            taskHistory[idx].status = status
        }
    }

    private func completeTask(_ id: String, result: String) {
        if let idx = taskHistory.firstIndex(where: { $0.id == id }) {
            taskHistory[idx].status = .completed
            taskHistory[idx].completedAt = Date()
            taskHistory[idx].result = result
        }
        if taskHistory.count > 100 {
            taskHistory = Array(taskHistory.suffix(50))
        }
    }

    private func failTask(_ id: String, error: String) {
        if let idx = taskHistory.firstIndex(where: { $0.id == id }) {
            taskHistory[idx].status = .failed
            taskHistory[idx].completedAt = Date()
            taskHistory[idx].result = error
        }
    }
}
