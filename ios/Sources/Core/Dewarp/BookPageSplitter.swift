import Foundation
import UIKit

final class BookPageSplitter {
    func detectSpineRatio(image: UIImage) -> CGFloat {
        guard let cg = image.cgImage else { return 0.5 }
        let width = cg.width, height = cg.height
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0.5 }
        let bytesPerRow = cg.bytesPerRow
        let bpp = cg.bitsPerPixel / 8
        var colBrightness = [Double](repeating: 0, count: width)
        let bandTop = height * 2 / 5
        let bandBottom = height * 3 / 5
        for y in bandTop..<bandBottom {
            for x in 0..<width {
                let off = y * bytesPerRow + x * bpp
                let r = Double(ptr[off]); let g = Double(ptr[off+1]); let b = Double(ptr[off+2])
                colBrightness[x] += (r+g+b)/3.0
            }
        }
        let c0 = width * 35 / 100
        let c1 = width * 65 / 100
        var maxVal = -Double.greatestFiniteMagnitude
        var spineX = width / 2
        for x in c0..<c1 {
            if colBrightness[x] > maxVal {
                maxVal = colBrightness[x]
                spineX = x
            }
        }
        return CGFloat(spineX) / CGFloat(width)
    }

    struct SplitResult {
        let leftPage: UIImage
        let rightPage: UIImage
    }

    func splitPage(image: UIImage, splitRatio: CGFloat) -> SplitResult? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width
        let splitX = Int(splitRatio * CGFloat(w))
        let leftRect = CGRect(x: 0, y: 0, width: splitX, height: cg.height)
        let rightRect = CGRect(x: splitX, y: 0, width: w - splitX, height: cg.height)
        guard let leftCG = cg.cropping(to: leftRect), let rightCG = cg.cropping(to: rightRect) else { return nil }
        return SplitResult(leftPage: UIImage(cgImage: leftCG), rightPage: UIImage(cgImage: rightCG))
    }
}
