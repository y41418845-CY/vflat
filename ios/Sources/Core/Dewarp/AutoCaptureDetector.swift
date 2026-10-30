import Foundation
import CoreGraphics

/// 對齊 OpenScan 之 AutoCaptureDetector
/// 監控連續相鄰影格的 DetectedDocument 角點位置穩定度
/// 當四角點之座標位移量皆低於容許門檻且持續達指定時間，判定為畫面靜止穩定，觸發自動快門
public final class AutoCaptureDetector {
    /// 判定為靜止的最大容許角點位移率 (正規化座標 0.0 ~ 1.0 間，0.02 代表移動不超過 2%)
    public var positionTolerance: CGFloat = 0.02
    /// 連續穩定觸發所需之最短秒數 (預設 0.5 秒)
    public var requiredStableDuration: TimeInterval = 0.5
    /// 連續穩定影格數要求 (避免單一瞬間誤判)
    public var minStableFrames: Int = 4

    private var previousDocument: DetectedDocument? = nil
    private var firstStableTimestamp: TimeInterval? = nil
    private var stableFrameCount: Int = 0

    /// 即時穩定進度 (0.0 ~ 1.0)，可用於畫面中心環狀進度條動畫
    public private(set) var stabilityProgress: Double = 0.0

    public init(positionTolerance: CGFloat = 0.02, requiredStableDuration: TimeInterval = 0.5) {
        self.positionTolerance = positionTolerance
        self.requiredStableDuration = requiredStableDuration
    }

    /// 重設偵測器狀態
    public func reset() {
        previousDocument = nil
        firstStableTimestamp = nil
        stableFrameCount = 0
        stabilityProgress = 0.0
    }

    /// 傳入新影格的偵測結果，評估是否應觸發拍照
    /// - Parameters:
    ///   - currentDocument: 當前幀的文件四邊形
    ///   - now: 當前時間戳
    /// - Returns: 若文件已完全穩定並達到觸發標準，回傳 true
    public func processFrame(document currentDocument: DetectedDocument?, at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let current = currentDocument else {
            reset()
            return false
        }

        guard let prev = previousDocument else {
            previousDocument = current
            firstStableTimestamp = now
            stableFrameCount = 1
            stabilityProgress = 0.1
            return false
        }

        // 計算四個角點的最大位移量
        let dTL = distance(current.topLeft, prev.topLeft)
        let dTR = distance(current.topRight, prev.topRight)
        let dBR = distance(current.bottomRight, prev.bottomRight)
        let dBL = distance(current.bottomLeft, prev.bottomLeft)
        let maxDelta = max(dTL, max(dTR, max(dBR, dBL)))

        previousDocument = current

        if maxDelta <= positionTolerance {
            // 維持在穩定容許範圍內
            stableFrameCount += 1
            if firstStableTimestamp == nil {
                firstStableTimestamp = now
            }
            let elapsed = now - (firstStableTimestamp ?? now)
            stabilityProgress = min(1.0, elapsed / requiredStableDuration)

            if stableFrameCount >= minStableFrames && elapsed >= requiredStableDuration {
                // 達成穩定快門觸發條件，重設避免重覆觸發
                reset()
                return true
            }
        } else {
            // 位移過大 (手震或移動取景)，重置計時器但平滑衰減進度
            firstStableTimestamp = now
            stableFrameCount = 0
            stabilityProgress = 0.0
        }

        return false
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}
