import Foundation
import CoreGraphics
import CoreImage

#if canImport(UIKit)
import UIKit

/// 對齊 OpenScan 6 大專用文件濾鏡模式
public enum DocumentFilterMode: String, CaseIterable, Identifiable {
    case original = "原圖"
    case auto = "智慧增強"
    case lighten = "去暗角"
    case grayscale = "黑白灰階"
    case blackAndWhite = "清晰二值"
    case whiteboard = "白板模式"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .original: return "photo"
        case .auto: return "wand.and.stars"
        case .lighten: return "sun.max"
        case .grayscale: return "circle.lefthalf.filled"
        case .blackAndWhite: return "doc.text.fill"
        case .whiteboard: return "rectangle.fill.on.rectangle.fill"
        }
    }
}

/// 負責在拍照後自動將框選物件透視拉平、切除背景與套用文件專用增強濾鏡
public final class DocumentRectifier {
    public static let shared = DocumentRectifier()
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// 自動將拍下之照片依據框選之 4 個角點進行透視拉平 (Perspective Correction)
    public func correctPerspective(image: UIImage, document: DetectedDocument) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let extent = ciImage.extent
        let width = extent.width
        let height = extent.height

        // CoreImage 坐標系原點在左下角 (Y 軸朝上)，需將 DetectedDocument (左上為原點) 轉換為 CoreImage 坐標
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

    /// 套用 6 大文件專用濾鏡模式 (完全相容 OpenScan)
    public func applyFilter(_ mode: DocumentFilterMode, to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        var current = ciImage

        switch mode {
        case .original:
            return image

        case .auto:
            // 智慧自動色彩平衡與銳化
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(current, forKey: kCIInputImageKey)
                colorFilter.setValue(1.25, forKey: kCIInputContrastKey)
                colorFilter.setValue(0.04, forKey: kCIInputBrightnessKey)
                colorFilter.setValue(1.10, forKey: kCIInputSaturationKey)
                if let out = colorFilter.outputImage { current = out }
            }
            if let sharpen = CIFilter(name: "CIUnsharpMask") {
                sharpen.setValue(current, forKey: kCIInputImageKey)
                sharpen.setValue(0.65, forKey: kCIInputIntensityKey)
                sharpen.setValue(2.50, forKey: kCIInputRadiusKey)
                if let out = sharpen.outputImage { current = out }
            }

        case .lighten:
            // 去除四周暗角與陰影，提升文件均勻度
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(current, forKey: kCIInputImageKey)
                colorFilter.setValue(1.15, forKey: kCIInputContrastKey)
                colorFilter.setValue(0.12, forKey: kCIInputBrightnessKey)
                colorFilter.setValue(0.95, forKey: kCIInputSaturationKey)
                if let out = colorFilter.outputImage { current = out }
            }

        case .grayscale:
            // 標準文件黑白灰階
            if let noir = CIFilter(name: "CIPhotoEffectNoir") {
                noir.setValue(current, forKey: kCIInputImageKey)
                if let out = noir.outputImage { current = out }
            }

        case .blackAndWhite:
            // 高反差清晰二值化 (字體極深黑、紙張純白化)
            if let noir = CIFilter(name: "CIPhotoEffectNoir") {
                noir.setValue(current, forKey: kCIInputImageKey)
                if let out = noir.outputImage { current = out }
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(current, forKey: kCIInputImageKey)
                controls.setValue(2.2, forKey: kCIInputContrastKey)
                controls.setValue(0.18, forKey: kCIInputBrightnessKey)
                if let out = controls.outputImage { current = out }
            }

        case .whiteboard:
            // 白板模式：提升色彩飽和度與背景漂白
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(current, forKey: kCIInputImageKey)
                controls.setValue(1.4, forKey: kCIInputContrastKey)
                controls.setValue(0.15, forKey: kCIInputBrightnessKey)
                controls.setValue(1.3, forKey: kCIInputSaturationKey)
                if let out = controls.outputImage { current = out }
            }
            if let sharpen = CIFilter(name: "CIUnsharpMask") {
                sharpen.setValue(current, forKey: kCIInputImageKey)
                sharpen.setValue(0.8, forKey: kCIInputIntensityKey)
                sharpen.setValue(3.0, forKey: kCIInputRadiusKey)
                if let out = sharpen.outputImage { current = out }
            }
        }

        guard let cgImage = ciContext.createCGImage(current, from: current.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    /// 一鍵自動校正管線：拍完照後自動透視拉平並套用指定濾鏡
    public func autoProcessCapture(
        image: UIImage,
        document: DetectedDocument?,
        autoCrop: Bool = true,
        filterMode: DocumentFilterMode = .auto
    ) -> UIImage {
        var processed = image

        if autoCrop, let doc = document {
            if let rectified = correctPerspective(image: processed, document: doc) {
                processed = rectified
            }
        }

        return applyFilter(filterMode, to: processed)
    }
}
#endif
