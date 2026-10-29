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

            // 將相機標準化座標轉換為全螢幕 Aspect-Fill 投影，保證邊界框與實體物品邊緣 100% 貼合
            func aspectFillPoint(_ pt: CGPoint, camAspect: CGFloat = 9.0 / 16.0) -> CGPoint {
                let viewAspect = width / height
                if viewAspect < camAspect {
                    // 螢幕較細長，以高度為基準填滿，左右側裁切
                    let renderedWidth = height * camAspect
                    let offsetX = (renderedWidth - width) / 2.0
                    let screenX = pt.x * renderedWidth - offsetX
                    let screenY = pt.y * height
                    return CGPoint(x: screenX, y: screenY)
                } else {
                    // 螢幕較寬，以寬度為基準填滿，上下端裁切
                    let renderedHeight = width / camAspect
                    let offsetY = (renderedHeight - height) / 2.0
                    let screenX = pt.x * width
                    let screenY = pt.y * renderedHeight - offsetY
                    return CGPoint(x: screenX, y: screenY)
                }
            }

            ZStack {
                // 1. 自動偵測之文件邊界框線 (精確貼合整體外輪廓)
                if let doc = viewModel.detectedDocument {
                    let p1 = aspectFillPoint(doc.topLeft)
                    let p2 = aspectFillPoint(doc.topRight)
                    let p3 = aspectFillPoint(doc.bottomRight)
                    let p4 = aspectFillPoint(doc.bottomLeft)

                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.closeSubpath()
                    }
                    .fill(Color(red: 0.98, green: 0.85, blue: 0.25).opacity(0.18)) // 原版 vFlat 之微光半透明填色

                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.closeSubpath()
                    }
                    .stroke(
                        Color(red: 0.98, green: 0.85, blue: 0.25),
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
