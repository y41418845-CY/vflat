import SwiftUI

/// 相機掃描輔助引導覆蓋層 (中縫雷射導引線、水平儀與邊界框)
public struct ScanGuideOverlay: View {
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                // 1. 掃描有效取景框 (留白邊界)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        viewModel.motionSensor.isLevel ? Color.green.opacity(0.8) : Color.orange.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .padding(24)

                // 2. 雙頁中縫導引線 (Book Spine Guide Line)
                if viewModel.scanMode == .doublePage {
                    Path { path in
                        path.move(to: CGPoint(x: width / 2.0, y: 32))
                        path.addLine(to: CGPoint(x: width / 2.0, y: height - 32))
                    }
                    .stroke(Color.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))

                    Text("請將書脊對齊中線")
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .foregroundColor(.primary)
                        .position(x: width / 2.0, y: 56)
                }

                // 3. 水平儀傾角提示 (Tilt Indicator)
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.motionSensor.isLevel ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(viewModel.motionSensor.isLevel ? .green : .orange)
                        Text(viewModel.motionSensor.isLevel ? "角度水平" : String(format: "傾角: %.1f° (請放平手機)", viewModel.motionSensor.tiltAngle))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 120)
                }
            }
        }
        .allowsHitTesting(false) // 穿透手勢至相機
    }
}
