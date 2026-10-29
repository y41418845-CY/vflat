import Foundation
import CoreVideo
import Vision
import CoreGraphics

/// 描述偵測到的文件四邊角點 (Normalized 0.0 .. 1.0, 螢幕座標系 Top-Left 原點)
public struct DetectedDocument: Equatable {
    public let topLeft: CGPoint
    public let topRight: CGPoint
    public let bottomRight: CGPoint
    public let bottomLeft: CGPoint
    public let confidence: Float

    public init(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        confidence: Float
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
    }
}

/// 透過 Apple Vision 框架在相機串流中即時偵測文件/矩形邊界
public final class DocumentDetector {
    private let detectionQueue = DispatchQueue(label: "com.vflat.ios.detector", qos: .userInteractive)
    private var isProcessing = false
    private var lastProcessTime: TimeInterval = 0
    private let throttleInterval: TimeInterval = 1.0 / 20.0 // 限制在 20fps，兼顧即時性與電池功耗

    public var onDocumentDetected: ((DetectedDocument?) -> Void)?

    public init() {}

    /// 傳入相機影格 (CVPixelBuffer) 進行非同步文件邊緣分析
    public func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessTime >= throttleInterval else { return }

        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isProcessing { return }
            self.isProcessing = true
            self.lastProcessTime = currentTime

            let request = VNDetectRectanglesRequest { [weak self] req, error in
                defer { self?.isProcessing = false }

                guard error == nil,
                      let results = req.results as? [VNRectangleObservation],
                      let topRect = results.first,
                      topRect.confidence > 0.4 else {
                    self?.onDocumentDetected?(nil)
                    return
                }

                // Vision 座標為左下原點 (0,0 在左下)，轉換為 SwiftUI/螢幕標準 (0,0 在左上)
                let doc = DetectedDocument(
                    topLeft: CGPoint(x: topRect.topLeft.x, y: 1.0 - topRect.topLeft.y),
                    topRight: CGPoint(x: topRect.topRight.x, y: 1.0 - topRect.topRight.y),
                    bottomRight: CGPoint(x: topRect.bottomRight.x, y: 1.0 - topRect.bottomRight.y),
                    bottomLeft: CGPoint(x: topRect.bottomLeft.x, y: 1.0 - topRect.bottomLeft.y),
                    confidence: topRect.confidence
                )

                self?.onDocumentDetected?(doc)
            }

            request.maximumObservations = 1
            request.minimumConfidence = 0.4
            request.minimumAspectRatio = 0.2
            request.maximumAspectRatio = 1.0
            request.quadratureTolerance = 30.0

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                self.isProcessing = false
                self.onDocumentDetected?(nil)
            }
        }
    }
}
