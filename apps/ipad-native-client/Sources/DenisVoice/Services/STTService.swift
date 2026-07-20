import Speech
import AVFoundation

@MainActor
class STTService: ObservableObject {
    @Published var isAvailable = false
    @Published var isRecognizing = false
    @Published var lastTranscript: String = ""
    @Published var lastConfidence: Float = 0

    private let recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    var onTranscript: ((String, Float) -> Void)?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
        let queue = OperationQueue()
        queue.name = "stt.recognition"
        queue.qualityOfService = .userInitiated
        recognizer?.queue = queue
        checkAvailability()
    }

    func checkAvailability() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAvailable = status == .authorized && self?.recognizer?.isAvailable == true
            }
        }
    }

    func startRecognition() throws {
        guard let recognizer, recognizer.isAvailable else { throw STTError.unavailable }
        stopRecognition()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.taskHint = .dictation

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            Task { @MainActor in
                if let error = error {
                    if (error as NSError).code != 216 {
                        self?.isRecognizing = false
                    }
                    return
                }
                guard let result else { return }
                let transcript = result.bestTranscription.formattedString
                let confidence = result.bestTranscription.segments.first?.confidence ?? 0
                self?.lastTranscript = transcript
                self?.lastConfidence = confidence
                self?.onTranscript?(transcript, confidence)
            }
        }

        isRecognizing = true
    }

    /// AudioService owns the only input tap. Sharing buffers avoids the
    /// AVAudioEngine crash caused by installing two taps on bus zero.
    func append(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecognizing = false
    }

}

enum STTError: LocalizedError {
    case unavailable
    case engineFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Reconocimiento de voz no disponible"
        case .engineFailed: return "Error al iniciar engine de audio para STT"
        }
    }
}
