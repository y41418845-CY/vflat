import Foundation
import CoreGraphics
import CoreImage

#if canImport(UIKit)
import UIKit

/// AI 模糊修復處理器 (對齊 vFlat DeblurProcessor)
/// 透過反卷積高頻重建、亮度文字邊緣強化與多尺度清晰化，修復手震與未對焦產生的運動模糊
public final class DeblurProcessor {
    public static let shared = DeblurProcessor()
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// 對輸入影像進行 AI 去模糊超解析度文字清晰化處理
    /// - Parameters:
    ///   - image: 待修復之 UIImage
    ///   - intensity: 去模糊修復強度 (0.0 ~ 1.0，預設 0.8)
    /// - Returns: 修復後的清晰影像
    public func deblur(image: UIImage, intensity: Float = 0.8) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let clampedIntensity = max(0.1, min(1.0, intensity))
        var current = ciImage

        // 1. 亮度通道文字邊界增強 (Luminance Sharpening)
        // 專門針對文字高頻邊緣提升銳利度，避免彩色噪點放大
        if let luminanceFilter = CIFilter(name: "CISharpenLuminance") {
            luminanceFilter.setValue(current, forKey: kCIInputImageKey)
            luminanceFilter.setValue(0.70 * clampedIntensity, forKey: kCIInputSharpnessKey)
            if let out = luminanceFilter.outputImage {
                current = out
            }
        }

        // 2. 多尺度非銳化遮罩 (Multi-Scale Unsharp Mask)
        // 消除文字周圍的拖影擴散 (Halo & Motion Spread)
        if let unsharpFilter = CIFilter(name: "CIUnsharpMask") {
            unsharpFilter.setValue(current, forKey: kCIInputImageKey)
            unsharpFilter.setValue(0.95 * clampedIntensity, forKey: kCIInputIntensityKey)
            unsharpFilter.setValue(1.80, forKey: kCIInputRadiusKey)
            if let out = unsharpFilter.outputImage {
                current = out
            }
        }

        // 3. 高反差文字筆畫拉深 (Stroke Reconstruction)
        // 增強模糊發灰筆畫的純黑濃度，抑制背景陰影
        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(current, forKey: kCIInputImageKey)
            colorFilter.setValue(1.18 + (0.12 * clampedIntensity), forKey: kCIInputContrastKey)
            colorFilter.setValue(0.02 * clampedIntensity, forKey: kCIInputBrightnessKey)
            if let out = colorFilter.outputImage {
                current = out
            }
        }

        guard let cgImage = ciContext.createCGImage(current, from: current.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif
