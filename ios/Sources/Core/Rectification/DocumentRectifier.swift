import Foundation
import UIKit
import CoreImage

enum DocumentFilterMode: String, CaseIterable, Identifiable, Codable {
    case auto      = "自動"
    case color     = "彩色"
    case grayscale = "灰階"
    case blackWhite = "黑白"
    case dark      = "文字"
    case original  = "原始"
    var id: String { rawValue }
    var iconName: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .color: return "photo.on.rectangle"
        case .grayscale: return "circle.lefthalf.filled"
        case .blackWhite: return "squareshape.fill"
        case .dark: return "doc.text.fill"
        case .original: return "photo"
        }
    }
}

final class DocumentRectifier {
    func geometryCorrected(image: UIImage, document: DetectedDocument?, autoCrop: Bool) -> UIImage {
        guard autoCrop, let doc = document else { return image }
        return correctPerspective(image: image, document: doc) ?? image
    }

    func correctPerspective(image: UIImage, document: DetectedDocument) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        let w = image.size.width, h = image.size.height
        let tl = CIVector(x: document.topLeft.x * w, y: (1 - document.topLeft.y) * h)
        let tr = CIVector(x: document.topRight.x * w, y: (1 - document.topRight.y) * h)
        let br = CIVector(x: document.bottomRight.x * w, y: (1 - document.bottomRight.y) * h)
        let bl = CIVector(x: document.bottomLeft.x * w, y: (1 - document.bottomLeft.y) * h)
        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(ci, forKey: kCIInputImageKey)
        filter?.setValue(tl, forKey: "inputTopLeft")
        filter?.setValue(tr, forKey: "inputTopRight")
        filter?.setValue(br, forKey: "inputBottomRight")
        filter?.setValue(bl, forKey: "inputBottomLeft")
        guard let out = filter?.outputImage else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func applyFilter(_ mode: DocumentFilterMode, to image: UIImage, enhanceColor: Bool, darkenText: Bool) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        var out = ci
        switch mode {
        case .auto:
            out = ci.applyingFilter("CIColorControls", parameters: ["inputContrast": 1.2, "inputSaturation": 1.1])
        case .color:
            if enhanceColor {
                out = ci.applyingFilter("CIColorControls", parameters: ["inputSaturation": 1.3, "inputContrast": 1.1])
            }
        case .grayscale:
            out = ci.applyingFilter("CIPhotoEffectMono", parameters: [:])
        case .blackWhite:
            out = ci.applyingFilter("CIColorControls", parameters: ["inputContrast": 2.0, "inputSaturation": 0.0, "inputBrightness": 0.1])
        case .dark:
            if darkenText {
                out = ci.applyingFilter("CIColorControls", parameters: ["inputContrast": 1.6, "inputBrightness": -0.05])
            }
        case .original:
            break
        }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: cg)
    }
}
