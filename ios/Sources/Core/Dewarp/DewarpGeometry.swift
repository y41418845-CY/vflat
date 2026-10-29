import Foundation
import simd

/// 25x25 自由曲面展平之幾何數學運算引擎
/// 完整實作原版 vFlat libnative-scan.so 中之 freeform::model::calcOutputSize 演算法
public final class DewarpGeometry {
    /// 網格行數 (Rows)
    public static let rowCount: Int = 25
    /// 網格列數 (Columns)
    public static let colCount: Int = 25
    /// 總網格節點數 (Total Control Points)
    public static let totalPoints: Int = rowCount * colCount // 625 個控制點

    public struct OutputSize: Equatable {
        public let width: Int
        public let height: Int
        public let aspectRatio: Float

        public init(width: Int, height: Int, aspectRatio: Float) {
            self.width = width
            self.height = height
            self.aspectRatio = aspectRatio
        }
    }

    /// 根據 25x25 幾何網格點與頁面長寬比純量，計算物理展平後之輸出長寬尺寸
    /// - Parameters:
    ///   - points: 長度為 625 的 SIMD2<Float> 陣列，對應 25x25 網格上的歸一化座標 (0.0 .. 1.0)
    ///   - inputWidth: 原始相機影像寬度（像素）
    ///   - aspectRatio: 頁面幾何長寬比純量 (Height / Width)
    /// - Returns: 展開後的目標輸出尺寸 (寬度, 高度)
    public static func calculateOutputSize(
        points: [SIMD2<Float>],
        inputWidth: Int,
        aspectRatio: Float
    ) -> OutputSize {
        guard points.count == totalPoints else {
            return OutputSize(width: 0, height: 0, aspectRatio: 0)
        }
        guard aspectRatio > 0.0 else {
            return OutputSize(width: 0, height: 0, aspectRatio: 0)
        }

        // 限制長寬比合法邊界 (對應原生 0x1c0ec - 0x1c104 浮點邊界處理)
        let clampedAspect = max(min(aspectRatio, 10.0), 0.1)

        var totalArcLengthSum: Float = 0.0

        // 對 25 條橫向曲線分別進行微分弧長積分
        for row in 0..<rowCount {
            let rowOffset = row * colCount
            var rowArcLength: Float = 0.0

            // 逐段累加相鄰控制點之間的歐幾里得距離：\sum \sqrt{\Delta x^2 + \Delta y^2}
            for col in 0..<(colCount - 1) {
                let p1 = points[rowOffset + col]
                let p2 = points[rowOffset + col + 1]
                let segmentDistance = simd_distance(p1, p2)
                rowArcLength += segmentDistance
            }

            totalArcLengthSum += rowArcLength
        }

        // 取 25 行曲線展開長度之平均值 (對應原生 fdiv s1, s1, #25.0)
        let averageArcLength = totalArcLengthSum / Float(rowCount)

        // 避免異常過度伸展 (限制在合理展開比例內)
        guard averageArcLength < 2.0 else {
            return OutputSize(width: 0, height: 0, aspectRatio: 0)
        }

        let outputWidthFloat = averageArcLength * Float(inputWidth)
        let outputHeightFloat = outputWidthFloat * clampedAspect

        let outWidth = Int(outputWidthFloat)
        let outHeight = Int(outputHeightFloat)

        return OutputSize(width: outWidth, height: outHeight, aspectRatio: clampedAspect)
    }

    /// 產生用於 POC 階段之平整標準網格 (25x25 均勻分布)
    public static func makeFlatGrid() -> [SIMD2<Float>] {
        var grid = [SIMD2<Float>]()
        grid.reserveCapacity(totalPoints)

        for row in 0..<rowCount {
            let y = Float(row) / Float(rowCount - 1)
            for col in 0..<colCount {
                let x = Float(col) / Float(colCount - 1)
                grid.append(SIMD2<Float>(x, y))
            }
        }

        return grid
    }

    /// 產生用於 POC 測試之模擬彎曲書頁網格 (正弦拋物線曲面)
    /// - Parameter curvature: 彎曲幅度 (0.0: 完全平坦, 0.2: 顯著書頁彎曲)
    public static func makeCurvedGrid(curvature: Float = 0.2) -> [SIMD2<Float>] {
        var grid = [SIMD2<Float>]()
        grid.reserveCapacity(totalPoints)

        for row in 0..<rowCount {
            let y = Float(row) / Float(rowCount - 1)
            for col in 0..<colCount {
                let normX = Float(col) / Float(colCount - 1)
                // 模擬書頁在 Y 軸方向的正弦隆起與中縫弧度
                let curveOffset = sin(normX * Float.pi) * curvature
                let distortedX = normX
                let distortedY = y + curveOffset * 0.5
                grid.append(SIMD2<Float>(distortedX, distortedY))
            }
        }

        return grid
    }

    /// 網格輸出座標反混淆 (還原置換索引)
    /// 依據原版 freeform::model::deobfuscate 原理將打散的張量還原為標準 25x25 拓撲網格
    public static func deobfuscate(shuffledPoints: [SIMD2<Float>], permutationTable: [Int]?) -> [SIMD2<Float>] {
        guard let table = permutationTable, table.count == shuffledPoints.count else {
            return shuffledPoints
        }

        var restored = Array(repeating: SIMD2<Float>(0, 0), count: shuffledPoints.count)
        for i in 0..<shuffledPoints.count {
            let originalIndex = table[i]
            if originalIndex >= 0 && originalIndex < restored.count {
                restored[originalIndex] = shuffledPoints[i]
            }
        }

        return restored
    }
}
