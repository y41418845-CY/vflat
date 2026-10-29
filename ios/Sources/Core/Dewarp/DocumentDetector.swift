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

/// 候選四邊形內部幾何分析器：包含對邊比例、凸性、中央權重與垂直融合能力
struct CandidateQuad {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    var confidence: Float

    var topLen: CGFloat { hypot(topRight.x - topLeft.x, topRight.y - topLeft.y) }
    var botLen: CGFloat { hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y) }
    var leftLen: CGFloat { hypot(bottomLeft.x - topLeft.x, bottomLeft.y - topLeft.y) }
    var rightLen: CGFloat { hypot(bottomRight.x - topRight.x, bottomRight.y - topRight.y) }

    var area: CGFloat {
        ((topLen + botLen) * 0.5) * ((leftLen + rightLen) * 0.5)
    }

    var center: CGPoint {
        CGPoint(
            x: (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) * 0.25,
            y: (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) * 0.25
        )
    }

    /// 幾何對稱性檢查：對邊長度比率與凸多邊形驗證
    var isValidGeometry: Bool {
        let maxHoriz = max(topLen, botLen)
        let minHoriz = max(min(topLen, botLen), 0.0001)
        let horizRatio = maxHoriz / minHoriz

        let maxVert = max(leftLen, rightLen)
        let minVert = max(min(leftLen, rightLen), 0.0001)
        let vertRatio = maxVert / minVert

        // 嚴格限制對邊長度比例不可超過 1.35 (防範斜向陰影與畸變假梯形)
        if horizRatio > 1.35 || vertRatio > 1.35 {
            return false
        }

        // 檢查凸多邊形性 (所有相鄰外積同號)
        func crossProduct(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
            return (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
        }
        let cp1 = crossProduct(topLeft, topRight, bottomRight)
        let cp2 = crossProduct(topRight, bottomRight, bottomLeft)
        let cp3 = crossProduct(bottomRight, bottomLeft, topLeft)
        let cp4 = crossProduct(bottomLeft, topLeft, topRight)

        let allPositive = cp1 > 0 && cp2 > 0 && cp3 > 0 && cp4 > 0
        let allNegative = cp1 < 0 && cp2 < 0 && cp3 < 0 && cp4 < 0
        if !(allPositive || allNegative) {
            return false
        }

        // 面積合理範圍 (佔畫面 2% 到 90%)
        let a = area
        if a < 0.02 || a > 0.90 {
            return false
        }

        return true
    }

    /// 綜合評分：結合置信度、對稱度、中央權重
    var score: Float {
        let maxHoriz = Float(max(topLen, botLen))
        let minHoriz = Float(max(min(topLen, botLen), 0.0001))
        let horizDiff = (maxHoriz / minHoriz) - 1.0

        let maxVert = Float(max(leftLen, rightLen))
        let minVert = Float(max(min(leftLen, rightLen), 0.0001))
        let vertDiff = (maxVert / minVert) - 1.0

        let parallelismScore = max(1.0 - (horizDiff + vertDiff) * 0.8, 0.0)

        // 距離畫面中央越近，分數越高 (中央權重避免抓到邊緣桌面雜訊)
        let distToCenter = Float(hypot(center.x - 0.5, center.y - 0.5))
        let centerScore = max(1.0 - distToCenter * 1.5, 0.0)

        // 面積合理性獎勵 (以 0.05 ~ 0.70 最佳)
        let areaFloat = Float(area)
        let areaScore = (areaFloat >= 0.05 && areaFloat <= 0.70) ? Float(1.0) : Float(0.5)

        return (confidence * 3.0) + (parallelismScore * 2.5) + (centerScore * 2.0) + (areaScore * 1.0)
    }

    /// 垂直重疊融合：若兩四邊形 X 軸重疊度高且垂直相鄰，融合為包含兩者之完整四邊形
    static func tryMergeVertically(_ a: CandidateQuad, _ b: CandidateQuad) -> CandidateQuad? {
        let minX_a = min(a.topLeft.x, a.bottomLeft.x)
        let maxX_a = max(a.topRight.x, a.bottomRight.x)
        let minX_b = min(b.topLeft.x, b.bottomLeft.x)
        let maxX_b = max(b.topRight.x, b.bottomRight.x)

        let overlapX = max(0.0, min(maxX_a, maxX_b) - max(minX_a, minX_b))
        let unionX = max(maxX_a, maxX_b) - min(minX_a, minX_b)
        guard unionX > 0, (overlapX / unionX) > 0.65 else { return nil }

        let topA = min(a.topLeft.y, a.topRight.y)
        let botA = max(a.bottomLeft.y, a.bottomRight.y)
        let topB = min(b.topLeft.y, b.topRight.y)
        let botB = max(b.bottomLeft.y, b.bottomRight.y)

        // 垂直間距不可過遠
        let verticalGap = max(0.0, max(topA, topB) - min(botA, botB))
        guard verticalGap < 0.08 else { return nil }

        let mergedTL = CGPoint(x: min(a.topLeft.x, b.topLeft.x), y: min(a.topLeft.y, b.topLeft.y))
        let mergedTR = CGPoint(x: max(a.topRight.x, b.topRight.x), y: min(a.topRight.y, b.topRight.y))
        let mergedBR = CGPoint(x: max(a.bottomRight.x, b.bottomRight.x), y: max(a.bottomRight.y, b.bottomRight.y))
        let mergedBL = CGPoint(x: min(a.bottomLeft.x, b.bottomLeft.x), y: max(a.bottomLeft.y, b.bottomLeft.y))

        let candidate = CandidateQuad(
            topLeft: mergedTL,
            topRight: mergedTR,
            bottomRight: mergedBR,
            bottomLeft: mergedBL,
            confidence: max(a.confidence, b.confidence)
        )
        return candidate.isValidGeometry ? candidate : nil
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

            // 雙引擎檢測管線：
            // 主引擎 (Primary)：Apple 官方深度學習語意分割神經網絡 (VNDetectDocumentSegmentationRequest)
            // 備援引擎 (Fallback)：高嚴格度幾何約束矩形檢測器 (VNDetectRectanglesRequest)
            var neuralCandidate: CandidateQuad? = nil
            var fallbackCandidates: [CandidateQuad] = []

            let docSegRequest = VNDetectDocumentSegmentationRequest { req, error in
                if error == nil,
                   let results = req.results as? [VNRectangleObservation],
                   let best = results.first {
                    let quad = CandidateQuad(
                        topLeft: CGPoint(x: best.topLeft.x, y: 1.0 - best.topLeft.y),
                        topRight: CGPoint(x: best.topRight.x, y: 1.0 - best.topRight.y),
                        bottomRight: CGPoint(x: best.bottomRight.x, y: 1.0 - best.bottomRight.y),
                        bottomLeft: CGPoint(x: best.bottomLeft.x, y: 1.0 - best.bottomLeft.y),
                        confidence: best.confidence
                    )
                    if quad.isValidGeometry {
                        neuralCandidate = quad
                    }
                }
            }

            let rectRequest = VNDetectRectanglesRequest { req, error in
                if error == nil,
                   let results = req.results as? [VNRectangleObservation],
                   !results.isEmpty {
                    fallbackCandidates = results.map { r in
                        CandidateQuad(
                            topLeft: CGPoint(x: r.topLeft.x, y: 1.0 - r.topLeft.y),
                            topRight: CGPoint(x: r.topRight.x, y: 1.0 - r.topRight.y),
                            bottomRight: CGPoint(x: r.bottomRight.x, y: 1.0 - r.bottomRight.y),
                            bottomLeft: CGPoint(x: r.bottomLeft.x, y: 1.0 - r.bottomLeft.y),
                            confidence: r.confidence
                        )
                    }.filter { $0.isValidGeometry }
                }
            }
            rectRequest.maximumObservations = 5
            rectRequest.minimumConfidence = 0.40
            rectRequest.minimumAspectRatio = 0.15
            rectRequest.maximumAspectRatio = 1.0
            rectRequest.quadratureTolerance = 18.0
            rectRequest.minimumSize = 0.08

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([docSegRequest, rectRequest])
            } catch {
                self.isProcessing = false
                self.onDocumentDetected?(nil)
                return
            }

            self.isProcessing = false
            let now = CACurrentMediaTime()

            // 1. 優先採用神經網絡語意分割輸出
            var selectedQuad: CandidateQuad? = neuralCandidate

            // 2. 若神經網絡未命中，採用垂直融合備援幾何輸出
            if selectedQuad == nil && !fallbackCandidates.isEmpty {
                let n = fallbackCandidates.count
                var mergedList = fallbackCandidates
                if n >= 2 {
                    for i in 0..<n {
                        for j in (i + 1)..<n {
                            if let merged = CandidateQuad.tryMergeVertically(fallbackCandidates[i], fallbackCandidates[j]) {
                                mergedList.append(merged)
                            }
                        }
                    }
                }
                selectedQuad = mergedList.max(by: { $0.score < $1.score })
            }

            // 3. 套用角點最小位移對齊與自適應 EMA 平滑
            if let best = selectedQuad {
                let rawDoc = DetectedDocument(
                    topLeft: best.topLeft,
                    topRight: best.topRight,
                    bottomRight: best.bottomRight,
                    bottomLeft: best.bottomLeft,
                    confidence: best.confidence
                )

                let smoothed: DetectedDocument
                if let previous = self.currentSmoothedDoc {
                    let aligned = previous.reorderedToMatch(rawDoc)
                    smoothed = previous.smoothed(with: aligned, alpha: 0.35)
                } else {
                    smoothed = rawDoc
                }

                self.currentSmoothedDoc = smoothed
                self.lastDetectedTime = now
                self.onDocumentDetected?(smoothed)
            } else {
                // 滯後窗口平滑，避免相機晃動短暫掉幀產生頻閃
                if let previous = self.currentSmoothedDoc, now - self.lastDetectedTime < self.persistenceWindow {
                    self.onDocumentDetected?(previous)
                } else {
                    self.currentSmoothedDoc = nil
                    self.onDocumentDetected?(nil)
                }
            }
        }
    }
}
