import SwiftUI

#if canImport(UIKit)
import UIKit

/// 1:1 復刻原廠「AI 橡皮擦 / InpaintViewController」互動編輯視窗
/// 像素級對齊 10:17 原廠截圖配置：
/// 1. 簡潔純白現代面板，無頂部多餘飾條，底圖全幅可視
/// 2. 筆刷尺寸粗細無級滑動調節 (左：細 cursive 筆畫 icon、中：原廠薄荷綠滑塊、右：粗 cursive 筆畫 icon)
/// 3. 底部原廠操作列：左側「取消」、中央雙圓環「Undo 復原 / Redo 重做」、右側「儲存」
/// 4. 原廠取消警告對話框 (「您真的要取消嗎？正在進行的工作可能會被取消。」)
/// 5. 原廠塗鴉進行中提示視窗 (「塗鴉橡皮擦正在進行中，如果您關閉應用程序，工作就會停止」)
/// 6. 雙階段泊松底色擴散調和核心 (AIInpainter)
public struct AIEraserView: View {
    public let sourceImage: UIImage
    public let onApply: (UIImage) -> Void
    public let onCancel: () -> Void

    @State private var lines: [DoodleLine] = []
    @State private var redoLines: [DoodleLine] = []
    @State private var currentLine: DoodleLine? = nil
    @State private var brushSize: CGFloat = 26
    @State private var isProcessing: Bool = false
    @State private var showingCancelAlert: Bool = false
    @State private var imageDisplaySize: CGSize = .zero

    // 畫布縮放平移狀態 (方便塗抹細微文字)
    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize = .zero

    public struct DoodleLine: Identifiable {
        public let id = UUID()
        public var points: [CGPoint]
        public var lineWidth: CGFloat
    }

    public init(sourceImage: UIImage, onApply: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.sourceImage = sourceImage
        self.onApply = onApply
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            // 背景深色（原廠相片檢視底色，徹底避免白屏錯覺）
            Color(red: 0.10, green: 0.10, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 中央主要畫布取景與塗抹手勢區 (無頂部黑色工具列，文檔頂格鋪滿)
                GeometryReader { geo in
                    ZStack {
                        // 文檔底圖
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(canvasScale)
                            .offset(canvasOffset)
                            .background(
                                GeometryReader { imgGeo in
                                    Color.clear
                                        .onAppear {
                                            self.imageDisplaySize = imgGeo.size
                                        }
                                        .onChange(of: imgGeo.size) { newSize in
                                            self.imageDisplaySize = newSize
                                        }
                                }
                            )

                        // 手繪塗抹路徑預覽 (原廠經典半透明青綠色 #36D1BC 筆觸)
                        Canvas { context, size in
                            for line in lines {
                                var path = Path()
                                guard let first = line.points.first else { continue }
                                path.move(to: first)
                                for pt in line.points.dropFirst() {
                                    path.addLine(to: pt)
                                }
                                context.stroke(
                                    path,
                                    with: .color(Color(red: 0.21, green: 0.82, blue: 0.74).opacity(0.45)),
                                    style: StrokeStyle(lineWidth: line.lineWidth, lineCap: .round, lineJoin: .round)
                                )
                            }

                            if let cur = currentLine, let first = cur.points.first {
                                var path = Path()
                                path.move(to: first)
                                for pt in cur.points.dropFirst() {
                                    path.addLine(to: pt)
                                }
                                context.stroke(
                                    path,
                                    with: .color(Color(red: 0.21, green: 0.82, blue: 0.74).opacity(0.55)),
                                    style: StrokeStyle(lineWidth: cur.lineWidth, lineCap: .round, lineJoin: .round)
                                )
                            }
                        }
                        .scaleEffect(canvasScale)
                        .offset(canvasOffset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let adjustedPoint = CGPoint(
                                    x: (value.location.x - geo.size.width / 2 - canvasOffset.width) / canvasScale + geo.size.width / 2,
                                    y: (value.location.y - geo.size.height / 2 - canvasOffset.height) / canvasScale + geo.size.height / 2
                                )
                                if currentLine == nil {
                                    currentLine = DoodleLine(points: [adjustedPoint], lineWidth: brushSize)
                                } else {
                                    currentLine?.points.append(adjustedPoint)
                                }
                            }
                            .onEnded { _ in
                                if let finished = currentLine {
                                    lines.append(finished)
                                    redoLines.removeAll() // 新筆跡清空 redo
                                    currentLine = nil
                                }
                            }
                    )
                }

                // 2. 底部原廠 1:1 控制抽屜面板 (筆刷滑塊 + 取消 / 復原 / 重做 / 儲存)
                bottomControlPanel
            }

            // 3. 原廠塗鴉橡皮擦運算中進度視窗 (1:1 對齊官方 scribble_eraser_progress_title)
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)

