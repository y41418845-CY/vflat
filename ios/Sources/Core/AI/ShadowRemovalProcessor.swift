import Foundation
import CoreImage

#if canImport(UIKit)
import UIKit

/// 負責消除手機拍攝時所產生的投影陰影（例如手機本體、頭部或光線不均勻造成的暗色區塊）
/// 透過背景照度場（Illumination Field）估算與 Retinex 反射率重構，將紙張底色無損平滑提亮至一致純白
public final class ShadowRemovalProcessor: @unchecked Sendable {
    public static let shared = ShadowRemovalProcessor()

    private let ciContext: CIContext

    private init() {
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])
    }

    /// 對影像執行環境光照均勻化與手機陰影消除
    /// - Parameters:
    ///   - image: 原始拍下之文件影像
    ///   - shadowIntensity: 陰影提亮強度 (0.0 .. 1.0，預設 0.75)
    /// - Returns: 消除陰影後均勻光照之影像
    public func removeShadow(image: UIImage, shadowIntensity: Float = 0.75) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        // 1. 取得大尺度的低頻背景照度估算圖 (Illumination Map)
        // 模糊半徑根據圖像解析度動態計算（約取寬度之 4%～6%），確保文字高頻細節被濾除，僅保留低頻光照
        let maxDim = max(ciImage.extent.width, ciImage.extent.height)
        let blurRadius = max(24.0, maxDim * 0.04)

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)

        guard let illuminationMap = blurFilter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        // 2. 利用色彩分割與分段動態範圍提亮陰影 (Retinex 概念)
        // 透過 CIColorControls 增強對比，並利用 CIDivideBlendMode (I / L) 實現反射率重建
        guard let divideFilter = CIFilter(name: "CIDivideBlendMode") else { return nil }
        divideFilter.setValue(ciImage, forKey: kCIInputImageKey)
        divideFilter.setValue(illuminationMap, forKey: kCIInputBackgroundImageKey)

        guard let reflectionMap = divideFilter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        // 3. 調整色階與白平衡，保護文字對比度
        guard let toneFilter = CIFilter(name: "CIHighlightShadowAdjust") else {
            return render(ciImage: reflectionMap, orientation: image.imageOrientation)
        }
        toneFilter.setValue(reflectionMap, forKey: kCIInputImageKey)
        toneFilter.setValue(0.35, forKey: "inputShadowAmount")
        toneFilter.setValue(0.95, forKey: "inputHighlightAmount")

        // 4. 文字邊緣與暗部細節加深保護
        guard let finalAdjust = toneFilter.outputImage?.cropped(to: ciImage.extent),
              let colorControls = CIFilter(name: "CIColorControls") else {
            return render(ciImage: reflectionMap, orientation: image.imageOrientation)
        }
        colorControls.setValue(finalAdjust, forKey: kCIInputImageKey)
        colorControls.setValue(1.15, forKey: kCIInputContrastKey) // 微調對比
        colorControls.setValue(0.02, forKey: kCIInputBrightnessKey)

        guard let resultCI = colorControls.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }

        return render(ciImage: resultCI, orientation: image.imageOrientation)
    }

    private func render(ciImage: CIImage, orientation: UIImage.Orientation) -> UIImage? {
        guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
    }
}
#endif
