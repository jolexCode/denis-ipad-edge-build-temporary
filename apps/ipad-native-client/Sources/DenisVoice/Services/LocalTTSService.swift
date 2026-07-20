import AVFoundation

@MainActor
final class LocalTTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    var onSpeakingChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, locale: String = "es-ES") {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice(locale: locale)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.04
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func preferredVoice(locale: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == locale }
        return voices.sorted { $0.quality.rawValue > $1.quality.rawValue }.first
            ?? AVSpeechSynthesisVoice(language: locale)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true; onSpeakingChanged?(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false; onSpeakingChanged?(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false; onSpeakingChanged?(false)
    }
}
