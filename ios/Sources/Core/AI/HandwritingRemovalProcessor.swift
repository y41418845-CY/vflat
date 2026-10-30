import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit

/// 手寫筆跡消除處理器 (對齊 vFlat HandwritingRemovalPostProcessor)
/// 辨識試卷、課本上的彩色原子筆 (藍筆、紅筆) 與標記筆跡，完整保留黑色印刷字體，一鍵還原空白文件
public final class HandwritingRemovalProcessor {
    public static let shared = HandwritingRemovalProcessor()

    private init() {}

    /// 移除影像中的彩色手寫筆跡 (藍筆、紅筆、螢光標記)
    /// - Parameters:
    ///   - image: 原始掃描影像
    ///   - preserveBlackThreshold: 黑色印刷字保護門檻 (亮度低於此值且色飽和度極低判定為印刷體)
    /// - Returns: 消除手寫筆跡後之乾淨影像
    public func removeHandwriting(image: UIImage, preserveBlackThreshold: Int = 110) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 16, height > 16 else { return image }

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

        // 1. 取樣全圖紙張底色平均值
        var sampleR = 0, sampleG = 0, sampleB = 0, sampleCount = 0
        for y in stride(from: 0, to: height, by: 8) {
            let pRow = y * bytesPerRow
            for x in stride(from: 0, to: width, by: 8) {
                let p = pRow + x * bytesPerPixel
                let r = Int(pixelData[p])
                let g = Int(pixelData[p + 1])
                let b = Int(pixelData[p + 2])
                if (r + g + b) / 3 > 175 {
                    sampleR += r
                    sampleG += g
                    sampleB += b
                    sampleCount += 1
                }
            }
        }

        let paperR = sampleCount > 0 ? UInt8(sampleR / sampleCount) : UInt8(252)
        let paperG = sampleCount > 0 ? UInt8(sampleG / sampleCount) : UInt8(252)
        let paperB = sampleCount > 0 ? UInt8(sampleB / sampleCount) : UInt8(250)

        // 2. 逐像素過濾手寫筆跡
        for y in 0..<height {
            let pRow = y * bytesPerRow
            for x in 0..<width {
                let p = pRow + x * bytesPerPixel
                let r = Int(pixelData[p])
                let g = Int(pixelData[p + 1])
                let b = Int(pixelData[p + 2])

                let maxVal = max(r, max(g, b))
                let minVal = min(r, min(g, b))
                let brightness = (r + g + b) / 3

                // 計算色彩飽和度 (Saturation: 印刷黑字/灰階底色飽和度極低，手寫彩色筆跡飽和度高)
                let delta = maxVal - minVal
                let saturation = maxVal > 0 ? Double(delta) / Double(maxVal) : 0.0

                // 印刷黑字保護：極深黑且無顯著色彩飽和度
                let isBlackPrintText = (brightness < preserveBlackThreshold) && (saturation < 0.18)

                if !isBlackPrintText {
                    // 筆跡特徵 A：藍色原子筆 / 鋼筆 (B 通道明顯高於 R 與 G)
                    let isBluePen = (b > r + 22) && (b > g + 12) && (saturation > 0.16)

                    // 筆跡特徵 B：紅色原子筆 / 批改筆 (R 通道明顯高於 G 與 B)
                    let isRedPen = (r > g + 28) && (r > b + 28) && (saturation > 0.20)

                    // 筆跡特徵 C：彩色螢光標記 (黃/綠/粉高亮度高彩度)
                    let isHighlighter = (brightness > 140) && (saturation > 0.25)

                    if isBluePen || isRedPen || isHighlighter {
                        // 替換為紙張背景色
                        pixelData[p] = paperR
                        pixelData[p + 1] = paperG
                        pixelData[p + 2] = paperB
                    }
                }
            }
        }

        guard let outputCG = context.makeImage() else { return image }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif
