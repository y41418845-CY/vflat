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

    /// 尋找與自身歐幾里得總位移距離最小的角點順序，徹底解決相機晃動時頂點順序對調導致的框線抽搐
    public func reorderedToMatch(_ target: DetectedDocument) -> DetectedDocument {
        let pts = [target.topLeft, target.topRight, target.bottomRight, target.bottomLeft]
        let currentPts = [self.topLeft, self.topRight, self.bottomRight, self.bottomLeft]

        var bestShift = 0
        var minTotalDist: CGFloat = .greatestFiniteMagnitude

        for shift in 0..<4 {
            var dist: CGFloat = 0
            for i in 0..<4 {
                let p1 = currentPts[i]
                let p2 = pts[(i + shift) % 4]
                dist += hypot(p1.x - p2.x, p1.y - p2.y)
            }
            if dist < minTotalDist {
                minTotalDist = dist
                bestShift = shift
            }
        }

        return DetectedDocument(
            topLeft: pts[bestShift % 4],
            topRight: pts[(bestShift + 1) % 4],
            bottomRight: pts[(bestShift + 2) % 4],
            bottomLeft: pts[(bestShift + 3) % 4],
            confidence: target.confidence
        )
    }

    /// 與另一個文件幾何座標進行指數平滑插值 (EMA Smoothing)，並具備極限防抖死區保護
    public func smoothed(with target: DetectedDocument, alpha: CGFloat = 0.3) -> DetectedDocument {
        // 計算四角點總位移量，若極微小 (< 0.012) 視為靜止雜訊，直接忽略更新以保證框線完全不動
        let totalDrift = hypot(topLeft.x - target.topLeft.x, topLeft.y - target.topLeft.y)
                       + hypot(topRight.x - target.topRight.x, topRight.y - target.topRight.y)
                       + hypot(bottomRight.x - target.bottomRight.x, bottomRight.y - target.bottomRight.y)
                       + hypot(bottomLeft.x - target.bottomLeft.x, bottomLeft.y - target.bottomLeft.y)

        if totalDrift < 0.012 {
            return self
        }

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
                   !results.isEmpty {

                    // 計算四邊形在標準化空間中的有效面積
                    func approxArea(_ r: VNRectangleObservation) -> CGFloat {
                        let w1 = hypot(r.topRight.x - r.topLeft.x, r.topRight.y - r.topLeft.y)
                        let w2 = hypot(r.bottomRight.x - r.bottomLeft.x, r.bottomRight.y - r.bottomLeft.y)
                        let h1 = hypot(r.bottomLeft.x - r.topLeft.x, r.bottomLeft.y - r.topLeft.y)
                        let h2 = hypot(r.bottomRight.x - r.topRight.x, r.bottomRight.y - r.topRight.y)
                        return ((w1 + w2) * 0.5) * ((h1 + h2) * 0.5)
                    }

                    // 挑選最大面積的候選矩形（鎖定整體物品或藥盒外框，避免誤鎖局部文字區）
                    if let bestRect = results.max(by: { approxArea($0) < approxArea($1) }),
                       bestRect.confidence >= 0.20 {

                        // Vision 座標轉換為標準 (0,0 左上角)
                        let rawDoc = DetectedDocument(
                            topLeft: CGPoint(x: bestRect.topLeft.x, y: 1.0 - bestRect.topLeft.y),
                            topRight: CGPoint(x: bestRect.topRight.x, y: 1.0 - bestRect.topRight.y),
                            bottomRight: CGPoint(x: bestRect.bottomRight.x, y: 1.0 - bestRect.bottomRight.y),
                            bottomLeft: CGPoint(x: bestRect.bottomLeft.x, y: 1.0 - bestRect.bottomLeft.y),
                            confidence: bestRect.confidence
                        )

                        // 自適應平滑插值 (EMA Smoothing)
                        let smoothed: DetectedDocument
                        if let previous = self.currentSmoothedDoc {
                            // 若新邊框顯著大於舊邊框（發現更完整的外邊界），加速貼合
                            let prevWidth = hypot(previous.topRight.x - previous.topLeft.x, previous.topRight.y - previous.topLeft.y)
                            let prevHeight = hypot(previous.bottomLeft.x - previous.topLeft.x, previous.bottomLeft.y - previous.topLeft.y)
                            let prevArea = prevWidth * prevHeight
                            let newArea = approxArea(bestRect)

                            let alpha: CGFloat = (newArea > prevArea * 1.25) ? 0.75 : 0.35
                            let alignedDoc = previous.reorderedToMatch(rawDoc)
                            smoothed = previous.smoothed(with: alignedDoc, alpha: alpha)
                        } else {
                            smoothed = rawDoc
                        }

                        self.currentSmoothedDoc = smoothed
                        self.lastDetectedTime = now
                        self.onDocumentDetected?(smoothed)
                        return
                    }
                }

                // 若當前影格短暫未檢測出，在滯後窗口內維持上一幀座標，避免高頻閃爍
                if let previous = self.currentSmoothedDoc, now - self.lastDetectedTime < self.persistenceWindow {
                    self.onDocumentDetected?(previous)
                } else {
                    self.currentSmoothedDoc = nil
                    self.onDocumentDetected?(nil)
                }
            }

            // 放寬辨識條件，以捕捉藥盒、不規則長條物與書籍整體輪廓
            request.maximumObservations = 8
            request.minimumConfidence = 0.20
            request.minimumAspectRatio = 0.1
            request.maximumAspectRatio = 1.0
            request.quadratureTolerance = 45.0
            request.minimumSize = 0.1

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
