import Foundation
import UIKit
import CoreImage

final class HandwritingRemovalProcessor {
    func process(_ image: UIImage) -> UIImage {
        guard let ci = CIImage(image: image) else { return image }
        // Approximate: boost contrast / monochrome to suppress colored handwriting
        let mono = ci.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0, "inputContrast": 1.3])
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(mono, from: mono.extent) else { return image }
        return UIImage(cgImage: cg)
    }
}