                        Text("塗鴉橡皮擦正在進行中")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)

                        Text("如果您關閉應用程序，工作就會停止")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(Color(white: 0.18, opacity: 0.96))
                    .cornerRadius(18)
                    .shadow(radius: 12)
                }
            }
        }
        // 原廠「您真的要取消嗎？」確認視窗
        .alert(isPresented: $showingCancelAlert) {
            Alert(
                title: Text("您真的要取消嗎？"),
                message: Text("正在進行的工作可能會被取消。"),
                primaryButton: .destructive(Text("放棄變更")) {
                    onCancel()
                },
                secondaryButton: .cancel(Text("繼續編輯"))
            )
        }
    }

    // MARK: - 底部原廠 1:1 控制抽屜面板 (10:17 截圖復刻)

    private var bottomControlPanel: some View {
        VStack(spacing: 12) {
            // 第一列：筆刷粗細連續調節滑塊 (左右書法筆劃 icon + 薄荷綠進度軌道)
            HStack(spacing: 16) {
                // 左側：細筆劃 icon (cursive 'h' 細線)
                CursiveStrokeIcon(lineWidth: 1.8)

                // 中央：原廠薄荷綠筆刷無級滑塊
                Slider(value: $brushSize, in: 8...56)
                    .tint(Color(red: 0.16, green: 0.76, blue: 0.58))

                // 右側：粗筆劃 icon (cursive 'h' 粗線)
                CursiveStrokeIcon(lineWidth: 5.0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            // 第二列：操作按鈕列 (取消 | 復原 圓環 / 重做 圓環 | 儲存)
            HStack(alignment: .center) {
                // 左側：取消按鈕
                Button(action: {
                    if lines.isEmpty {
                        onCancel()
                    } else {
                        showingCancelAlert = true
                    }
                }) {
                    Text("取消")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                }

                Spacer()

                // 中央：圓環復原 (Undo) 與 重做 (Redo) 按鈕組
                HStack(spacing: 18) {
                    // 復原 (Undo) 圓環按鈕
                    Button(action: {
                        if let last = lines.popLast() {
                            redoLines.append(last)
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(lines.isEmpty ? Color.gray.opacity(0.35) : Color(red: 0.15, green: 0.15, blue: 0.15))
                        }
                    }
                    .disabled(lines.isEmpty)

                    // 重做 (Redo) 圓環按鈕
                    Button(action: {
                        if let redone = redoLines.popLast() {
                            lines.append(redone)
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(redoLines.isEmpty ? Color.gray.opacity(0.35) : Color(red: 0.15, green: 0.15, blue: 0.15))
                        }
                    }
                    .disabled(redoLines.isEmpty)
                }

                Spacer()

                // 右側：儲存按鈕 (有筆跡時點亮綠色，無筆跡時呈淺灰置灰)
                Button(action: {
                    performInpaint()
                }) {
                    Text("儲存")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(lines.isEmpty ? Color(white: 0.78) : Color(red: 0.13, green: 0.62, blue: 0.48))
                }
                .disabled(lines.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 22)
        }
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - 核心運算 (AI Inpainting)

    private func performInpaint() {
        guard !lines.isEmpty else {
            onCancel()
            return
        }

        isProcessing = true
        let original = sourceImage
        let capturedLines = lines
        let displaySize = imageDisplaySize

        Task.detached(priority: .userInitiated) {
            guard let cg = original.cgImage else {
                await MainActor.run { self.onCancel() }
                return
            }

            let imgW = cg.width
            let imgH = cg.height
            let scaleX = displaySize.width > 0 ? CGFloat(imgW) / displaySize.width : 1.0
            let scaleY = displaySize.height > 0 ? CGFloat(imgH) / displaySize.height : 1.0

            // 建立黑底白線遮罩 Bitmap
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let maskContext = CGContext(
                data: nil,
                width: imgW,
                height: imgH,
                bitsPerComponent: 8,
                bytesPerRow: imgW,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                await MainActor.run { self.onCancel() }
                return
            }

            // 黑色背景 (代表保留區域)
            maskContext.setFillColor(gray: 0.0, alpha: 1.0)
            maskContext.fill(CGRect(x: 0, y: 0, width: imgW, height: imgH))

            // 白色筆觸 (代表欲擦除修復區域)
            maskContext.setStrokeColor(gray: 1.0, alpha: 1.0)
            maskContext.setLineCap(.round)
            maskContext.setLineJoin(.round)

            for line in capturedLines {
                guard let first = line.points.first else { continue }
                maskContext.setLineWidth(line.lineWidth * max(scaleX, scaleY))
                maskContext.beginPath()
                maskContext.move(to: CGPoint(x: first.x * scaleX, y: CGFloat(imgH) - first.y * scaleY))
                for pt in line.points.dropFirst() {
                    maskContext.addLine(to: CGPoint(x: pt.x * scaleX, y: CGFloat(imgH) - pt.y * scaleY))
                }
                maskContext.strokePath()
            }

            guard let maskCG = maskContext.makeImage() else {
                await MainActor.run { self.onCancel() }
                return
            }

            let maskImg = UIImage(cgImage: maskCG)
            let result = AIInpainter.shared.inpaint(image: original, maskImage: maskImg)

            await MainActor.run {
                self.isProcessing = false
                self.onApply(result)
            }
        }
    }
}

/// 1:1 原廠花體筆劃 icon (細筆畫 / 粗筆畫 取樣示意圖)
public struct CursiveStrokeIcon: View {
    public let lineWidth: CGFloat

    public init(lineWidth: CGFloat) {
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            let w = size.width
            let h = size.height

            // 繪製原廠 cursive 'h' 升筆環繞軌跡
            path.move(to: CGPoint(x: w * 0.18, y: h * 0.82))
            path.addCurve(
                to: CGPoint(x: w * 0.52, y: h * 0.12),
                control1: CGPoint(x: w * 0.10, y: h * 0.50),
                control2: CGPoint(x: w * 0.35, y: h * 0.18)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.42, y: h * 0.86),
                control1: CGPoint(x: w * 0.65, y: h * 0.08),
                control2: CGPoint(x: w * 0.46, y: h * 0.55)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.70, y: h * 0.58),
                control1: CGPoint(x: w * 0.42, y: h * 0.66),
                control2: CGPoint(x: w * 0.54, y: h * 0.54)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.92, y: h * 0.80),
                control1: CGPoint(x: w * 0.82, y: h * 0.62),
                control2: CGPoint(x: w * 0.88, y: h * 0.74)
            )

            context.stroke(
                path,
                with: .color(Color(red: 0.15, green: 0.15, blue: 0.15)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 22, height: 26)
    }
}
#endif
