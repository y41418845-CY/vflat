import Foundation
import CoreVideo
import CoreImage
import Vision
import CoreGraphics
import QuartzCore

#if canImport(UIKit)
import UIKit
#endif

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

        // 限制對邊長度比例，防範斜向陰影與畸變假梯形
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

        // 面積合理範圍 (佔畫面 1.5% 到 95%)
        let a = area
        if a < 0.015 || a > 0.95 {
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

    /// 沿四邊形軸向法向量自適應向外延伸，精準貼合物體實體硬外框，解決模型僅框住內部印刷文字的內縮問題
    func expandedToPhysicalBounds(marginRatioX: CGFloat = 0.05, marginRatioY: CGFloat = 0.08) -> CandidateQuad {
        let w = (topLen + botLen) * 0.5
        let h = (leftLen + rightLen) * 0.5

        let expandX = w * marginRatioX
        let expandY = h * marginRatioY

        let dxTop = (topRight.x - topLeft.x) / max(topLen, 0.001)
        let dyTop = (topRight.y - topLeft.y) / max(topLen, 0.001)

        let dxLeft = (bottomLeft.x - topLeft.x) / max(leftLen, 0.001)
        let dyLeft = (bottomLeft.y - topLeft.y) / max(leftLen, 0.001)

        let newTL = CGPoint(
            x: max(0.0, min(1.0, topLeft.x - dxTop * expandX - dxLeft * expandY)),
            y: max(0.0, min(1.0, topLeft.y - dyTop * expandX - dyLeft * expandY))
        )
        let newTR = CGPoint(
            x: max(0.0, min(1.0, topRight.x + dxTop * expandX - dxLeft * expandY)),
            y: max(0.0, min(1.0, topRight.y + dyTop * expandX - dyLeft * expandY))
        )
        let newBR = CGPoint(
            x: max(0.0, min(1.0, bottomRight.x + dxTop * expandX + dxLeft * expandY)),
            y: max(0.0, min(1.0, bottomRight.y + dyTop * expandX + dyLeft * expandY))
        )
        let newBL = CGPoint(
            x: max(0.0, min(1.0, bottomLeft.x - dxTop * expandX + dxLeft * expandY)),
            y: max(0.0, min(1.0, bottomLeft.y - dyTop * expandX + dyLeft * expandY))
        )

        return CandidateQuad(
            topLeft: newTL,
            topRight: newTR,
            bottomRight: newBR,
            bottomLeft: newBL,
            confidence: self.confidence
        )
    }
}

/// 透過 Apple Vision 框架在相機串流中即時偵測文件/矩形邊界，並具備 EMA 平滑防抖與防閃爍延遲
public final class DocumentDetector {
    // MARK: - 可調參數

    /// 送進 Vision 的推論工作解析度 (寬度)。以縮圖推論可大幅降低 ANE/CPU 負載，座標仍為正規化故不影響精度
    public static let inferenceWidth: CGFloat = 720.0
    /// 即時預覽偵測頻率上限
    public var detectionFrameRate: Double = 15.0
    /// 條碼偵測頻率上限 (獨立節流，避免每幀都跑全符號集)
    public var barcodeFrameRate: Double = 4.0
    /// 邊界物理外擴比例 (貼膜級微調)
    public var marginRatioX: CGFloat = 0.01
    public var marginRatioY: CGFloat = 0.015

    // MARK: - 內部狀態 (僅在 detectionQueue 上存取)

    private let detectionQueue = DispatchQueue(label: "com.vflat.ios.detector", qos: .userInteractive)
    private var isProcessing = false
    private var lastProcessTime: TimeInterval = 0
    private var lastBarcodeRunTime: TimeInterval = 0

    // 平滑濾波狀態
    private var currentSmoothedDoc: DetectedDocument? = nil
    private var lastDetectedTime: TimeInterval = 0
    private let persistenceWindow: TimeInterval = 0.35 // 350ms 滯後窗口，防止短暫掉幀產生劇烈閃爍

    private var lastBarcodePayload: String? = nil
    /// 最後一次「實際掃到條碼」的時間 (用於 2.5 秒殘留；與掃描節流分開)
    private var lastBarcodeSeenTime: TimeInterval = 0

    public var onDocumentDetected: ((DetectedDocument?) -> Void)?
    public var onBarcodeDetected: ((DetectedBarcode?) -> Void)?

    /// CIContext 為執行緒安全，供串流縮圖與單張偵測共用
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public init() {}

    // MARK: - 串流即時偵測

