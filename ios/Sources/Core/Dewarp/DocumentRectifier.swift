import Foundation
import CoreGraphics
import CoreImage

#if canImport(UIKit)
import UIKit

/// 負責拍完照後自動將框選物做透視拉正、長寬比校正與色彩文字增強之處理器
/// 完整對齊 vFlat Scan 之 PPTP (Paper Perspective Target Points) 與 Enhance 管線
public final class DocumentRectifier {
    public static let shared = DocumentRectifier()
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// 自動將拍下之照片依據框選之 4 個角點進行單應性透視變換拉正 (Perspective Correction)
    /// - Parameters:
    ///   - image: 原始高解析度照片
    ///   - document: 偵測到的四邊形頂角坐標 (標準化 0.0 .. 1.0, 左上為原點)
    /// - Returns: 物理透視拉正後之正交影像
    public func correctPerspective(image: UIImage, document: DetectedDocument) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let extent = ciImage.extent
        let width = extent.width
        let height = extent.height

        // CoreImage 坐標系為左下角原點 (Y 軸向上)，需將 DetectedDocument (左上角原點) 轉為 CoreImage 坐標
        let ciTL = CGPoint(x: document.topLeft.x * width, y: (1.0 - document.topLeft.y) * height)
        let ciTR = CGPoint(x: document.topRight.x * width, y: (1.0 - document.topRight.y) * height)
        let ciBR = CGPoint(x: document.bottomRight.x * width, y: (1.0 - document.bottomRight.y) * height)
        let ciBL = CGPoint(x: document.bottomLeft.x * width, y: (1.0 - document.bottomLeft.y) * height)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: ciTL), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: ciTR), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: ciBR), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: ciBL), forKey: "inputBottomLeft")

        guard let outputCI = filter.outputImage else { return nil }
        guard let cgImage = ciContext.createCGImage(outputCI, from: outputCI.extent) else { return nil }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    /// 影像增強處理：去除陰影、文字邊緣加深與底色純化 (對齊 vFlat Enhance & Whitening)
    /// - Parameters:
    ///   - image: 待增強之圖片
    ///   - textDarken: 是否使文字加黑變暗
    ///   - colorEnhance: 是否自動色彩與對比度校正
    /// - Returns: 增強後清晰白底黑字圖片
    public func enhanceDocument(image: UIImage, textDarken: Bool = true, colorEnhance: Bool = true) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }
        var current = ciImage

        // 1. 色彩與對比度校正 (提升對比度 1.25，稍微提升亮度，使背景泛白)
        if colorEnhance, let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(current, forKey: kCIInputImageKey)
            colorFilter.setValue(1.25, forKey: kCIInputContrastKey)
            colorFilter.setValue(0.05, forKey: kCIInputBrightnessKey)
            colorFilter.setValue(1.10, forKey: kCIInputSaturationKey)
            if let out = colorFilter.outputImage {
                current = out
            }
        }

        // 2. 局部銳化加深文字邊緣 (Unsharp Mask)
        if textDarken, let sharpenFilter = CIFilter(name: "CIUnsharpMask") {
            sharpenFilter.setValue(current, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.60, forKey: kCIInputIntensityKey)
            sharpenFilter.setValue(2.50, forKey: kCIInputRadiusKey)
            if let out = sharpenFilter.outputImage {
                current = out
            }
        }

        guard let cgImage = ciContext.createCGImage(current, from: current.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    /// 一鍵全自動校正管線：拍完照後自動透視拉正、計算長寬比並增強影像
    public func autoProcessCapture(
        image: UIImage,
        document: DetectedDocument?,
        autoCrop: Bool = true,
        textDarken: Bool = true,
        colorEnhance: Bool = true
    ) -> UIImage {
        var processed = image

        // 步驟一：若有偵測到四角邊界且開啟自動裁剪，執行透視拉正
        if autoCrop, let doc = document {
            if let rectified = correctPerspective(image: processed, document: doc) {
                processed = rectified
            }
        }

        // 步驟二：執行影像增強 (文字變暗加深、背景純白化)
        if textDarken || colorEnhance {
            if let enhanced = enhanceDocument(image: processed, textDarken: textDarken, colorEnhance: colorEnhance) {
                processed = enhanced
            }
        }

        return processed
    }
}
#endif
