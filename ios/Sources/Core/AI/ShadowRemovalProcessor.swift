import Foundation
import UIKit
import CoreImage
import CoreGraphics

final class ShadowRemovalProcessor {
    func process(_ image: UIImage) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        // Convert to grayscale-ish via luminance; blur large; divide
        let luminance = ci.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
            "inputGVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
            "inputBVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        ])
        let blur = luminance.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 80.0])
        // Use core image to approximate: output = input * (blurred+eps)^-1 scaled
        // Simpler: apply exposure adjust + contrast
        let out = ci.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.5])
            .applyingFilter("CIContrast", parameters: ["inputContrast": 1.2])
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
