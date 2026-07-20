import Foundation

@MainActor
final class ContinuousPresenceCoordinator: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var lastCandidateAt: Date?
    private var analysisTask: Task<Void, Never>?

    private weak var audio: AudioService?
    private weak var tts: LocalTTSService?
    private let edge: FoundationModelsService
    private let transport: AppleEdgeTransport

    init(edge: FoundationModelsService, transport: AppleEdgeTransport) {
        self.edge = edge
        self.transport = transport
    }

    func configure(audio: AudioService, tts: LocalTTSService) {
        self.audio = audio
        self.tts = tts
        tts.onSpeakingChanged = { [weak audio] speaking in
            if !speaking, audio?.state == .playing { audio?.state = .recording }
        }
        transport.onWorkRequest = { [weak self] request in
            Task { @MainActor in await self?.handle(request) }
        }
        transport.onPersonaSurface = { [weak self] response in
            Task { @MainActor in self?.speakPersonaSurface(response.text) }
        }
    }

    func start() {
        active = true
        transport.connect()
        let nodeId = UIDevice.current.identifierForVendor?.uuidString ?? "ipad-m1"
        _ = transport.sendManifest(.current(nodeId: nodeId))
        try? audio?.startCapture()
    }

    func stop() {
        active = false
        analysisTask?.cancel()
        audio?.stopCapture()
        tts?.stop()
        transport.disconnect()
    }

    /// Partial STT updates are debounced; silence closes a human turn without
    /// requiring a hotword. Apple output remains candidate-only.
    func observeTranscript(_ text: String) {
        guard active else { return }
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            do {
                let frame = try await edge.analyze(text)
                let envelope = edge.encodeEnvelope(function: .intent, payload: .intent(frame), sourceText: text)
                _ = transport.send(envelope)
                lastCandidateAt = Date()
            } catch {
                // Fail closed: no direct-model or cloud fallback.
            }
        }
    }

    func speakPersonaSurface(_ text: String) {
        audio?.state = .playing
        tts?.speak(text)
    }

    private func handle(_ request: EdgeWorkRequest) async {
        if request.cancelPreviousTurn { analysisTask?.cancel() }
        do {
            if !(request.moduleInvocations ?? []).isEmpty {
                _ = transport.sendModuleResults(await edge.executeModules(request))
            }
            let frame = try await edge.analyze(request)
            let envelope = edge.encodeEnvelope(function: .intent, payload: .intent(frame), sourceText: request.userText, edgeStage: "fused")
            _ = transport.send(envelope)
            lastCandidateAt = Date()
        } catch {
            // Governed fail-closed: Persona receives no fabricated candidate.
        }
    }
}
