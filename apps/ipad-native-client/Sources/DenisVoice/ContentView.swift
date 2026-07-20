import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ws: WebSocketService
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var vad: VADService
    @EnvironmentObject var stt: STTService
    @EnvironmentObject var faceID: FaceIDService
    @EnvironmentObject var vision: VisionService
    @EnvironmentObject var ml: MLService
    @EnvironmentObject var worker: WorkerService
    @EnvironmentObject var bargeIn: BargeInManager

    @State private var showTaskHistory = false
    @State private var showFacePanel = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    audioCard
                    visionCard
                    faceIDCard
                    mlCard
                    workerCard
                    authorityCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Denis Edge Worker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        Button(showFacePanel ? "Ocultar" : "Face ID") {
                            withAnimation { showFacePanel.toggle() }
                        }
                        .font(.caption)
                        Button(showTaskHistory ? "Ocultar" : "Historial") {
                            withAnimation { showTaskHistory.toggle() }
                        }
                        .font(.caption)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if showFacePanel { facePanel }
                    if showTaskHistory { taskHistorySheet }
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionCard: some View {
        CardView {
            HStack {
                Circle().fill(connectionColor).frame(width: 14, height: 14)
                VStack(alignment: .leading) {
                    Text("Canary v\(ws.protocolVersion)")
                        .font(.headline)
                    Text(ws.lastCommand)
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if app.registeredInNeo4j {
                    Image(systemName: "server.rack").foregroundColor(.green)
                }
                VStack(alignment: .trailing) {
                    Text(app.uptimeFormatted).font(.caption2).monospacedDigit()
                    Button(ws.connectionState == .connected ? "Desconectar" : "Conectar") {
                        if ws.connectionState == .connected { ws.disconnect() }
                        else { ws.connect() }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }

    private var connectionColor: Color {
        switch ws.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }

    // MARK: - Audio + VAD + STT + BargeIn

    private var audioCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "waveform").foregroundColor(audio.state == .recording ? .green : .secondary)
                    Text("Audio Pipeline").font(.headline)
                    Spacer()
                    if audio.isBargeInActive {
                        Text("BARGE-IN").font(.caption2).bold()
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15)).cornerRadius(4)
                    }
                    LevelBar(level: audio.level).frame(width: 60, height: 20)
                }

                HStack(spacing: 8) {
                    Button(audio.state == .recording ? "Detener" : "Mic") {
                        if audio.state == .recording { audio.stopCapture() }
                        else { try? audio.startCapture() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(audio.state == .recording ? .red : .blue)
                    .controlSize(.small)

                    Button(audio.isMuted ? "Unmute" : "Mute") {
                        audio.toggleMute()
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button(bargeIn.isBargeInEnabled ? "B-In ON" : "B-In OFF") {
                        bargeIn.toggleBargeIn()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(bargeIn.isBargeInEnabled ? .orange : .gray)

                    Button("Test TTS") {
                        let msg = CanaryMessage.clientReady(
                            sessionId: ws.sessionId,
                            payload: ["action": "play_tts", "text": "Hola, soy Denis"]
                        )
                        ws.send(msg)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                HStack(spacing: 16) {
                    Label("VAD: \(vad.isVoiceActive ? "VOZ" : "silencio")", systemImage: vad.isVoiceActive ? "mic.fill" : "mic.slash")
                        .font(.caption).foregroundColor(vad.isVoiceActive ? .green : .secondary)
                    Label("STT: \(stt.isAvailable ? "OK" : "N/A")", systemImage: stt.isRecognizing ? "text.bubble" : "text.bubble.fill")
                        .font(.caption)
                }

                if !audio.lastTranscript.isEmpty {
                    HStack {
                        Image(systemName: "quote.bubble").font(.caption2)
                        Text(audio.lastTranscript).font(.caption).foregroundColor(.secondary).lineLimit(3)
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                HStack {
                    Text(audioStateLabel).font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("Nivel VAD: \(Int(vad.voiceLevel * 100))%").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private var audioStateLabel: String {
        switch audio.state {
        case .idle: return "Inactivo"
        case .recording: return "Grabando"
        case .playing: return "Reproduciendo"
        case .error(let e): return "Error: \(e)"
        }
    }

    // MARK: - Vision

    private var visionCard: some View {
        CardView {
            HStack {
                Image(systemName: vision.isActive ? "video.fill" : "video.slash")
                    .foregroundColor(vision.isActive ? .green : .secondary)
                Text("Visión").font(.headline)
                Spacer()
                if vision.isFrontCamera {
                    Text("Frontal").font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15)).cornerRadius(4)
                }
                if vision.hasTrueDepth {
                    Text("TrueDepth").font(.caption2)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15)).cornerRadius(4)
                }
            }

            HStack(spacing: 8) {
                Button(vision.isActive ? "Detener" : "Cámara") {
                    if vision.isActive { vision.stopCapture() }
                    else { try? vision.startCapture(position: .back) }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .tint(vision.isActive ? .red : .blue)

                Button("Cambiar") {
                    try? vision.switchCamera()
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!vision.isActive)

                Button("Face Auth") {
                    Task { await faceID.authenticate() }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!faceID.isAvailable)
            }

            if vision.isActive {
                HStack {
                    Text("\(Int(vision.frameRate)) fps").font(.caption2)
                    Text("\(Int(vision.lastFrameSize.width))×\(Int(vision.lastFrameSize.height))").font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            if !faceID.lastAuthResult.isEmpty {
                Text(faceID.lastAuthResult)
                    .font(.caption).foregroundColor(faceID.isAuthenticated ? .green : .red)
            }
        }
    }

    // MARK: - Face ID Panel

    private var faceIDCard: some View {
        CardView {
            HStack {
                Image(systemName: faceID.isAvailable ? "faceid" : "face.smiling")
                    .foregroundColor(faceID.isAuthenticated ? .green : .secondary)
                Text("Face ID").font(.headline)
                Spacer()
                if faceID.faceDetected {
                    Text("\(faceID.faceCount) rostro(s)").font(.caption)
                        .foregroundColor(.green)
                }
                if faceID.attentionAware {
                    Image(systemName: "eye.fill").foregroundColor(.blue).font(.caption)
                }
            }

            HStack(spacing: 8) {
                Button("Autenticar") {
                    Task { await faceID.authenticate() }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!faceID.isAvailable)

                Button("Cerrar sesión") {
                    faceID.logout()
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!faceID.isAuthenticated)
            }

            HStack {
                Circle()
                    .fill(faceID.faceDetected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(faceID.faceDetected ? "Rostro presente" : "Sin rostro")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("Atención: \(faceID.attentionAware ? "SI" : "NO")")
                    .font(.caption2).foregroundColor(faceID.attentionAware ? .green : .secondary)
            }
        }
    }

    private var facePanel: some View {
        VStack {
            Divider()
            VStack(spacing: 8) {
                Label("Face ID / Detección Facial", systemImage: "faceid")
                    .font(.subheadline).fontWeight(.medium)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Disponible: \(faceID.isAvailable ? "Sí" : "No")")
                        Text("Autenticado: \(faceID.isAuthenticated ? "Sí" : "No")")
                        Text("Rostros detectados: \(faceID.faceCount)")
                        Text("Atención: \(faceID.attentionAware ? "Sí" : "No")")
                    }
                    .font(.caption2)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Última auth: \(faceID.lastAuthResult)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .transition(.move(edge: .bottom))
    }

    // MARK: - ML Card

    private var mlCard: some View {
        CardView {
            HStack {
                Image(systemName: "cpu").foregroundColor(ml.isReady ? .green : .secondary)
                Text("M1 Neural Engine").font(.headline)
                Spacer()
                if ml.hasANE { badge("ANE", .green) }
                if ml.hasGPU { badge("GPU", .blue) }
            }

            HStack {
                Text("Modelo:").font(.caption)
                Text(ml.activeModel.isEmpty ? "ninguno" : ml.activeModel)
                    .foregroundColor(.secondary).font(.caption)
            }

            if ml.lastInferenceMs > 0 {
                Text("Última inferencia: \(Int(ml.lastInferenceMs))ms").font(.caption2).foregroundColor(.secondary)
            }

            if !ml.availableModels.isEmpty {
                Text("Modelos: \(ml.availableModels.joined(separator: ", "))")
                    .font(.caption2).foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button("Registrar nodo") {
                    Task { await app.registerNode() }
                }
                .buttonStyle(.bordered).controlSize(.small)

                Button("Capacidades") {
                    worker.handleCommand("capabilities", payload: [:])
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: - Worker Card

    private var workerCard: some View {
        CardView {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Worker").font(.headline)
                Spacer()
                if !worker.activeTask.isEmpty {
                    ProgressView().scaleEffect(0.7)
                    Text(worker.activeTask).font(.caption)
                }
                Text("\(worker.taskHistory.count) tareas").font(.caption2).foregroundColor(.secondary)
            }

            let recent = worker.taskHistory.suffix(3)
            if !recent.isEmpty {
                ForEach(recent) { task in
                    HStack {
                        Circle().fill(task.status == .completed ? Color.green :
                                       task.status == .failed ? Color.red : .yellow)
                            .frame(width: 8, height: 8)
                        Text(task.type).font(.caption)
                        Spacer()
                        Text(task.result ?? "").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Authority Card

    private var authorityCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "shield.checkered")
                    Text("Authority Invariants").font(.headline)
                    Spacer()
                    Text("EDGE WORKER").font(.caption2).bold()
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2)).cornerRadius(4)
                }

                let flags = AuthorityFlags.edgeWorker
                ForEach(Array(flags.dictionary.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                        Spacer()
                        let val = flags.dictionary[key] as? Bool ?? false
                        Image(systemName: val ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .foregroundColor(val ? .green : .red)
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Task History

    private var taskHistorySheet: some View {
        VStack {
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(worker.taskHistory.reversed()) { task in
                        HStack {
                            Image(systemName: task.status == .completed ? "checkmark.circle.fill" :
                                    task.status == .failed ? "xmark.circle.fill" : "clock")
                                .foregroundColor(task.status == .completed ? .green :
                                                   task.status == .failed ? .red : .yellow)
                            Text(task.type).font(.caption).fontWeight(.medium)
                            Text(task.receivedAt, style: .time).font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            if let result = task.result {
                                Text(result).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .frame(height: 200)
            .background(.ultraThinMaterial)
        }
        .transition(.move(edge: .bottom))
    }

    // MARK: - Helpers

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2)).cornerRadius(4)
    }
}

// MARK: - Subviews

struct CardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.green, .yellow, .red],
                                          startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(level, 1.0)))
            }
        }
    }
}
