import SwiftUI

/// 完整 1:1 復刻 iPhone 版 vFlat 輔助引導覆蓋層
/// 包含：即時文件邊界框選（黃色流動框）、中央「尋找文件」狀態標籤、右側十字姿態儀
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
                // 1. 自動偵測之文件邊界框線 (如圖二之青綠/黃色選取框)
                if let doc = viewModel.detectedDocument {
                    Path { path in
                        let p1 = CGPoint(x: doc.topLeft.x * width, y: doc.topLeft.y * height)
                        let p2 = CGPoint(x: doc.topRight.x * width, y: doc.topRight.y * height)
                        let p3 = CGPoint(x: doc.bottomRight.x * width, y: doc.bottomRight.y * height)
                        let p4 = CGPoint(x: doc.bottomLeft.x * width, y: doc.bottomLeft.y * height)

                        path.move(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.closeSubpath()
                    }
                    .fill(Color(red: 0.1, green: 0.8, blue: 0.7).opacity(0.18)) // 輕微半透明填色

                    Path { path in
                        let p1 = CGPoint(x: doc.topLeft.x * width, y: doc.topLeft.y * height)
                        let p2 = CGPoint(x: doc.topRight.x * width, y: doc.topRight.y * height)
                        let p3 = CGPoint(x: doc.bottomRight.x * width, y: doc.bottomRight.y * height)
                        let p4 = CGPoint(x: doc.bottomLeft.x * width, y: doc.bottomLeft.y * height)

                        path.move(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.closeSubpath()
                    }
                    .stroke(
                        Color(red: 0.2, green: 0.9, blue: 0.8),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }

                // 2. 中央「尋找文件」動態提示膠囊 (未辨識到文件時顯示，對齊圖一)
                if !viewModel.isDocumentDetected {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Text("尋找文件")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        Spacer()
                    }
                }

                // 3. 右下側：十字方向姿態儀 (對齊圖一中灰色圓形方向盤)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 58, height: 58)

                            // 十字按鈕箭頭
                            VStack(spacing: 12) {
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.6))
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 8))
                                    .rotationEffect(.degrees(180))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            HStack(spacing: 12) {
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 8))
                                    .rotationEffect(.degrees(-90))
                                    .foregroundColor(.white.opacity(0.6))
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 8))
                                    .rotationEffect(.degrees(90))
                                    .foregroundColor(.white.opacity(0.6))
                            }

                            Circle()
                                .fill(viewModel.motionSensor.isLevel ? Color.green.opacity(0.8) : Color.white.opacity(0.8))
                                .frame(width: 12, height: 12)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 150)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
