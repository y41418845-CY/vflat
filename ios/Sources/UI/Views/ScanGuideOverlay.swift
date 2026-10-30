import SwiftUI

/// 完整 1:1 復刻 iPhone 版 vFlat 輔助引導覆蓋層
/// 包含：即時文件邊界框選（黃色流動框）、中央「尋找文件」狀態標籤、右側十字姿態儀
public struct ScanGuideOverlay: View {
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    // 相機預設以 16:9 影格輸出；若實際感測器格式不同，僅影響框線些微內縮，不影響裁切結果
    private let cameraAspect: CGFloat = 9.0 / 16.0

    /// 將相機標準化座標轉換為全螢幕 Aspect-Fill 投影，保證邊界框與實體物品邊緣貼合
    private func aspectFillPoint(_ pt: CGPoint, viewWidth: CGFloat, viewHeight: CGFloat) -> CGPoint {
        let viewAspect = viewWidth / viewHeight
        if viewAspect < cameraAspect {
            // 螢幕較細長，以高度為基準填滿，左右側裁切
            let renderedWidth = viewHeight * cameraAspect
            let offsetX = (renderedWidth - viewWidth) / 2.0
            let screenX = pt.x * renderedWidth - offsetX
            let screenY = pt.y * viewHeight
            return CGPoint(x: screenX, y: screenY)
        } else {
            // 螢幕較寬，以寬度為基準填滿，上下端裁切
            let renderedHeight = viewWidth / cameraAspect
            let offsetY = (renderedHeight - viewHeight) / 2.0
            let screenX = pt.x * viewWidth
            let screenY = pt.y * renderedHeight - offsetY
            return CGPoint(x: screenX, y: screenY)
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                // 1. 自動偵測之文件邊界框線（受「掃描輔助引導線」設定控制）
                if viewModel.useScanGuide, let doc = viewModel.detectedDocument {
                    let p1 = aspectFillPoint(doc.topLeft, viewWidth: width, viewHeight: height)
                    let p2 = aspectFillPoint(doc.topRight, viewWidth: width, viewHeight: height)
                    let p3 = aspectFillPoint(doc.bottomRight, viewWidth: width, viewHeight: height)
                    let p4 = aspectFillPoint(doc.bottomLeft, viewWidth: width, viewHeight: height)

                    Path { path in
                        path.move(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.closeSubpath()
                    }
                    .fill(Color(red: 0.98, green: 0.85, blue: 0.25).opacity(0.18))

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

                // 2. 中央「尋找文件」動態提示膠囊（未辨識到文件時顯示）
                if viewModel.useScanGuide,
                   !viewModel.isDocumentDetected,
                   !viewModel.isProcessingCapture {
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
                    .transition(.opacity)
                }

                // 3. 右下側：十字方向姿態儀
                if viewModel.useScanGuide {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 58, height: 58)

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

                                // 水平狀態指示燈：傾角在容許範圍內時轉綠
                                Circle()
                                    .fill(viewModel.motionSensor.isLevel ? Color.green.opacity(0.85) : Color.white.opacity(0.8))
                                    .frame(width: 12, height: 12)
                            }
                            .overlay(
                                // 依實際 roll 角度旋轉外環，讓使用者知道該往哪邊修正
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(min(abs(viewModel.motionSensor.rollDegrees) / 30.0, 1.0)) * 0.25)
                                    .stroke(
                                        viewModel.motionSensor.isLevel ? Color.green.opacity(0.8) : Color(red: 0.98, green: 0.82, blue: 0.35),
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(viewModel.motionSensor.rollDegrees >= 0 ? -90 : 90))
                            )
                            .padding(.trailing, 20)
                            .padding(.bottom, 150)
                            .animation(.easeOut(duration: 0.15), value: viewModel.motionSensor.rollDegrees)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: viewModel.useScanGuide)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isDocumentDetected)
    }
}
