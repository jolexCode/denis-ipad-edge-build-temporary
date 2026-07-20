import Foundation
import Vision
import CoreVideo

struct DenisVisionObservation: Codable, Sendable {
    let kind: String
    let label: String
    let confidence: Float
    let boundingBox: [String: Double]
}

struct VisionAnalysisService {
    static func analyze(pixelBuffer: CVPixelBuffer, maxResults: Int = 12) -> [DenisVisionObservation] {
        var observations: [DenisVisionObservation] = []
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let barcodeRequest = VNDetectBarcodesRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 4

        do {
            try handler.perform([faceRequest, textRequest, barcodeRequest, rectangleRequest])
        } catch {
            return [DenisVisionObservation(kind: "vision_error", label: error.localizedDescription, confidence: 0, boundingBox: [:])]
        }

        observations.append(contentsOf: (faceRequest.results ?? []).prefix(maxResults).map {
            DenisVisionObservation(kind: "face", label: "face", confidence: $0.confidence, boundingBox: box($0.boundingBox))
        })

        observations.append(contentsOf: (textRequest.results ?? []).prefix(maxResults).compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return DenisVisionObservation(kind: "text", label: candidate.string, confidence: candidate.confidence, boundingBox: box(obs.boundingBox))
        })

        observations.append(contentsOf: (barcodeRequest.results ?? []).prefix(maxResults).map { obs in
            DenisVisionObservation(kind: "barcode", label: obs.payloadStringValue ?? obs.symbology.rawValue, confidence: obs.confidence, boundingBox: box(obs.boundingBox))
        })

        observations.append(contentsOf: (rectangleRequest.results ?? []).prefix(maxResults).map {
            DenisVisionObservation(kind: "rectangle", label: "rectangle", confidence: $0.confidence, boundingBox: box($0.boundingBox))
        })

        return Array(observations.prefix(maxResults))
    }

    private static func box(_ rect: CGRect) -> [String: Double] {
        [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.width,
            "height": rect.height,
        ]
    }
}
