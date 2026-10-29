import XCTest
import simd
@testable import vFlatCore

final class DewarpGeometryTests: XCTestCase {

    /// 測試 1：驗證平整平面網格之計算長寬比與尺寸
    func testFlatGridCalculation() {
        let flatGrid = DewarpGeometry.makeFlatGrid()
        XCTAssertEqual(flatGrid.count, DewarpGeometry.totalPoints, "網格點總數必須為 625")

        let inputWidth = 1000
        let targetAspect: Float = 1.414 // A4 紙張長寬比

        let result = DewarpGeometry.calculateOutputSize(
            points: flatGrid,
            inputWidth: inputWidth,
            aspectRatio: targetAspect
        )

        // 平整網格之平均橫向展開長度應接近 1.0
        XCTAssertEqual(result.width, 1000, accuracy: 2, "平整網格展開寬度應等同輸入寬度")
        XCTAssertEqual(result.height, 1414, accuracy: 5, "高度應符合長寬比換算")
    }

    /// 測試 2：驗證彎曲書頁網格微分弧長展開之物理特性
    func testCurvedGridArcLengthExceedsFlat() {
        let curvedGrid = DewarpGeometry.makeCurvedGrid(curvature: 0.2)
        let inputWidth = 1000
        let targetAspect: Float = 1.414

        let result = DewarpGeometry.calculateOutputSize(
            points: curvedGrid,
            inputWidth: inputWidth,
            aspectRatio: targetAspect
        )

        // 彎曲弧面經過微分弧長積分展開後，物理寬度必大於投影寬度 (1000)
        XCTAssertGreaterThan(result.width, 1000, "彎曲曲線展開後之物理弧長必須大於投影寬度")
        XCTAssertEqual(Float(result.height) / Float(result.width), targetAspect, accuracy: 0.05)
    }

    /// 測試 3：驗證三角形索引與頂點生成數量
    func testMeshGenerationCounts() {
        let mesh = DewarpMesh(rows: 25, cols: 25)
        let flatGrid = DewarpGeometry.makeFlatGrid()

        let vertices = mesh.generateVertices(from: flatGrid)
        let indices = mesh.generateIndices()

        XCTAssertEqual(vertices.count, 625, "頂點數必須為 25x25 = 625")
        // 24x24 格子 * 2 個三角形 * 3 個頂點 = 3,456 個索引
        XCTAssertEqual(indices.count, 24 * 24 * 6, "索引數量必須精確對應三角形數量")
    }
}
