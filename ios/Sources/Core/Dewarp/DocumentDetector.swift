import Foundation
import CoreVideo
import Vision
import CoreGraphics
import QuartzCore

/// 描述偵測到的文件四邊角點 (Normalized 0.0 .. 1.0, 螢幕座標系 Top-Left 原點)
public struct DetectedDocument: Equatable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint
    public var confidence: Float

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

    /// 與另一個文件幾何座標進行指數平滑插值 (EMA Smoothing)
    public func smoothed(with target: DetectedDocument, alpha: CGFloat = 0.3) -> DetectedDocument {
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            return CGPoint(x: a.x + (b.x - a.x) * alpha, y: a.y + (b.y - a.y) * alpha)
        }

        return DetectedDocument(
            topLeft: lerp(self.topLeft, target.topLeft),
            topRight: lerp(self.topRight, target.topRight),
            bottomRight: lerp(self.bottomRight, target.bottomRight),
            bottomLeft: lerp(self.bottomLeft, target.bottomLeft),
            confidence: self.confidence + (target.confidence - self.confidence) * Float(alpha)
        )
    }
}

/// 透過 Apple Vision 框架在相機串流中即時偵測文件/矩形邊界，並具備 EMA 平滑防抖與防閃爍延遲
public final class DocumentDetector {
    private let detectionQueue = DispatchQueue(label: "com.vflat.ios.detector", qos: .userInteractive)
    private var isProcessing = false
    private var lastProcessTime: TimeInterval = 0
    private let throttleInterval: TimeInterval = 1.0 / 15.0 // 15fps 最佳平穩採樣率

    // 平滑濾波狀態
    private var currentSmoothedDoc: DetectedDocument? = nil
    private var lastDetectedTime: TimeInterval = 0
    private let persistenceWindow: TimeInterval = 0.35 // 350ms 滯後窗口，防止短暫掉幀產生劇烈閃爍

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
                guard let self = self else { return }

                let now = CACurrentMediaTime()

                if error == nil,
                   let results = req.results as? [VNRectangleObservation],
                   let topRect = results.first,
                   topRect.confidence > 0.45 {

                    // Vision 座標轉換為標準 (0,0 左上角)
                    let rawDoc = DetectedDocument(
                        topLeft: CGPoint(x: topRect.topLeft.x, y: 1.0 - topRect.topLeft.y),
                        topRight: CGPoint(x: topRect.topRight.x, y: 1.0 - topRect.topRight.y),
                        bottomRight: CGPoint(x: topRect.bottomRight.x, y: 1.0 - topRect.bottomRight.y),
                        bottomLeft: CGPoint(x: topRect.bottomLeft.x, y: 1.0 - topRect.bottomLeft.y),
                        confidence: topRect.confidence
                    )

                    // 平滑插值 (EMA Smoothing)，徹底消除框線跳來跳去的抽搐抖動
                    let smoothed: DetectedDocument
                    if let previous = self.currentSmoothedDoc {
                        smoothed = previous.smoothed(with: rawDoc, alpha: 0.32)
                    } else {
                        smoothed = rawDoc
                    }

                    self.currentSmoothedDoc = smoothed
                    self.lastDetectedTime = now
                    self.onDocumentDetected?(smoothed)

                } else {
                    // 若當前影格短暫未檢測出，在滯後窗口內維持上一幀座標，避免高頻閃爍
                    if let previous = self.currentSmoothedDoc, now - self.lastDetectedTime < self.persistenceWindow {
                        self.onDocumentDetected?(previous)
                    } else {
                        self.currentSmoothedDoc = nil
                        self.onDocumentDetected?(nil)
                    }
                }
            }

            request.maximumObservations = 1
            request.minimumConfidence = 0.45
            request.minimumAspectRatio = 0.2
            request.maximumAspectRatio = 1.0
            request.quadratureTolerance = 25.0

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
