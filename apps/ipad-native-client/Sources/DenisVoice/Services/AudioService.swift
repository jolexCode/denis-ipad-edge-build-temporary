import AVFoundation
import Accelerate

@MainActor
class AudioService: NSObject, ObservableObject {
    @Published var state: AudioState = .idle
    @Published var level: Float = 0.0
    @Published var lastTranscript: String = ""
    @Published var isMuted: Bool = false
    @Published var isBargeInActive: Bool = false

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private let bus = 0
    private let sampleRate: Double = 16000.0
    private let frameDuration: Double = 0.1
    private let canaryFramesPerSend = 10

    private var frameBuffer = [Data]()
    private var isEngineRunning = false
    private var onAudioFrame: ((AudioFrame) -> Void)?

    private var vadService: VADService?
    private var sttService: STTService?
    private var bargeInManager: BargeInManager?
    private var playbackNodes: [AVAudioPlayerNode] = []
    private var playbackEngines: [AVAudioEngine] = []

    override init() {
        super.init()
        setupNotifications()
    }

    func configure(onFrame: @escaping (AudioFrame) -> Void) {
        self.onAudioFrame = onFrame
    }

    func injectServices(vad: VADService, stt: STTService, bargeIn: BargeInManager) {
        vadService = vad
        sttService = stt
        bargeInManager = bargeIn
        bargeIn.configure(audioService: self, engine: engine)
    }

    func startCapture() throws {
        guard !isEngineRunning else { return }

        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay])
        if session.isEchoCancelledInputAvailable {
            try? session.setPrefersEchoCancelledInput(true)
        }
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: bus)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: sampleRate,
                                          channels: 1,
                                          interleaved: false)!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterFailed
        }

        input.installTap(onBus: bus, bufferSize: AVAudioFrameCount(sampleRate * frameDuration),
                         format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            self.processBuffer(buffer, converter: converter)
        }

        engine.prepare()
        try engine.start()
        isEngineRunning = true
        state = .recording

        try? sttService?.startRecognition()
        if bargeInManager?.isBargeInEnabled == true {
            bargeInManager?.startMonitoring()
        }
    }

    func stopCapture() {
        sttService?.stopRecognition()
        bargeInManager?.stopMonitoring()
        engine.inputNode.removeTap(onBus: bus)
        engine.stop()
        isEngineRunning = false
        state = .idle
        frameBuffer.removeAll()
    }

    func stopPlayback() {
        for node in playbackNodes {
            node.stop()
        }
        for eng in playbackEngines {
            eng.stop()
        }
        playbackNodes.removeAll()
        playbackEngines.removeAll()
        state = .recording
    }

    func playAudio(data: Data, sampleRate: Double = 24000.0) {
        state = .playing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.playPcmData(data, sampleRate: sampleRate)
        }
    }

    func playTTS(url: URL) {
        state = .playing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let data = try Data(contentsOf: url)
                self?.playPcmData(data, sampleRate: 24000.0)
            } catch {
                Task { @MainActor in
                    self?.state = .error("Error descargando TTS")
                }
            }
        }
    }

    func playTTSStreaming(data: Data) {
        playAudio(data: data)
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stopCapture()
        } else {
            try? startCapture()
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        sttService?.append(buffer)
        guard let onFrame = onAudioFrame else { return }
        guard let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                                frameCapacity: AVAudioFrameCount(sampleRate * frameDuration)) else { return }

        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, statusPtr in
            statusPtr.pointee = .haveData
            return buffer
        }

        guard status == .haveData,
              let channelData = converted.int16ChannelData?[0] else { return }

        let frameLength = Int(converted.frameLength)
        let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Int16>.size)
        frameBuffer.append(data)

        vadService?.analyze(data)

        if frameBuffer.count >= canaryFramesPerSend {
            let combined = frameBuffer.reduce(Data(), +)
            frameBuffer.removeAll()

            let frame = AudioFrame(
                data: combined,
                sampleRate: sampleRate,
                channels: 1,
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                durationMs: Int(Double(frameLength) / sampleRate * 1000) * canaryFramesPerSend
            )

            DispatchQueue.main.async { [self] in
                level = Float(data.withUnsafeBytes { ptr in
                    let samples = ptr.bindMemory(to: Int16.self)
                    var maxVal: Int16 = 0
                    vDSP_maxv(samples.baseAddress!, 1, &maxVal, vDSP_Length(samples.count))
                    return Float(maxVal) / Float(Int16.max)
                })
                bargeInManager?.observeInputLevel(level)
            }

            onFrame(frame)
        }
    }

    private func playPcmData(_ data: Data, sampleRate: Double) {
        do {
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: sampleRate,
                                        channels: 1,
                                        interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                           frameCapacity: AVAudioFrameCount(data.count / 2))!
            buffer.frameLength = buffer.frameCapacity
            data.withUnsafeBytes { src in
                buffer.int16ChannelData?[0].update(from: src.bindMemory(to: Int16.self).baseAddress!,
                                                    count: data.count / 2)
            }

            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            let playbackEngine = AVAudioEngine()
            playbackEngine.attach(player)
            playbackEngine.attach(mixer)
            playbackEngine.connect(player, to: mixer, format: format)
            playbackEngine.connect(mixer, to: playbackEngine.outputNode, format: format)

            try playbackEngine.start()
            playbackNodes.append(player)
            playbackEngines.append(playbackEngine)

            player.scheduleBuffer(buffer) { [weak self] in
                DispatchQueue.main.async {
                    if self?.state == .playing {
                        self?.state = .recording
                    }
                }
            }
            player.play()
        } catch {
            Task { @MainActor in
                state = .error("Error playback: \(error.localizedDescription)")
            }
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            if isEngineRunning { stopCapture() }
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                try? startCapture()
            }
        @unknown default: break
        }
    }
}

enum AudioError: LocalizedError {
    case converterFailed
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .converterFailed: return "No se pudo crear el conversor de audio"
        case .engineStartFailed: return "No se pudo iniciar el engine de audio"
        }
    }
}
