import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit

/// 手指抹除與修補處理器 (對齊 vFlat FingerMask & Inpainter)
/// 自動辨識翻開書本時按壓於邊緣的手指，並以周圍紙張自然底色修補抹除
public final class FingerRemovalProcessor {
    public static let shared = FingerRemovalProcessor()

    private init() {}

    /// 自動偵測並抹除頁面邊緣的手指按壓遮擋
    /// - Parameters:
    ///   - image: 待處理之頁面影像
    ///   - edgeThresholdRatio: 檢測邊緣區域比例 (預設在左右各 18% 及底部 12% 範圍搜尋)
    /// - Returns: 抹除手指後之乾淨影像
    public func removeFingers(image: UIImage, edgeThresholdRatio: CGFloat = 0.18) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 64, height > 64 else { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let base = context.data else { return image }
        let pixelData = base.assumingMemoryBound(to: UInt8.self)

        // 1. 建立手指遮罩 (二值化 Mask: 255 代表手指，0 代表正常紙張或文字)
        var mask = [UInt8](repeating: 0, count: width * height)
        let leftMargin = Int(CGFloat(width) * edgeThresholdRatio)
        let rightMargin = width - leftMargin
        let bottomMargin = height - Int(CGFloat(height) * 0.12)

        var hasFingerDetected = false

        for y in 0..<height {
            let rowOffset = y * width
            let pixelRowOffset = y * bytesPerRow

            // 只在兩側或底邊邊界區域檢測按壓手指
            let isNearBottom = y >= bottomMargin

            for x in 0..<width {
                let isNearSide = (x <= leftMargin || x >= rightMargin)
                guard isNearSide || isNearBottom else { continue }

                let p = pixelRowOffset + x * bytesPerPixel
                let r = Int(pixelData[p])
                let g = Int(pixelData[p + 1])
                let b = Int(pixelData[p + 2])

                // 轉換至 YCbCr 進行強健膚色判定 (避免受不同光照陰影干擾)
                let yVal = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
                let cb = 128.0 - 0.168736 * Double(r) - 0.331264 * Double(g) + 0.5 * Double(b)
                let cr = 128.0 + 0.5 * Double(r) - 0.418688 * Double(g) - 0.081312 * Double(b)

                // 經典膚色區域條件: Cb in [77..127], Cr in [133..173], Y > 45, R > G > B
                if cb >= 75.0 && cb <= 128.0 && cr >= 130.0 && cr <= 175.0 && yVal >= 45.0 && r > g && g > b {
                    mask[rowOffset + x] = 255
                    hasFingerDetected = true
                }
            }
        }

        guard hasFingerDetected else {
            return image // 未檢測到手指，直接回傳原圖
        }

        // 2. 估算乾淨紙張之背景基準色彩 (在中線內側安全區域取樣)
        var sampleR = 0, sampleG = 0, sampleB = 0, sampleCount = 0
        let sampleStartX = width / 4
        let sampleEndX = (width * 3) / 4
        let sampleStartY = height / 4
        let sampleEndY = (height * 3) / 4

        for y in stride(from: sampleStartY, to: sampleEndY, by: 4) {
            let pRow = y * bytesPerRow
            for x in stride(from: sampleStartX, to: sampleEndX, by: 4) {
                let p = pRow + x * bytesPerPixel
                let r = Int(pixelData[p])
                let g = Int(pixelData[p + 1])
                let b = Int(pixelData[p + 2])
                // 排除深色文字筆畫，只取高亮度底色 (灰度 > 180)
                if (r + g + b) / 3 > 180 {
                    sampleR += r
                    sampleG += g
                    sampleB += b
                    sampleCount += 1
                }
            }
        }

        let bgR = sampleCount > 0 ? UInt8(sampleR / sampleCount) : UInt8(250)
        let bgG = sampleCount > 0 ? UInt8(sampleG / sampleCount) : UInt8(250)
        let bgB = sampleCount > 0 ? UInt8(sampleB / sampleCount) : UInt8(248)

        // 3. 執行修補 (Inpainting)：將遮罩範圍平滑替換為周圍底色
        for y in 0..<height {
            let rowOffset = y * width
            let pixelRowOffset = y * bytesPerRow
            for x in 0..<width {
                if mask[rowOffset + x] == 255 {
                    let p = pixelRowOffset + x * bytesPerPixel
                    pixelData[p] = bgR
                    pixelData[p + 1] = bgG
                    pixelData[p + 2] = bgB
                }
            }
        }

        guard let outputCG = context.makeImage() else { return image }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif
