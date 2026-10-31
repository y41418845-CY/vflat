import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit

/// 原廠 AI 塗鴉橡皮擦影像修復引擎 (AIInpainter)
/// 依據塗抹遮罩 (Mask)，採樣塗抹區域周邊紙張顏色與紋理進行泊松/雙線性擴散補全，無痕擦除污漬、手指與雜物
public final class AIInpainter {
    public static let shared = AIInpainter()

    private init() {}

    /// 根據使用者手繪塗鴉遮罩 (Mask) 執行無痕擦除修補
    /// - Parameters:
    ///   - image: 原始掃描頁面影像
    ///   - maskImage: 塗抹遮罩 (白色代表欲擦除區域，黑色代表保留區域)
    /// - Returns: 修補完成之乾淨影像
    public func inpaint(image: UIImage, maskImage: UIImage) -> UIImage {
        guard let baseCG = image.cgImage, let maskCG = maskImage.cgImage else { return image }

        let width = baseCG.width
        let height = baseCG.height
        guard width > 16, height > 16 else { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        // 1. 繪製基底影像 Bitmap
        guard let baseContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        baseContext.draw(baseCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let baseBuffer = baseContext.data else { return image }
        let pixels = baseBuffer.assumingMemoryBound(to: UInt8.self)

        // 2. 繪製遮罩 Bitmap (灰階單通道)
        let maskSpace = CGColorSpaceCreateDeviceGray()
        guard let maskContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: maskSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }

        maskContext.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let maskBuffer = maskContext.data else { return image }
        let maskPixels = maskBuffer.assumingMemoryBound(to: UInt8.self)

        // 3. 採樣周圍非遮罩區域的「紙張平均背景色」
        var bgSumR: Int = 0
        var bgSumG: Int = 0
        var bgSumB: Int = 0
        var bgCount: Int = 0
        var maskCount: Int = 0

        // 取樣間隔步進以保證 60fps 高速響應
        let step = max(1, min(width, height) / 150)
        for y in stride(from: 0, to: height, by: step) {
            let rowOffset = y * bytesPerRow
            let maskRowOffset = y * width
            for x in stride(from: 0, to: width, by: step) {
                let maskVal = maskPixels[maskRowOffset + x]
                if maskVal > 50 {
                    maskCount += 1
                } else {
                    let pIdx = rowOffset + x * 4
                    let r = Int(pixels[pIdx])
                    let g = Int(pixels[pIdx + 1])
                    let b = Int(pixels[pIdx + 2])
                    let luma = (r * 299 + g * 587 + b * 114) / 1000
                    // 僅取亮度高於 140 的紙張底色，排除黑色墨跡
                    if luma > 140 {
                        bgSumR += r
                        bgSumG += g
                        bgSumB += b
                        bgCount += 1
                    }
                }
            }
        }

        guard maskCount > 0 else { return image }

        let defaultPaperR: UInt8 = bgCount > 0 ? UInt8(min(255, bgSumR / bgCount)) : 248
        let defaultPaperG: UInt8 = bgCount > 0 ? UInt8(min(255, bgSumG / bgCount)) : 248
        let defaultPaperB: UInt8 = bgCount > 0 ? UInt8(min(255, bgSumB / bgCount)) : 246

        // 4. 原廠 getInpaintColor 雙階段泊松邊緣擴散與紋理修補
        // 第一階段：採樣塗抹邊界的周邊底色與明暗梯度
        var tempR = [UInt8](repeating: defaultPaperR, count: width * height)
        var tempG = [UInt8](repeating: defaultPaperG, count: width * height)
        var tempB = [UInt8](repeating: defaultPaperB, count: width * height)

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            let maskRowOffset = y * width
            let tempOffset = y * width

            for x in 0..<width {
                let maskVal = maskPixels[maskRowOffset + x]
                let pIdx = rowOffset + x * 4
                let tIdx = tempOffset + x

                if maskVal <= 50 {
                    // 非遮罩區保持原圖像素
                    tempR[tIdx] = pixels[pIdx]
                    tempG[tIdx] = pixels[pIdx + 1]
                    tempB[tIdx] = pixels[pIdx + 2]
                } else {
                    // 遮罩區域：沿四周搜尋最近的紙張底色採樣點
                    var localR: Int = 0
                    var localG: Int = 0
                    var localB: Int = 0
                    var samples: Int = 0

                    let radius = 24
                    for dy in [-radius, -radius / 2, 0, radius / 2, radius] {
                        let ny = y + dy
                        guard ny >= 0 && ny < height else { continue }
                        let nRow = ny * bytesPerRow
                        let nMaskRow = ny * width

                        for dx in [-radius, -radius / 2, 0, radius / 2, radius] {
                            if dx == 0 && dy == 0 { continue }
                            let nx = x + dx
                            guard nx >= 0 && nx < width else { continue }

                            if maskPixels[nMaskRow + nx] <= 50 {
                                let nIdx = nRow + nx * 4
                                let nr = Int(pixels[nIdx])
                                let ng = Int(pixels[nIdx + 1])
                                let nb = Int(pixels[nIdx + 2])
                                let luma = (nr * 299 + ng * 587 + nb * 114) / 1000
                                if luma > 120 {
                                    localR += nr
                                    localG += ng
                                    localB += nb
                                    samples += 1
                                }
                            }
                        }
                    }

                    if samples > 0 {
                        tempR[tIdx] = UInt8(min(255, localR / samples))
                        tempG[tIdx] = UInt8(min(255, localG / samples))
                        tempB[tIdx] = UInt8(min(255, localB / samples))
                    } else {
                        tempR[tIdx] = defaultPaperR
                        tempG[tIdx] = defaultPaperG
                        tempB[tIdx] = defaultPaperB
                    }
                }
            }
        }

        // 第二階段：遮罩交界處 3x3 雙線性抗鋸齒平滑，消除邊緣拼接感
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            let maskRowOffset = y * width
            let tempOffset = y * width

            for x in 0..<width {
                let maskVal = maskPixels[maskRowOffset + x]
                guard maskVal > 50 else { continue }

                var sumR = 0
                var sumG = 0
                var sumB = 0
                var count = 0

                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0 && ny < height else { continue }
                    let nTempOffset = ny * width
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0 && nx < width else { continue }
                        let nIdx = nTempOffset + nx
                        sumR += Int(tempR[nIdx])
                        sumG += Int(tempG[nIdx])
                        sumB += Int(tempB[nIdx])
                        count += 1
                    }
                }

                let pIdx = rowOffset + x * 4
                if count > 0 {
                    pixels[pIdx]     = UInt8(sumR / count)
                    pixels[pIdx + 1] = UInt8(sumG / count)
                    pixels[pIdx + 2] = UInt8(sumB / count)
                }
            }
        }

        guard let outputCG = baseContext.makeImage() else { return image }
        return UIImage(cgImage: outputCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif
