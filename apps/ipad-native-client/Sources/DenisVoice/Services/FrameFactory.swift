import Foundation
import CoreVideo
import CoreMedia

@MainActor
class FrameFactory: ObservableObject {
    var nodeId: String = ""
    private var audioSequence: Int = 0
    private var visionSequence: Int = 0

    func makeAudioFeatureFrame(data: Data, sampleRate: Int, channels: Int, durationMs: Int,
                               vadActive: Bool, rmsLevel: Float, peakLevel: Float) -> AudioFeatureFrame {
        audioSequence += 1
        return AudioFeatureFrame(
            nodeId: nodeId,
            format: "pcm_s16le",
            sampleRate: sampleRate,
            channels: channels,
            data: data.base64EncodedString(),
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            durationMs: durationMs,
            vadActive: vadActive,
            rmsLevel: rmsLevel,
            peakLevel: peakLevel,
            sequenceNumber: audioSequence,
            authority: .edgeWorker
        )
    }

    func makeVisionFeatureFrame(pixelBuffer: CVPixelBuffer, cameraPosition: String) -> VisionFeatureFrame? {
        visionSequence += 1
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dataSize = bytesPerRow * height
        let data = Data(bytes: baseAddress, count: dataSize).base64EncodedString()

        return VisionFeatureFrame(
            nodeId: nodeId,
            width: width,
            height: height,
            format: "bgra",
            data: data,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            cameraPosition: cameraPosition,
            sequenceNumber: visionSequence,
            authority: .edgeWorker
        )
    }

    func makeHeartbeat(audioActive: Bool, visionActive: Bool, mlActive: Bool,
                       capabilities: CapabilitySet, batteryLevel: Float) -> HeartbeatFrame {
        let start = ProcessInfo.processInfo.systemUptime
        return HeartbeatFrame(
            nodeId: nodeId,
            uptimeMs: Int64(start * 1000),
            audioActive: audioActive,
            visionActive: visionActive,
            mlActive: mlActive,
            capabilities: capabilities,
            batteryLevel: batteryLevel,
            authority: .edgeWorker
        )
    }

    func makeRasaBoost(transcript: String, confidence: Float, intent: String, entities: [String: String]) -> RasaFeatureBoost {
        RasaFeatureBoost(
            nodeId: nodeId,
            transcript: transcript,
            confidence: confidence,
            intent: intent,
            entities: entities,
            authority: .edgeWorker
        )
    }

    func makeParlaiBoost(context: String, turnId: String) -> ParlAIContextBoost {
        ParlAIContextBoost(
            nodeId: nodeId,
            context: context,
            turnId: turnId,
            authority: .edgeWorker
        )
    }

    func resetSequences() {
        audioSequence = 0
        visionSequence = 0
    }
}
