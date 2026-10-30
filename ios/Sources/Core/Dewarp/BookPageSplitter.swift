import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit

/// 雙頁分割結果
public struct SplitBookPages {
    public let leftPage: UIImage
    public let rightPage: UIImage

    public init(leftPage: UIImage, rightPage: UIImage) {
        self.leftPage = leftPage
        self.rightPage = rightPage
    }

    /// 根據閱讀順序取得有序頁面列表 (leftToRight 為 true 代表由左至右閱讀，false 則右頁在前)
    public func orderedPages(leftToRight: Bool = true) -> [UIImage] {
        return leftToRight ? [leftPage, rightPage] : [rightPage, leftPage]
    }
}

/// 負責在拍攝跨頁書本時，自動沿書籍中縫 (Book Spine/Crease) 偵測並分割為兩頁獨立文件
public final class BookPageSplitter {
    public static let shared = BookPageSplitter()

    private init() {}

    /// 沿中縫精確分割跨頁圖像為左右兩頁
    /// - Parameters:
    ///   - image: 拍下之跨頁書籍影像 (通常為 4:3 或 16:9 橫向展開)
    ///   - splitRatio: 中縫 X 軸相對比例 (預設 0.50，中線)
    ///   - spineMarginRatio: 中縫裝訂裝線微調裁除比率 (0.015 代表中縫各向左右裁除 1.5% 避免陰影或裝訂線殘留)
    /// - Returns: 分割完成之左右兩頁獨立圖片
    public func splitPage(
        image: UIImage,
        splitRatio: CGFloat = 0.50,
        spineMarginRatio: CGFloat = 0.012
    ) -> SplitBookPages? {
        guard let cgImage = image.cgImage else { return nil }

        let fullWidth = CGFloat(cgImage.width)
        let fullHeight = CGFloat(cgImage.height)

        // 計算中縫切線像素位置
        let splitX = fullWidth * max(0.2, min(0.8, splitRatio))
        let marginPixels = fullWidth * spineMarginRatio

        // 1. 左頁裁剪範圍 (從 0 到 splitX - margin)
        let leftWidth = max(1.0, splitX - marginPixels)
        let leftRect = CGRect(x: 0, y: 0, width: leftWidth, height: fullHeight)

        // 2. 右頁裁剪範圍 (從 splitX + margin 到 fullWidth)
        let rightX = splitX + marginPixels
        let rightWidth = max(1.0, fullWidth - rightX)
        let rightRect = CGRect(x: rightX, y: 0, width: rightWidth, height: fullHeight)

        guard let leftCG = cgImage.cropping(to: leftRect),
              let rightCG = cgImage.cropping(to: rightRect) else {
            return nil
        }

        let leftImg = UIImage(cgImage: leftCG, scale: image.scale, orientation: image.imageOrientation)
        let rightImg = UIImage(cgImage: rightCG, scale: image.scale, orientation: image.imageOrientation)

        return SplitBookPages(leftPage: leftImg, rightPage: rightImg)
    }

    /// 分析圖像像素灰度，智慧定位書本中縫 (縱向暗線/凹陷陰影之最小光度位置)
    /// - Parameter image: 待分析影像
    /// - Returns: 偵測到的中縫 X 軸比例 (若對比不明顯則預設回傳 0.50)
    public func detectSpineRatio(image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0.50 }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 200, height > 200 else { return 0.50 }

        // 在中央 40% ~ 60% 區間進行像素抽樣，尋找垂直平均灰度之局部極小值 (最暗的中縫溝槽)
        let minCol = Int(Double(width) * 0.42)
        let maxCol = Int(Double(width) * 0.58)

        // 建立微縮點陣圖加速分析
        let sampleHeight = 100
        let sampleWidth = width
        let bytesPerRow = sampleWidth
        var grayData = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)

        guard let context = CGContext(
            data: &grayData,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0.50
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var minIntensitySum = Int.max
        var bestCol = width / 2

        for col in minCol...maxCol {
            var colSum = 0
            for row in 0..<sampleHeight {
                colSum += Int(grayData[row * sampleWidth + col])
            }
            if colSum < minIntensitySum {
                minIntensitySum = colSum
                bestCol = col
            }
        }

        return CGFloat(bestCol) / CGFloat(width)
    }
}
#endif
