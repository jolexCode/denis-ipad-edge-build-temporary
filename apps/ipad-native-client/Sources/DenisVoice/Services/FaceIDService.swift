import LocalAuthentication
import Vision
import AVFoundation
import UIKit

@MainActor
class FaceIDService: ObservableObject {
    @Published var isAvailable = false
    @Published var isAuthenticated = false
    @Published var lastAuthResult: String = ""
    @Published var faceDetected = false
    @Published var faceCount: Int = 0
    @Published var attentionAware = false
    @Published var lastFaceRect: CGRect = .zero

    private let context = LAContext()
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var faceLandmarksRequest: VNDetectFaceLandmarksRequest?
    private var sequenceHandler = VNSequenceRequestHandler()
    private var evaluationDate: Date?

    func configure() {
        checkAvailability()
        setupVision()
    }

    func checkAvailability() {
        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticate(reason: String = "Denis necesita verificar tu identidad") async -> Bool {
        guard isAvailable else {
            lastAuthResult = "Face ID no disponible"
            return false
        }

        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, error in
                Task { @MainActor in
                    if success {
                        self?.isAuthenticated = true
                        self?.lastAuthResult = "Autenticado vía Face ID"
                        self?.evaluationDate = Date()
                    } else {
                        self?.isAuthenticated = false
                        self?.lastAuthResult = error?.localizedDescription ?? "Falló autenticación"
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func detectFaces(in pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let results = request.results as? [VNFaceObservation] else { return }
            Task { @MainActor in
                self?.faceCount = results.count
                self?.faceDetected = !results.isEmpty
                self?.lastFaceRect = results.first?.boundingBox ?? .zero
            }
        }
        request.revision = VNDetectFaceRectanglesRequestRevision3
        try? handler.perform([request])
    }

    func checkAttention(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let results = request.results as? [VNFaceObservation] else { return }
            let hasAttention = results.contains { obs in
                obs.roll.map { abs($0.floatValue) < 0.3 } ?? true
            }
            Task { @MainActor in
                self?.attentionAware = hasAttention
            }
        }
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }

    var statePayload: [String: Any] {
        [
            "available": isAvailable,
            "authenticated": isAuthenticated,
            "face_detected": faceDetected,
            "face_count": faceCount,
            "attention_aware": attentionAware,
            "last_auth": evaluationDate?.ISO8601Format() ?? "",
        ]
    }

    func logout() {
        isAuthenticated = false
        lastAuthResult = "Sesión cerrada"
        evaluationDate = nil
    }

    private func setupVision() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
        faceDetectionRequest?.revision = VNDetectFaceRectanglesRequestRevision3
        faceLandmarksRequest = VNDetectFaceLandmarksRequest()
    }
}
