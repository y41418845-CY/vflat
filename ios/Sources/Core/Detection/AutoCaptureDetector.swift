import Foundation
import CoreGraphics

final class AutoCaptureDetector {
    private var lastCorners: [CGPoint]?
    private var stableStart: TimeInterval?
    private let cooldown: TimeInterval = 1.8
    private var lastTrigger: TimeInterval = 0
    private(set) var stabilityProgress: Double = 0

    func processFrame(document: DetectedDocument?, at time: TimeInterval) -> Bool {
        guard let doc = document else {
            stabilityProgress = 0
            lastCorners = nil
            stableStart = nil
            return false
        }
        let corners = [doc.topLeft, doc.topRight, doc.bottomRight, doc.bottomLeft]
        if let prev = lastCorners {
            let maxDisp = zip(prev, corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
            // normalized 0..1; threshold 8px ~ 0.01 in normalized coords
            if maxDisp < 0.01 {
                if stableStart == nil { stableStart = time }
                let elapsed = time - (stableStart ?? time)
                stabilityProgress = min(1.0, elapsed / 0.8)
                if stabilityProgress >= 1.0 && time - lastTrigger > cooldown {
                    lastTrigger = time
                    reset()
                    return true
                }
            } else {
                stableStart = nil
                stabilityProgress = 0
            }
        }
        lastCorners = corners
        return false
    }

    func reset() {
        lastCorners = nil
        stableStart = nil
        stabilityProgress = 0
    }
}
