import CoreML
import Accelerate
import Metal
import Vision

@MainActor
class MLService: ObservableObject {
    @Published var isReady = false
    @Published var activeModel: String = ""
    @Published var lastInferenceMs: Double = 0
    @Published var availableModels: [String] = []

    private let metalDevice: MTLDevice?
    private var models: [String: MLModel] = [:]
    private let queue = DispatchQueue(label: "ml.inference", qos: .userInitiated)

    init() {
        metalDevice = MTLCreateSystemDefaultDevice()
    }

    func loadModel(name: String, url: URL? = nil) throws {
        let modelURL = url ?? Bundle.main.url(forResource: name, withExtension: "mlmodelc")!
        let model = try MLModel(contentsOf: modelURL)
        models[name] = model
        activeModel = name
        isReady = true
        if !availableModels.contains(name) {
            availableModels.append(name)
        }
    }

    func predict(modelName: String, input: [String: Any]) throws -> [String: Any] {
        guard let model = models[modelName] else {
            throw MLError.modelNotLoaded
        }
        let start = CFAbsoluteTimeGetCurrent()
        let provider = try MLDictionaryFeatureProvider(dictionary: input as [String: NSObject])
        let result = try model.prediction(from: provider)
        lastInferenceMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        var output = [String: Any]()
        for (key, value) in result.featureValueDictionary {
            output[key] = value
        }
        return output
    }

    func predictVision(modelName: String, pixelBuffer: CVPixelBuffer) throws -> [String: Any] {
        guard let model = models[modelName] else {
            throw MLError.modelNotLoaded
        }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try model.prediction(from: [modelName: pixelBuffer])
        lastInferenceMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        var output = [String: Any]()
        for (key, value) in result.featureValueDictionary {
            output[key] = value
        }
        return output
    }

    func predictFaceEmbedding(pixelBuffer: CVPixelBuffer) -> [Float]? {
        return nil
    }

    func unloadModel(name: String) {
        models.removeValue(forKey: name)
        activeModel = models.keys.first ?? ""
        isReady = !models.isEmpty
        availableModels.removeAll { $0 == name }
    }

    func unloadAll() {
        models.removeAll()
        activeModel = ""
        isReady = false
        availableModels.removeAll()
    }

    var hasANE: Bool {
        metalDevice?.hasUnifiedMemory ?? false
    }

    var hasGPU: Bool {
        metalDevice != nil
    }

    var systemInfo: [String: String] {
        [
            "ane": hasANE ? "available" : "unavailable",
            "gpu": hasGPU ? "available" : "unavailable",
            "gpu_name": metalDevice?.name ?? "none",
            "unified_memory": metalDevice?.hasUnifiedMemory == true ? "true" : "false",
            "max_buffer_length": "\(metalDevice?.maxBufferLength ?? 0)",
            "available_models": availableModels.joined(separator: ","),
        ]
    }
}

enum MLError: LocalizedError {
    case modelNotLoaded
    case inferenceFailed(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Modelo no cargado"
        case .inferenceFailed(let reason): return "Inferencia fallida: \(reason)"
        case .unsupportedFormat: return "Formato de entrada no soportado"
        }
    }
}
