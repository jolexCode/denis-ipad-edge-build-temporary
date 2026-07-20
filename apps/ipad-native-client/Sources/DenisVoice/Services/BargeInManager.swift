import AVFoundation
import Accelerate

@MainActor
class BargeInManager: ObservableObject {
    @Published var isBargeInEnabled = true
    @Published var lastInterruption: Date?
    var onBargeIn: (() -> Void)?

    private weak var audioService: AudioService?

    func configure(audioService: AudioService, engine: AVAudioEngine) {
        self.audioService = audioService
        _ = engine
    }

    func startMonitoring() {
        // Input levels arrive from AudioService's single real microphone tap.
    }

    func stopMonitoring() {
        // No timer: polling fabricated buffers cannot detect speech.
    }

    func observeInputLevel(_ rms: Float) {
        guard isBargeInEnabled,
              let audio = audioService,
              audio.state == .playing else { return }
        if rms > 0.05 {
            lastInterruption = Date()
            onBargeIn?()
            audio.stopPlayback()
            audio.state = .recording
        }
    }

    func toggleBargeIn() {
        isBargeInEnabled.toggle()
        if isBargeInEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
}
