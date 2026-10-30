import Foundation
import UIKit
import Vision
import CoreVideo

struct DetectedDocument: Codable, Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    var confidence: Float
}

struct DetectedBarcode: Equatable {
    let payloadString: String
    let symbology: VNBarcodeSymbology
    var isURL: Bool
    var iconName: String
}

final class DocumentDetector {
    private let request = VNDetectRectanglesRequest()
    private var smoothed: DetectedDocument?
    private let alpha: CGFloat = 0.3

    init() {
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.2
        request.minimumConfidence = 0.6
        request.quadratureTolerance = 30
    }

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectedDocument? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first else { return nil }
        let doc = DetectedDocument(
            topLeft: CGPoint(x: obs.topLeft.x, y: 1 - obs.topLeft.y),
            topRight: CGPoint(x: obs.topRight.x, y: 1 - obs.topRight.y),
            bottomRight: CGPoint(x: obs.bottomRight.x, y: 1 - obs.bottomRight.y),
            bottomLeft: CGPoint(x: obs.bottomLeft.x, y: 1 - obs.bottomLeft.y),
            confidence: obs.confidence
        )
        return smooth(doc)
    }

    func detect(in image: UIImage) -> DetectedDocument? {
        guard let cg = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first else { return nil }
        return DetectedDocument(
            topLeft: CGPoint(x: obs.topLeft.x, y: 1 - obs.topLeft.y),
            topRight: CGPoint(x: obs.topRight.x, y: 1 - obs.topRight.y),
            bottomRight: CGPoint(x: obs.bottomRight.x, y: 1 - obs.bottomRight.y),
            bottomLeft: CGPoint(x: obs.bottomLeft.x, y: 1 - obs.bottomLeft.y),
            confidence: obs.confidence
        )
    }

    static func detectOnce(in pixelBuffer: CVPixelBuffer) -> DetectedDocument? {
        let d = DocumentDetector()
        // bypass smoothing by direct
        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.3
        req.maximumAspectRatio = 1.0
        req.minimumSize = 0.2
        req.minimumConfidence = 0.6
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do { try handler.perform([req]) } catch { return nil }
        guard let obs = req.results?.first else { return nil }
        return DetectedDocument(
            topLeft: CGPoint(x: obs.topLeft.x, y: 1 - obs.topLeft.y),
            topRight: CGPoint(x: obs.topRight.x, y: 1 - obs.topRight.y),
            bottomRight: CGPoint(x: obs.bottomRight.x, y: 1 - obs.bottomRight.y),
            bottomLeft: CGPoint(x: obs.bottomLeft.x, y: 1 - obs.bottomLeft.y),
            confidence: obs.confidence
        )
    }

    static func detectOnce(in image: UIImage) -> DetectedDocument? {
        let d = DocumentDetector()
        return d.detect(in: image)
    }

    private func smooth(_ doc: DetectedDocument) -> DetectedDocument {
        if let prev = smoothed {
            let s = DetectedDocument(
                topLeft: CGPoint(x: prev.topLeft.x + (doc.topLeft.x - prev.topLeft.x) * alpha,
                                 y: prev.topLeft.y + (doc.topLeft.y - prev.topLeft.y) * alpha),
                topRight: CGPoint(x: prev.topRight.x + (doc.topRight.x - prev.topRight.x) * alpha,
                                  y: prev.topRight.y + (doc.topRight.y - prev.topRight.y) * alpha),
                bottomRight: CGPoint(x: prev.bottomRight.x + (doc.bottomRight.x - prev.bottomRight.x) * alpha,
                                     y: prev.bottomRight.y + (doc.bottomRight.y - prev.bottomRight.y) * alpha),
                bottomLeft: CGPoint(x: prev.bottomLeft.x + (doc.bottomLeft.x - prev.bottomLeft.x) * alpha,
                                    y: prev.bottomLeft.y + (doc.bottomLeft.y - prev.bottomLeft.y) * alpha),
                confidence: doc.confidence
            )
            smoothed = s
            return s
        }
        smoothed = doc
        return doc
    }

    func reset() { smoothed = nil }
}
