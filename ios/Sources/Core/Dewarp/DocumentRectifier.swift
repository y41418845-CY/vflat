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
/// `CIContext` 本身是執行緒安全的，且此類別沒有可變狀態，可安全跨執行緒共用。
public final class DocumentRectifier: @unchecked Sendable {
    public static let shared = DocumentRectifier()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// 自動將拍下之照片依據框選之 4 個角點進行透視拉平 (Perspective Correction)
    public func correctPerspective(image: UIImage, document: DetectedDocument) -> UIImage? {
        let normalized = Self.normalizedImage(image)
        guard let ciImage = CIImage(image: normalized) else { return nil }

        let extent = ciImage.extent
        let width = extent.width
        let height = extent.height
        guard width > 1, height > 1 else { return nil }

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

        guard let outputCI = filter.outputImage,
              outputCI.extent.width >= 1,
              outputCI.extent.height >= 1,
              let cgImage = ciContext.createCGImage(outputCI, from: outputCI.extent) else { return nil }

        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    /// 套用 6 大文件專用濾鏡模式 (完全相容 OpenScan)
    /// - Parameters:
    ///   - mode: 濾鏡模式
    ///   - image: 來源影像
    ///   - enhanceColor: 是否額外做色彩飽和度與白平衡微調（對應「智慧色彩校正」設定）
    ///   - darkenText: 是否額外壓暗中間調讓文字更清晰（對應「使文本變暗」設定）
    public func applyFilter(
        _ mode: DocumentFilterMode,
        to image: UIImage,
        enhanceColor: Bool = true,
        darkenText: Bool = true
    ) -> UIImage {
        let normalized = Self.normalizedImage(image)
        guard let ciImage = CIImage(image: normalized) else { return image }

        var current = ciImage

        // 前置：色彩校正（灰階/二值模式本身已去色，不需再調飽和度）
        if enhanceColor, mode != .grayscale, mode != .blackAndWhite {
            if let color = CIFilter(name: "CIColorControls") {
                color.setValue(current, forKey: kCIInputImageKey)
                color.setValue(1.06, forKey: kCIInputSaturationKey)
                color.setValue(0.015, forKey: kCIInputBrightnessKey)
                color.setValue(1.02, forKey: kCIInputContrastKey)
                if let out = color.outputImage { current = out }
            }
        }

        switch mode {
        case .original:
            break

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

        // 後置：文字變暗（Gamma > 1 會壓暗中間調、保留亮部紙張）
        if darkenText, mode != .grayscale, mode != .blackAndWhite {
            if let gamma = CIFilter(name: "CIGammaAdjust") {
                gamma.setValue(current, forKey: kCIInputImageKey)
                gamma.setValue(1.12, forKey: "inputPower")
                if let out = gamma.outputImage { current = out }
            }
        }

        guard let cgImage = ciContext.createCGImage(current, from: current.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }

    /// 幾何階段：只做方向正規化與透視裁切，不套濾鏡。
    /// 保留這張「已裁切、未上色」的影像，後續切換濾鏡或重新裁切都能重複利用，不必重拍。
    public func geometryCorrected(
        image: UIImage,
        document: DetectedDocument?,
        autoCrop: Bool
    ) -> UIImage {
        let normalized = Self.normalizedImage(image)
        guard autoCrop, let document = document else { return normalized }
        return correctPerspective(image: normalized, document: document) ?? normalized
    }

    /// 一鍵自動校正管線：透視拉平 → 選用 25x25 自由曲面 GPU 展平 → 套用指定濾鏡
    /// - Parameter dewarpGrid: 真實模型輸出的 625 點網格；未提供時**不會**合成假曲面，直接跳過展平。
    public func autoProcessCapture(
        image: UIImage,
        document: DetectedDocument?,
        autoCrop: Bool = true,
        enableDewarp: Bool = true,
        filterMode: DocumentFilterMode = .auto,
        enhanceColor: Bool = true,
        darkenText: Bool = true,
        dewarpGrid: [SIMD2<Float>]? = nil
    ) -> UIImage {
        // 1. 幾何：方向正規化 + 四邊形透視拉正
        var processed = geometryCorrected(image: image, document: document, autoCrop: autoCrop)

        // 2. 25x25 自由曲面 GPU 硬體加速離屏展平（僅在真有模型網格時執行）
        if enableDewarp, let grid = dewarpGrid {
            if let dewarped = MetalOffscreenDewarper.shared.dewarpImage(image: processed, curvedGrid: grid, dewarpStrength: 1.0) {
                processed = dewarped
            }
        }

        // 3. 專用文件增強濾鏡
        return applyFilter(filterMode, to: processed, enhanceColor: enhanceColor, darkenText: darkenText)
    }

    // MARK: - Helpers

    /// 將任意方向的 UIImage 正規化為 `.up`，避免 CoreImage 依 EXIF 方向重複旋轉
    public static func normalizedImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.cgImage != nil {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
#endif
