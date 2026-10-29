import Foundation
import simd

/// 供 Swift 與 Metal 綁定之頂點資料模型
public struct DewarpVertexData {
    public var position: SIMD2<Float>  // NDC 螢幕座標 (-1.0 .. 1.0)
    public var texCoord: SIMD2<Float>  // 紋理座標 (0.0 .. 1.0)

    public init(position: SIMD2<Float>, texCoord: SIMD2<Float>) {
        self.position = position
        self.texCoord = texCoord
    }
}

/// 負責為 Metal 渲染管線建立 25x25 拓撲網格頂點緩衝與三角形索引緩衝
public final class DewarpMesh {
    public let rows: Int
    public let cols: Int

    public init(rows: Int = DewarpGeometry.rowCount, cols: Int = DewarpGeometry.colCount) {
        self.rows = rows
        self.cols = cols
    }

    /// 根據 25x25 控制點產生 Metal 頂點資料陣列
    /// - Parameter curvedPoints: 相機紋理上的彎曲點座標 (0.0 .. 1.0)
    /// - Returns: 一一映射到 NDC 螢幕空間的頂點陣列
    public func generateVertices(from curvedPoints: [SIMD2<Float>]) -> [DewarpVertexData] {
        var vertices = [DewarpVertexData]()
        vertices.reserveCapacity(rows * cols)

        for row in 0..<rows {
            // 平整目標 NDC 座標 Y: 頂部 1.0 到 底部 -1.0
            let ndcY = 1.0 - (Float(row) / Float(rows - 1)) * 2.0

            for col in 0..<cols {
                // 平整目標 NDC 座標 X: 左側 -1.0 到 右側 1.0
                let ndcX = (Float(col) / Float(cols - 1)) * 2.0 - 1.0

                let idx = row * cols + col
                let uv = idx < curvedPoints.count ? curvedPoints[idx] : SIMD2<Float>(Float(col) / Float(cols - 1), Float(row) / Float(rows - 1))

                vertices.append(
                    DewarpVertexData(
                        position: SIMD2<Float>(ndcX, ndcY),
                        texCoord: uv
                    )
                )
            }
        }

        return vertices
    }

    /// 產生 24x24 格子的三角形索引列表 (每個格子 2 個三角形，共 6 個頂點索引)
    public func generateIndices() -> [UInt32] {
        var indices = [UInt32]()
        let numCells = (rows - 1) * (cols - 1)
        indices.reserveCapacity(numCells * 6)

        for row in 0..<(rows - 1) {
            for col in 0..<(cols - 1) {
                let topLeft = UInt32(row * cols + col)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((row + 1) * cols + col)
                let bottomRight = bottomLeft + 1

                // 三角形 1: TopLeft -> BottomLeft -> TopRight
                indices.append(topLeft)
                indices.append(bottomLeft)
                indices.append(topRight)

                // 三角形 2: TopRight -> BottomLeft -> BottomRight
                indices.append(topRight)
                indices.append(bottomLeft)
                indices.append(bottomRight)
            }
        }

        return indices
    }
}
