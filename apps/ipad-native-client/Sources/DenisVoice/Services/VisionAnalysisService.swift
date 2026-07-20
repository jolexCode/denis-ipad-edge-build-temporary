import Foundation
import Vision
import CoreVideo

struct VisionAnalysisService {
    static func analyze(pixelBuffer: CVPixelBuffer, maxResults: Int = 12) -> [VisionObservation] {
        var observations: [VisionObservation] = []
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        textRequest.maximumRecognitionCandidates = 1
        let barcodeRequest = VNDetectBarcodesRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 4

        do {
            try handler.perform([faceRequest, textRequest, barcodeRequest, rectangleRequest])
        } catch {
            return [VisionObservation(kind: "vision_error", label: error.localizedDescription, confidence: 0, boundingBox: [:])]
        }

        observations.append(contentsOf: (faceRequest.results ?? []).prefix(maxResults).map {
            VisionObservation(kind: "face", label: "face", confidence: $0.confidence, boundingBox: box($0.boundingBox))
        })

        observations.append(contentsOf: (textRequest.results ?? []).prefix(maxResults).compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return VisionObservation(kind: "text", label: candidate.string, confidence: candidate.confidence, boundingBox: box(obs.boundingBox))
        })

        observations.append(contentsOf: (barcodeRequest.results ?? []).prefix(maxResults).map { obs in
            VisionObservation(kind: "barcode", label: obs.payloadStringValue ?? obs.symbology.rawValue, confidence: obs.confidence, boundingBox: box(obs.boundingBox))
        })

        observations.append(contentsOf: (rectangleRequest.results ?? []).prefix(maxResults).map {
            VisionObservation(kind: "rectangle", label: "rectangle", confidence: $0.confidence, boundingBox: box($0.boundingBox))
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
