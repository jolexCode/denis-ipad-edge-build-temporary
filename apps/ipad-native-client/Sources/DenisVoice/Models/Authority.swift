import Foundation

struct AuthorityFlags: Codable, Equatable {
    var technicalAuthority: Bool = true
    var semanticAuthority: Bool = false
    var mutationAuthority: Bool = false
    var finalResponseAuthority: Bool = false
    var memoryAuthority: Bool = false
    var graphAuthority: Bool = false
    var ownerAuthority: Bool = false

    var candidateOnly: Bool = true

    static let edgeWorker = AuthorityFlags(
        technicalAuthority: true,
        semanticAuthority: false,
        mutationAuthority: false,
        finalResponseAuthority: false,
        memoryAuthority: false,
        graphAuthority: false,
        ownerAuthority: false,
        candidateOnly: true
    )

    var dictionary: [String: Any] {
        [
            "technical_authority": technicalAuthority,
            "semantic_authority": semanticAuthority,
            "mutation_authority": mutationAuthority,
            "final_response_authority": finalResponseAuthority,
            "memory_authority": memoryAuthority,
            "graph_authority": graphAuthority,
            "owner_authority": ownerAuthority,
            "candidate_only": candidateOnly,
        ]
    }
}

struct CapabilitySet: Codable {
    var audioCapture: Bool = true
    var audioPlayback: Bool = true
    var visionCapture: Bool = true
    var mlInference: Bool = true
    var neuralEngine: Bool = true
    var gpuCompute: Bool = true
    var vad: Bool = true
    var onDeviceSTT: Bool = true
    var bargeIn: Bool = true
    var pipecat: Bool = false
    var webrtc: Bool = false
    var backgroundAudio: Bool = true

    var payload: [String: Any] {
        [
            "audio_capture": audioCapture,
            "audio_playback": audioPlayback,
            "vision_capture": visionCapture,
            "ml_inference": mlInference,
            "neural_engine": neuralEngine,
            "gpu_compute": gpuCompute,
            "vad": vad,
            "on_device_stt": onDeviceSTT,
            "barge_in": bargeIn,
            "pipecat": pipecat,
            "webrtc": webrtc,
            "background_audio": backgroundAudio,
        ]
    }
}
