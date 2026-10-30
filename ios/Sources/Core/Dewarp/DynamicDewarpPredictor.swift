import Foundation
import UIKit
import simd

final class DynamicDewarpPredictor {
    func predictGrid(for image: UIImage) -> [[simd_float2]] {
        // 25x25 grid
        let n = 25
        // compute horizontal brightness profile to find spine (center dip)
        guard let cg = image.cgImage else { return defaultGrid(n) }
        let width = cg.width, height = cg.height
        // sample center row band
        // simple: find column with min brightness in central 30%
        var colBrightness = [Double](repeating: 0, count: width)
        // downsample
        // Use a simple approach: iterate pixels in middle horizontal band
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return defaultGrid(n) }
        let bytesPerRow = cg.bytesPerRow
        let bpp = cg.bitsPerPixel / 8
        let bandTop = height * 2 / 5
        let bandBottom = height * 3 / 5
        for y in bandTop..<bandBottom {
            for x in 0..<width {
                let off = y * bytesPerRow + x * bpp
                let r = Double(ptr[off])
                let g = Double(ptr[off+1])
                let b = Double(ptr[off+2])
                colBrightness[x] += (r+g+b)/3.0
            }
        }
        // find min in central 30%
        let c0 = width * 35 / 100
        let c1 = width * 65 / 100
        var minVal = Double.greatestFiniteMagnitude
        var spineX = width / 2
        for x in c0..<c1 {
            if colBrightness[x] < minVal {
                minVal = colBrightness[x]
                spineX = x
            }
        }
        let spineRatio = Double(spineX) / Double(width)
        // parabola coefficient for spine curvature
        let a = -0.15 // concave
        // build grid with horizontal warp
        var grid = [[simd_float2]]()
        for row in 0..<n {
            var r = [simd_float2]()
            for col in 0..<n {
                let u = Float(col) / Float(n - 1)
                let v = Float(row) / Float(n - 1)
                // horizontal displacement based on distance from spine
                let du = Float(spineRatio) - u
                let warp = Float(a) * du * du
                let uu = u + warp * (1.0 - abs(du) * 2) // stronger near spine
                r.append(simd_float2(uu, v))
            }
            grid.append(r)
        }
        return grid
    }

    private func defaultGrid(_ n: Int) -> [[simd_float2]] {
        var grid = [[simd_float2]]()
        for row in 0..<n {
            var r = [simd_float2]()
            for col in 0..<n {
                r.append(simd_float2(Float(col)/Float(n-1), Float(row)/Float(n-1)))
            }
            grid.append(r)
        }
        return grid
    }
}
