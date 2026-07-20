import Foundation

struct AudioFeatureFrame: Codable {
    let frameType: String = "audio_feature_frame"
    let nodeId: String
    let format: String
    let sampleRate: Int
    let channels: Int
    let data: String
    let timestampMs: Int64
    let durationMs: Int
    let vadActive: Bool
    let rmsLevel: Float
    let peakLevel: Float
    let sequenceNumber: Int
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "format": format,
            "sample_rate": sampleRate,
            "channels": channels,
            "data": data,
            "timestamp_ms": timestampMs,
            "duration_ms": durationMs,
            "vad_active": vadActive,
            "rms_level": rmsLevel,
            "peak_level": peakLevel,
            "sequence_number": sequenceNumber,
            "authority": authority.dictionary,
        ]
    }
}

struct VisionFeatureFrame: Codable {
    let frameType: String = "vision_feature_frame"
    let nodeId: String
    let width: Int
    let height: Int
    let format: String
    let data: String
    let timestampMs: Int64
    let cameraPosition: String
    let sequenceNumber: Int
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "width": width,
            "height": height,
            "format": format,
            "data": data,
            "timestamp_ms": timestampMs,
            "camera_position": cameraPosition,
            "sequence_number": sequenceNumber,
            "authority": authority.dictionary,
        ]
    }
}

struct MultimodalFeatureFrame: Codable {
    let frameType: String = "multimodal_feature_frame"
    let nodeId: String
    let audio: AudioFeatureFrame?
    let vision: VisionFeatureFrame?
    let metadata: [String: String]
    let timestampMs: Int64
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "audio": audio?.dictionary as Any,
            "vision": vision?.dictionary as Any,
            "metadata": metadata,
            "timestamp_ms": timestampMs,
            "authority": authority.dictionary,
        ]
    }
}

struct HeartbeatFrame: Codable {
    let frameType: String = "heartbeat"
    let nodeId: String
    let uptimeMs: Int64
    let audioActive: Bool
    let visionActive: Bool
    let mlActive: Bool
    let capabilities: CapabilitySet
    let batteryLevel: Float
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "uptime_ms": uptimeMs,
            "audio_active": audioActive,
            "vision_active": visionActive,
            "ml_active": mlActive,
            "capabilities": capabilities.payload,
            "battery_level": batteryLevel,
            "authority": authority.dictionary,
        ]
    }
}

struct RasaFeatureBoost: Codable {
    let frameType: String = "rasa_feature_boost"
    let nodeId: String
    let transcript: String
    let confidence: Float
    let intent: String
    let entities: [String: String]
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "transcript": transcript,
            "confidence": confidence,
            "intent": intent,
            "entities": entities,
            "authority": authority.dictionary,
        ]
    }
}

struct ParlAIContextBoost: Codable {
    let frameType: String = "parlai_context_boost"
    let nodeId: String
    let context: String
    let turnId: String
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "context": context,
            "turn_id": turnId,
            "authority": authority.dictionary,
        ]
    }
}

struct PipecatRealtimeFrame: Codable {
    let frameType: String = "pipecat_realtime_frame"
    let nodeId: String
    let transport: String
    let direction: String
    let payload: [String: Any]
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "transport": transport,
            "direction": direction,
            "payload": payload,
            "authority": authority.dictionary,
        ]
    }
}

struct NodeRegistrationFrame: Codable {
    let frameType: String = "node_registration"
    let nodeId: String
    let nodeType: String = "ipad_m1"
    let device: String
    let systemVersion: String
    let capabilities: CapabilitySet
    let mlInfo: [String: String]
    let authority: AuthorityFlags

    var dictionary: [String: Any] {
        [
            "type": frameType,
            "node_id": nodeId,
            "node_type": nodeType,
            "device": device,
            "system_version": systemVersion,
            "capabilities": capabilities.payload,
            "ml_info": mlInfo,
            "authority": authority.dictionary,
        ]
    }
}