    /// 傳入相機影格 (CVPixelBuffer) 進行非同步文件邊緣分析
    /// 所有可變狀態皆在 detectionQueue 上讀寫，避免跨執行緒資料競爭
    public func processFrame(_ pixelBuffer: CVPixelBuffer) {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isProcessing else { return }

            let now = CACurrentMediaTime()
            guard now - self.lastProcessTime >= (1.0 / max(self.detectionFrameRate, 1.0)) else { return }

            self.isProcessing = true
            self.lastProcessTime = now
            defer { self.isProcessing = false }

            autoreleasepool {
                self.runStreamDetection(pixelBuffer: pixelBuffer, now: now)
            }
        }
    }

    private func runStreamDetection(pixelBuffer: CVPixelBuffer, now: TimeInterval) {
        guard let inferenceImage = DocumentDetector.makeInferenceImage(from: pixelBuffer) else {
            onDocumentDetected?(nil)
            return
        }

        // 條碼獨立節流：只有達到頻率才把條碼請求加入同一次 Vision 批次
        let shouldRunBarcode = now - lastBarcodeRunTime >= (1.0 / max(barcodeFrameRate, 1.0))
        if shouldRunBarcode {
            lastBarcodeRunTime = now
        }
        let analysis = DocumentDetector.analyze(image: inferenceImage, includeBarcode: shouldRunBarcode)

        // 1. 條碼結果 (含 2.5 秒殘留，避免 UI 膠囊閃爍)
        if let bc = analysis.barcode {
            lastBarcodePayload = bc.payloadString
            lastBarcodeSeenTime = now
            onBarcodeDetected?(bc)
        } else if now - lastBarcodeSeenTime < 2.5, let lastPayload = lastBarcodePayload {
            onBarcodeDetected?(DetectedBarcode(payloadString: lastPayload, symbology: "QR/Barcode"))
        } else {
            lastBarcodePayload = nil
            onBarcodeDetected?(nil)
        }

        // 2. 文件邊界 (主引擎：語意分割；備援：幾何矩形 + 垂直融合)
        var selectedQuad: CandidateQuad? = analysis.neural
        if selectedQuad == nil, !analysis.fallbackCandidates.isEmpty {
            selectedQuad = DocumentDetector.selectBest(from: analysis.fallbackCandidates)
        }

        if let best = selectedQuad {
            let physical = best.expandedToPhysicalBounds(marginRatioX: marginRatioX, marginRatioY: marginRatioY)
            let rawDoc = DetectedDocument(
                topLeft: physical.topLeft,
                topRight: physical.topRight,
                bottomRight: physical.bottomRight,
                bottomLeft: physical.bottomLeft,
                confidence: physical.confidence
            )

            let smoothed: DetectedDocument
            if let previous = currentSmoothedDoc {
                let aligned = previous.reorderedToMatch(rawDoc)
                smoothed = previous.smoothed(with: aligned, alpha: 0.35)
            } else {
                smoothed = rawDoc
            }

            currentSmoothedDoc = smoothed
            lastDetectedTime = now
            onDocumentDetected?(smoothed)
        } else {
            // 滯後窗口平滑，避免相機晃動短暫掉幀產生頻閃
            if let previous = currentSmoothedDoc, now - lastDetectedTime < persistenceWindow {
                onDocumentDetected?(previous)
            } else {
                currentSmoothedDoc = nil
                onDocumentDetected?(nil)
            }
        }
    }

    /// 重設平滑狀態 (切換相機或重新進入掃描頁時呼叫)
    public func reset() {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentSmoothedDoc = nil
            self.lastDetectedTime = 0
            self.lastProcessTime = 0
            self.lastBarcodePayload = nil
            self.lastBarcodeRunTime = 0
            self.lastBarcodeSeenTime = 0
        }
    }

    // MARK: - 單張瞬時偵測 (拍照當下取最新角點)

    /// 對指定影格執行一次「無平滑、無滯後」的邊界偵測。
    /// 拍照時使用同一張影格重新偵測，可避免 EMA 平滑與 350ms 滯後造成的裁切錯位。
    public static func detectOnce(
        in pixelBuffer: CVPixelBuffer,
        marginRatioX: CGFloat = 0.01,
        marginRatioY: CGFloat = 0.015
    ) -> DetectedDocument? {
        guard let inferenceImage = makeInferenceImage(from: pixelBuffer) else { return nil }
        return detectOnce(in: inferenceImage, marginRatioX: marginRatioX, marginRatioY: marginRatioY)
    }

    #if canImport(UIKit)
    /// 對相簿匯入的 UIImage 執行單次邊界偵測（用於匯入時自動裁切）
    public static func detectOnce(
        in image: UIImage,
        marginRatioX: CGFloat = 0.01,
        marginRatioY: CGFloat = 0.015
    ) -> DetectedDocument? {
        guard let cgImage = image.cgImage else { return nil }
        return detectOnce(in: cgImage, marginRatioX: marginRatioX, marginRatioY: marginRatioY)
    }
    #endif

    /// 對任意 CGImage 執行單次邊界偵測（內部會降採樣至推論解析度）
    public static func detectOnce(
        in image: CGImage,
        marginRatioX: CGFloat = 0.01,
        marginRatioY: CGFloat = 0.015
    ) -> DetectedDocument? {
        let ciImage = CIImage(cgImage: image)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1.0, inferenceWidth / extent.width)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let inferenceImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }

        let analysis = analyze(image: inferenceImage, includeBarcode: false)

        var selected = analysis.neural
        if selected == nil, !analysis.fallbackCandidates.isEmpty {
            selected = selectBest(from: analysis.fallbackCandidates)
        }
        guard let best = selected else { return nil }
        let physical = best.expandedToPhysicalBounds(marginRatioX: marginRatioX, marginRatioY: marginRatioY)
        return DetectedDocument(
            topLeft: physical.topLeft,
            topRight: physical.topRight,
            bottomRight: physical.bottomRight,
            bottomLeft: physical.bottomLeft,
            confidence: physical.confidence
        )
    }

    // MARK: - Vision 推論

    struct AnalysisResult {
        var neural: CandidateQuad?
        var fallbackCandidates: [CandidateQuad]
        var barcode: DetectedBarcode?
    }

    /// 建立降採樣後的推論影像 (僅影響推論成本，正規化座標不需回映射)
    static func makeInferenceImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1.0, inferenceWidth / extent.width)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    static func analyze(image: CGImage, includeBarcode: Bool) -> AnalysisResult {
        var neural: CandidateQuad? = nil
        var fallbackCandidates: [CandidateQuad] = []
        var barcode: DetectedBarcode? = nil

        let docSegRequest = VNDetectDocumentSegmentationRequest { req, error in
            guard error == nil,
                  let results = req.results as? [VNRectangleObservation],
                  let best = results.first else { return }
            let quad = CandidateQuad(
                topLeft: CGPoint(x: best.topLeft.x, y: 1.0 - best.topLeft.y),
                topRight: CGPoint(x: best.topRight.x, y: 1.0 - best.topRight.y),
                bottomRight: CGPoint(x: best.bottomRight.x, y: 1.0 - best.bottomRight.y),
                bottomLeft: CGPoint(x: best.bottomLeft.x, y: 1.0 - best.bottomLeft.y),
                confidence: best.confidence
            )
            if quad.isValidGeometry {
                neural = quad
            }
        }

        let rectRequest = VNDetectRectanglesRequest { req, error in
            guard error == nil,
                  let results = req.results as? [VNRectangleObservation],
                  !results.isEmpty else { return }
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
        rectRequest.maximumObservations = 5
        rectRequest.minimumConfidence = 0.40
        rectRequest.minimumAspectRatio = 0.15
        rectRequest.maximumAspectRatio = 1.0
        rectRequest.quadratureTolerance = 18.0
        rectRequest.minimumSize = 0.08

        var requests: [VNRequest] = [docSegRequest, rectRequest]

        if includeBarcode {
            // 限定常見符號集，避免全符號掃描造成不必要的 CPU 負擔
            let request = VNDetectBarcodesRequest { req, error in
                guard error == nil,
                      let results = req.results as? [VNBarcodeObservation],
                      let first = results.first,
                      let payload = first.payloadStringValue,
                      !payload.isEmpty else { return }
                barcode = DetectedBarcode(
                    payloadString: payload,
                    symbology: first.symbology.rawValue,
                    boundingBox: first.boundingBox
                )
            }
            request.symbologies = [.qr, .aztec, .pdf417, .dataMatrix, .ean13, .ean8, .upce, .code39, .code93, .code128, .itf14]
            requests.append(request)
        }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try? handler.perform(requests)

        return AnalysisResult(
            neural: neural,
            fallbackCandidates: fallbackCandidates,
            barcode: barcode
        )
    }

    /// 備援候選評分 + 垂直融合
    static func selectBest(from candidates: [CandidateQuad]) -> CandidateQuad? {
        guard !candidates.isEmpty else { return nil }
        var mergedList = candidates
        if candidates.count >= 2 {
            for i in 0..<candidates.count {
                for j in (i + 1)..<candidates.count {
                    if let merged = CandidateQuad.tryMergeVertically(candidates[i], candidates[j]) {
                        mergedList.append(merged)
                    }
                }
            }
        }
        return mergedList.max(by: { $0.score < $1.score })
    }
}
