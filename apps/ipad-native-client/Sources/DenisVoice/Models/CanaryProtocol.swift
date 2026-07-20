import Foundation

enum CanaryMessage {
    case clientReady(sessionId: String, payload: [String: String])
    case micAudio(sessionId: String, format: String, sampleRate: Int, channels: Int, data: String, timestampMs: Int64)
    case ping
    case audioFrame(transcript: String, confidence: Float, voiceActivity: Bool, durationMs: Int, audioDataBytes: Int)
    case nodeRegistration(dict: [String: Any])
    case audioFeatureFrame(dict: [String: Any])
    case visionFeatureFrame(dict: [String: Any])
    case multimodalFeatureFrame(dict: [String: Any])
    case heartbeat(dict: [String: Any])
    case rasaBoost(dict: [String: Any])
    case parlaiBoost(dict: [String: Any])
    case pipecatFrame(dict: [String: Any])

    var type: String {
        switch self {
        case .clientReady: return "client_ready"
        case .micAudio: return "mic_audio"
        case .ping: return "ping"
        case .audioFrame: return "audio_frame"
        case .nodeRegistration: return "node_registration"
        case .audioFeatureFrame: return "audio_feature_frame"
        case .visionFeatureFrame: return "vision_feature_frame"
        case .multimodalFeatureFrame: return "multimodal_feature_frame"
        case .heartbeat: return "heartbeat"
        case .rasaBoost: return "rasa_feature_boost"
        case .parlaiBoost: return "parlai_context_boost"
        case .pipecatFrame: return "pipecat_realtime_frame"
        }
    }

    func encode() -> String? {
        var dict: [String: Any] = ["type": type]
        switch self {
        case .clientReady(let sessionId, let payload):
            dict["session_id"] = sessionId
            dict["payload"] = payload
        case .micAudio(let sessionId, let format, let sampleRate, let channels, let data, let timestampMs):
            dict["session_id"] = sessionId
            dict["format"] = format
            dict["sample_rate"] = sampleRate
            dict["channels"] = channels
            dict["data"] = data
            dict["timestamp_ms"] = timestampMs
        case .ping:
            break
        case .audioFrame(let transcript, let confidence, let voiceActivity, let durationMs, let audioDataBytes):
            dict["transcript"] = transcript
            dict["confidence"] = confidence
            dict["voice_activity"] = voiceActivity
            dict["duration_ms"] = durationMs
            dict["audio_data_bytes"] = audioDataBytes
        case .nodeRegistration(let d),
             .audioFeatureFrame(let d),
             .visionFeatureFrame(let d),
             .multimodalFeatureFrame(let d),
             .heartbeat(let d),
             .rasaBoost(let d),
             .parlaiBoost(let d),
             .pipecatFrame(let d):
            dict.merge(d) { $1 }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ text: String) -> (type: String, dict: [String: Any])? {
        guard let data = text.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        return (type, dict)
    }
}

struct AudioFrame {
    let data: Data
    let sampleRate: Double
    let channels: Int
    let timestampMs: Int64
    let durationMs: Int

    func toBase64() -> String {
        data.base64EncodedString()
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

enum AudioState: Equatable {
    case idle
    case recording
    case playing
    case error(String)
}
