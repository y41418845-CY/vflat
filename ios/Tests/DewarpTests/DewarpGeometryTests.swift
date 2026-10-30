import XCTest
import simd
import CoreGraphics

#if canImport(vFlat)
@testable import vFlat
#else
@testable import vFlatCore
#endif

final class DewarpGeometryTests: XCTestCase {

    // MARK: - 幾何尺寸

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

    /// 測試 4：輸出尺寸在極端網格下仍為正數且長寬比合理
    func testOutputSizeStaysPositiveForDegenerateGrid() {
        var degenerate = [SIMD2<Float>](repeating: SIMD2<Float>(0.5, 0.5), count: DewarpGeometry.totalPoints)
        degenerate[0] = SIMD2<Float>(0.0, 0.0)

        let result = DewarpGeometry.calculateOutputSize(
            points: degenerate,
            inputWidth: 100,
            aspectRatio: 1.0
        )

        XCTAssertGreaterThanOrEqual(result.width, 0)
        XCTAssertGreaterThanOrEqual(result.height, 0)
        XCTAssertFalse(result.aspectRatio.isNaN, "退化網格不可產生 NaN 長寬比")
    }

    // MARK: - 反混淆

    /// 測試 5：置換表為 nil 時應原樣回傳
    func testDeobfuscateWithoutTableReturnsInput() {
        let grid = DewarpGeometry.makeFlatGrid()
        let restored = DewarpGeometry.deobfuscate(shuffledPoints: grid, permutationTable: nil)
        XCTAssertEqual(restored, grid)
    }

    /// 測試 6：提供合法置換表時應還原回原始順序
    func testDeobfuscateRestoresOriginalOrder() {
        let original = DewarpGeometry.makeFlatGrid()
        // 建立一個已知的洗牌：把第 i 點搬到 (i + 17) % 625 的位置
        let count = original.count
        let shift = 17
        var shuffled = [SIMD2<Float>](repeating: SIMD2<Float>(0, 0), count: count)
        var permutation = [Int](repeating: 0, count: count)
        for i in 0..<count {
            let target = (i + shift) % count
            shuffled[target] = original[i]
            permutation[target] = i
        }

        let restored = DewarpGeometry.deobfuscate(shuffledPoints: shuffled, permutationTable: permutation)
        XCTAssertEqual(restored, original, "反混淆後必須逐點等於原始網格")
    }

    /// 測試 7：置換表長度不符時不應越界，直接回傳輸入
    func testDeobfuscateIgnoresMalformedTable() {
        let grid = DewarpGeometry.makeFlatGrid()
        let restored = DewarpGeometry.deobfuscate(shuffledPoints: grid, permutationTable: [0, 1, 2])
        XCTAssertEqual(restored, grid)
    }

    // MARK: - 條碼模型

    /// 測試 8：`DetectedBarcode` 的相等性不可受每次新建的 `id` 影響
    func testDetectedBarcodeEqualityIgnoresID() {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let a = DetectedBarcode(payloadString: "https://example.com", symbology: "QR", boundingBox: box, timestamp: 1)
        let b = DetectedBarcode(payloadString: "https://example.com", symbology: "QR", boundingBox: box, timestamp: 1)

        XCTAssertNotEqual(a.id, b.id, "兩個實例的 id 應各自獨立")
        XCTAssertEqual(a, b, "內容相同時必須判定相等，否則 SwiftUI 會每幀重繪")
    }

    /// 測試 9：URL 判斷與圖標選擇
    func testDetectedBarcodeURLDetection() {
        let urlBarcode = DetectedBarcode(payloadString: "https://example.com/path", symbology: "QR")
        XCTAssertTrue(urlBarcode.isURL)
        XCTAssertEqual(urlBarcode.iconName, "link")

        let plainBarcode = DetectedBarcode(payloadString: "4712345678909", symbology: "EAN13")
        XCTAssertFalse(plainBarcode.isURL)
        XCTAssertEqual(plainBarcode.iconName, "barcode")
    }

    // MARK: - 自動快門穩定度

    /// 測試 10：連續穩定影格應在達到時間門檻後觸發一次，且只觸發一次
    func testAutoCaptureDetectorTriggersOnStableFrames() {
        let detector = AutoCaptureDetector(positionTolerance: 0.01, requiredStableDuration: 0.3)
        detector.minStableFrames = 3

        let doc = makeDocument(offset: 0)
        XCTAssertFalse(detector.processFrame(document: doc, at: 0.0))
        XCTAssertFalse(detector.processFrame(document: doc, at: 0.12))
        XCTAssertFalse(detector.processFrame(document: doc, at: 0.24))
        XCTAssertTrue(detector.processFrame(document: doc, at: 0.36), "達到穩定時間門檻應觸發快門")

        // 觸發後狀態被重設，下一幀不應再次觸發
        XCTAssertFalse(detector.processFrame(document: doc, at: 0.40))
    }

    /// 測試 11：角點位移過大時必須重置進度且不觸發
    func testAutoCaptureDetectorResetsOnMovement() {
        let detector = AutoCaptureDetector(positionTolerance: 0.005, requiredStableDuration: 0.2)

        XCTAssertFalse(detector.processFrame(document: makeDocument(offset: 0), at: 0.0))
        XCTAssertFalse(detector.processFrame(document: makeDocument(offset: 0), at: 0.1))
        XCTAssertFalse(detector.processFrame(document: makeDocument(offset: 0.2), at: 0.2))
        XCTAssertEqual(detector.stabilityProgress, 0.0, accuracy: 0.0001, "位移超標應重置穩定進度")
    }

    /// 測試 12：畫面中沒有文件時應重置
    func testAutoCaptureDetectorResetsOnNilDocument() {
        let detector = AutoCaptureDetector()
        _ = detector.processFrame(document: makeDocument(offset: 0), at: 0.0)
        XCTAssertFalse(detector.processFrame(document: nil, at: 0.5))
        XCTAssertEqual(detector.stabilityProgress, 0.0, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func makeDocument(offset: CGFloat) -> DetectedDocument {
        DetectedDocument(
            topLeft: CGPoint(x: 0.1 + offset, y: 0.1 + offset),
            topRight: CGPoint(x: 0.9 + offset, y: 0.1 + offset),
            bottomRight: CGPoint(x: 0.9 + offset, y: 0.9 + offset),
            bottomLeft: CGPoint(x: 0.1 + offset, y: 0.9 + offset),
            confidence: 0.9
        )
    }
}
