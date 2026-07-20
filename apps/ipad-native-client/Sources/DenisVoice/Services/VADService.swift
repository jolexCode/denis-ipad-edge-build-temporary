import Accelerate
import AVFoundation

@MainActor
class VADService: ObservableObject {
    @Published var isVoiceActive = false
    @Published var voiceLevel: Float = 0.0
    @Published var noiseFloor: Float = 0.0

    private var framesSinceVoice: Int = 0
    private let voiceThreshold: Float = 0.025
    private let hangoverFrames: Int = 15
    private var runningRmsSum: Float = 0
    private var runningRmsCount: Int = 0
    private let adaptationPeriod: Int = 50

    func analyze(_ pcmData: Data) -> Bool {
        let samples = pcmData.withUnsafeBytes { ptr -> [Int16] in
            Array(UnsafeBufferPointer(start: ptr.bindMemory(to: Int16.self).baseAddress,
                                      count: pcmData.count / MemoryLayout<Int16>.size))
        }
        guard !samples.isEmpty else { return isVoiceActive }

        let sumSquares = samples.reduce(Double(0)) { sum, sample in
            let normalized = Double(sample) / Double(Int16.max)
            return sum + normalized * normalized
        }
        let normalizedRms = Float(sqrt(sumSquares / Double(samples.count)))

        voiceLevel = normalizedRms

        if runningRmsCount < adaptationPeriod {
            runningRmsSum += normalizedRms
            runningRmsCount += 1
            noiseFloor = runningRmsSum / Float(runningRmsCount)
        }

        let adjustedThreshold = max(voiceThreshold, noiseFloor * 1.5)

        if normalizedRms > adjustedThreshold {
            framesSinceVoice = 0
            if !isVoiceActive {
                isVoiceActive = true
            }
        } else {
            framesSinceVoice += 1
            if framesSinceVoice >= hangoverFrames {
                isVoiceActive = false
            }
        }

        return isVoiceActive
    }

    func reset() {
        isVoiceActive = false
        voiceLevel = 0
        noiseFloor = 0
        framesSinceVoice = 0
        runningRmsSum = 0
        runningRmsCount = 0
    }
}
