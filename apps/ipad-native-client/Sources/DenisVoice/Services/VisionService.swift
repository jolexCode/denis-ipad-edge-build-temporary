import AVFoundation
import CoreImage
import Vision

@MainActor
class VisionService: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var isFrontCamera = false
    @Published var lastFrameSize: CGSize = .zero
    @Published var frameRate: Double = 0
    @Published var hasTrueDepth = false

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "vision.capture", qos: .userInitiated)
    private var frameCount = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var onFrame: ((CVPixelBuffer, String) -> Void)?
    private var onFaceFrame: ((CVPixelBuffer) -> Void)?
    private var currentCameraPosition: String = "back"

    var faceIDService: FaceIDService?

    func configure(onFrame: @escaping (CVPixelBuffer, String) -> Void,
                   onFace: ((CVPixelBuffer) -> Void)? = nil) {
        self.onFrame = onFrame
        self.onFaceFrame = onFace
    }

    func startCapture(position: AVCaptureDevice.Position = .back) throws {
        guard !isActive else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        #if targetEnvironment(simulator)
        throw VisionError.noCamera
        #else
        let device: AVCaptureDevice
        if position == .front {
            if let trueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
                device = trueDepth
                hasTrueDepth = true
                currentCameraPosition = "front_true_depth"
            } else if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                device = front
                currentCameraPosition = "front"
            } else {
                throw VisionError.noCamera
            }
            isFrontCamera = true
        } else {
            guard let backCam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ??
                                AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) ??
                                AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) else {
                throw VisionError.noCamera
            }
            device = backCam
            currentCameraPosition = "back"
            isFrontCamera = false
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw VisionError.inputFailed }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw VisionError.outputFailed }
        session.addOutput(output)

        session.sessionPreset = .medium
        session.startRunning()
        isActive = true
        #endif
    }

    func stopCapture() {
        session.stopRunning()
        isActive = false
        isFrontCamera = false
        hasTrueDepth = false
    }

    func switchCamera() throws {
        let newPosition: AVCaptureDevice.Position = isFrontCamera ? .back : .front
        stopCapture()
        try startCapture(position: newPosition)
    }
}

extension VisionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                    didOutput sampleBuffer: CMSampleBuffer,
                                    from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        Task { @MainActor in
            lastFrameSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                    height: CVPixelBufferGetHeight(pixelBuffer))
            if lastTimestamp > 0 {
                frameRate = 1.0 / (timestamp - lastTimestamp)
            }
            lastTimestamp = timestamp
        }

        Task { @MainActor [weak self] in
            let position = self?.currentCameraPosition ?? "unknown"
            self?.onFrame?(pixelBuffer, position)
            self?.faceIDService?.detectFaces(in: pixelBuffer)
            self?.faceIDService?.checkAttention(in: pixelBuffer)
            self?.onFaceFrame?(pixelBuffer)
        }
    }
}

enum VisionError: LocalizedError {
    case noCamera
    case inputFailed
    case outputFailed

    var errorDescription: String? {
        switch self {
        case .noCamera: return "Cámara no disponible en este dispositivo"
        case .inputFailed: return "No se pudo configurar la entrada de cámara"
        case .outputFailed: return "No se pudo configurar la salida de video"
        }
    }
}
