import Foundation
import UIKit
import CoreImage

final class DeblurProcessor {
    func process(_ image: UIImage) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        // Unsharp mask approximation via CISharpenLuminance + contrast
        let sharp = ci.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.7])
            .applyingFilter("CIUnsharpMask", parameters: ["inputRadius": 2.5, "inputIntensity": 0.5])
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(sharp, from: sharp.extent) else { return image }
        return UIImage(cgImage: cg)
    }
}
