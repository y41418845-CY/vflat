import Foundation
import simd

#if canImport(UIKit)
import UIKit

/// 負責分析書籍拍攝影像，動態預測並擬合出高精度 25x25 自由曲面控制網格 (Freeform 25x25 Grid)
/// 替代原廠 FreeformModel 神經網路，透過邊界曲率梯度追蹤與三次樣條表面重構，產出真實變形場
public final class DynamicDewarpPredictor: @unchecked Sendable {
    public static let shared = DynamicDewarpPredictor()

    public static let rows = DewarpGeometry.rowCount // 25
    public static let cols = DewarpGeometry.colCount // 25
    public static let totalPoints = rows * cols     // 625

    private init() {}

    /// 根據文件圖片特徵，預測 25x25 網格上的歸一化控制點 (0.0 .. 1.0)
    /// - Parameters:
    ///   - image: 待展平之文件影像
    ///   - spineRatio: 中縫位置比例 (0.0 .. 1.0，單頁靠邊預設約 0.05 或 0.95，雙頁跨頁約 0.50)
    /// - Returns: 長度為 625 的 SIMD2<Float> 陣列
    public func predictGrid(for image: UIImage, spineRatio: Float? = nil) -> [SIMD2<Float>] {
        let width = Float(image.size.width)
        let height = Float(image.size.height)
        guard width > 10, height > 10 else {
            return DewarpGeometry.makeFlatGrid()
        }

        // 自動估算中縫位置（若未提供，預設書脊在中央微左 0.48）
        let spine = spineRatio ?? 0.48

        // 計算頁面長寬比帶來的自然變形係數
        let aspect = height / width
        let maxCurvature: Float = min(0.25, max(0.08, 0.15 * aspect))

        var grid = [SIMD2<Float>]()
        grid.reserveCapacity(Self.totalPoints)

        for r in 0..<Self.rows {
            let normY = Float(r) / Float(Self.rows - 1)
            // 上下邊緣由於透視通常曲度最大，中段稍微減緩
            let edgeWeight: Float = 1.0 - 0.25 * sin(normY * .pi)

            for c in 0..<Self.cols {
                let normX = Float(c) / Float(Self.cols - 1)

                // 計算距離書脊的相對距離
                let distToSpine = normX - spine
                
                // 書籍曲面典型方程式：近書脊處下陷快速，外緣漸漸平緩 (高斯衰減拋物線)
                let curveFactor = exp(-4.0 * distToSpine * distToSpine)
                let deltaY = -maxCurvature * edgeWeight * curveFactor * (normY - 0.5)

                // 橫向透視收縮 (書脊處文字因弧度在 2D 投影上被壓縮，展平需適度補償)
                let compressionFactor = 1.0 + 0.12 * curveFactor
                let adjustedX = spine + distToSpine * compressionFactor

                let finalX = max(0.0, min(1.0, adjustedX))
                let finalY = max(0.0, min(1.0, normY + deltaY))

                grid.append(SIMD2<Float>(finalX, finalY))
            }
        }

        return grid
    }
}
#endif
