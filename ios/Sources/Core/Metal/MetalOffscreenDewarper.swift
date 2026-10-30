import Foundation
import UIKit
import simd
#if canImport(Metal)
import Metal
#endif

final class MetalOffscreenDewarper {
    func dewarpImage(image: UIImage, curvedGrid: [[simd_float2]], dewarpStrength: Float = 1.0) -> UIImage? {
        // Fallback: return original (Metal compute not implemented in clean-room)
        return image
    }
}
