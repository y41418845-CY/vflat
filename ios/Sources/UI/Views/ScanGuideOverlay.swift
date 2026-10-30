import SwiftUI

struct ScanGuideOverlay: View {
    let detectedDocument: DetectedDocument?
    let motion: MotionSensor

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let doc = detectedDocument {
                    Path { p in
                        p.move(to: pt(doc.topLeft, geo.size))
                        p.addLine(to: pt(doc.topRight, geo.size))
                        p.addLine(to: pt(doc.bottomRight, geo.size))
                        p.addLine(to: pt(doc.bottomLeft, geo.size))
                        p.closeSubpath()
                    }
                    .stroke(Color(red:0.22,green:0.85,blue:0.45), lineWidth: 2)
                } else {
                    Text("尋找文件中…")
                        .foregroundColor(.white)
                }
                // pose indicator
                if abs(motion.roll) > 0.1 || abs(motion.pitch) > 0.1 {
                    Text("請保持水平")
                        .foregroundColor(.yellow)
                        .position(x: geo.size.width/2, y: geo.size.height/2 + 100)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func pt(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}
