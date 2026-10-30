import SwiftUI

struct LoupeCropView: View {
    @EnvironmentObject var vm: ScannerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var corners: [String: CGPoint] = [
        "tl": CGPoint(x: 0.1, y: 0.1),
        "tr": CGPoint(x: 0.9, y: 0.1),
        "br": CGPoint(x: 0.9, y: 0.9),
        "bl": CGPoint(x: 0.1, y: 0.9)
    ]
    private let cropSpaceName = "LoupeCropSpace"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let img = vm.lastRawPageImage ?? vm.lastPreviewImage {
                    Image(uiImage: img).resizable().scaledToFit()
                }
                // polygon
                Path { p in
                    let pts = ["tl","tr","br","bl"].map { corners[$0]! }
                    p.move(to: scaled(pts[0], geo.size))
                    for pt in pts.dropFirst() { p.addLine(to: scaled(pt, geo.size)) }
                    p.closeSubpath()
                }
                .fill(Color.blue.opacity(0.25))
                .overlay(
                    Path { p in
                        let pts = ["tl","tr","br","bl"].map { corners[$0]! }
                        p.move(to: scaled(pts[0], geo.size))
                        for pt in pts.dropFirst() { p.addLine(to: scaled(pt, geo.size)) }
                        p.closeSubpath()
                    }.stroke(Color.blue, lineWidth: 2)
                )
                ForEach(["tl","tr","br","bl"], id: \.self) { key in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .position(scaled(corners[key]!, geo.size))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(cropSpaceName))
                                .onChanged { v in
                                    corners[key] = CGPoint(x: v.location.x / geo.size.width, y: v.location.y / geo.size.height)
                                }
                        )
                }
            }
            .coordinateSpace(name: cropSpaceName)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
    }

    private func scaled(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}
