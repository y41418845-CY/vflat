import SwiftUI

#if canImport(UIKit)
import UIKit

/// 1:1 復刻原廠「AI 橡皮擦 / InpaintViewController」互動編輯視窗
/// 深度參考原廠 InpaintProcessor、InpaintViewModel 與官方繁體中文字串資源：
/// 1. 支援手繪塗鴉標記、Undo 復原、Redo 重做與清除全部標記
/// 2. 原廠三段筆刷尺寸 (細 14pt、中 26pt、粗 44pt)，視覺化圓點高亮
/// 3. 原廠取消警告對話框 (「您真的要取消嗎？正在進行的工作可能會被取消。」)
/// 4. 原廠塗鴉進行中提示視窗 (「塗鴉橡皮擦正在進行中，如果您關閉應用程序，工作就會停止」)
/// 5. 整合雙階段泊松底色擴散與邊緣紋理修補核心 (AIInpainter)
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
            // 背景深黑 (原廠相片檢視底色)
            Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 頂部導航工具列 (取消 | AI 橡皮擦 | 完成)
                topBar

                // 2. 中央畫布取景與塗抹手勢區 (支援雙指放大縮小微調)
                GeometryReader { geo in
                    ZStack {
                        // 底圖
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

                        // 手繪塗抹路徑預覽 (原廠經典半透明青綠色 #50E3C2 筆觸)
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
                                    with: .color(Color(red: 0.16, green: 0.85, blue: 0.55).opacity(0.48)),
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
                                    with: .color(Color(red: 0.16, green: 0.85, blue: 0.55).opacity(0.55)),
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

                // 3. 底部筆刷切換與 Undo / Redo 工具列
                bottomBar
            }

            // 4. 原廠塗鴉橡皮擦運算中進度視窗 (1:1 對齊官方 scribble_eraser_progress_title)
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

    // MARK: - 頂部導航工具列 (原廠 1:1)

    private var topBar: some View {
        HStack {
            // 取消按鈕 (若有筆跡則彈出確認視窗)
            Button(action: {
                if lines.isEmpty {
                    onCancel()
                } else {
                    showingCancelAlert = true
                }
            }) {
                Text("取消")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }

            Spacer()

            // 標題：AI 橡皮擦
            Text("AI 橡皮擦")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // 完成按鈕 (原廠經典綠色膠囊)
            Button(action: {
                performInpaint()
            }) {
                Text("完成")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(lines.isEmpty ? Color.gray.opacity(0.4) : Color(red: 0.08, green: 0.78, blue: 0.44))
                    .clipShape(Capsule())
            }
            .disabled(lines.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }

    // MARK: - 底部控制工具列 (Undo / 筆刷切換 / Redo / 自動消手指)

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // 提示文案
            Text(lines.isEmpty ? "請用手指塗抹要擦除的字跡、污漬或手指" : "已標記 \(lines.count) 處區域，點擊「完成」即可進行 AI 擦除")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(lines.isEmpty ? .gray : Color(red: 0.16, green: 0.85, blue: 0.55))

            HStack(spacing: 16) {
                // 1. 復原 (Undo)
                Button(action: {
                    if let last = lines.popLast() {
                        redoLines.append(last)
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 18, weight: .semibold))
                        Text("復原")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(lines.isEmpty ? .gray.opacity(0.5) : .white)
                    .frame(width: 44)
                }
                .disabled(lines.isEmpty)

                Spacer()

                // 2. 原廠三段筆刷切換 (細 14pt / 中 26pt / 粗 44pt)
                HStack(spacing: 18) {
                    brushButton(title: "細", size: 14)
                    brushButton(title: "中", size: 26)
                    brushButton(title: "粗", size: 44)
                }

                Spacer()

                // 3. 重做 (Redo)
                Button(action: {
                    if let redone = redoLines.popLast() {
                        lines.append(redone)
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 18, weight: .semibold))
                        Text("重做")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(redoLines.isEmpty ? .gray.opacity(0.5) : .white)
                    .frame(width: 44)
                }
                .disabled(redoLines.isEmpty)
            }
            .padding(.horizontal, 16)

            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.vertical, 4)

            // 4. 輔助捷徑列 (一鍵自動消手指 / 清除全部標記)
            HStack(spacing: 16) {
                Button(action: {
                    performAutoFingerRemoval()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 13))
                        Text("一鍵消手指")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }

                if !lines.isEmpty {
                    Button(action: {
                        lines.removeAll()
                        redoLines.removeAll()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("清除全部標記")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(Color.red.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }

    @ViewBuilder
    private func brushButton(title: String, size: CGFloat) -> some View {
        let isSelected = (brushSize == size)
        Button(action: {
            brushSize = size
        }) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 32, height: 32)

                    Circle()
                        .fill(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.white.opacity(0.7))
                        .frame(width: size / 2.2, height: size / 2.2)
                }

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : .gray)
            }
            .frame(width: 48)
        }
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

    private func performAutoFingerRemoval() {
        isProcessing = true
        let original = sourceImage
        Task.detached(priority: .userInitiated) {
            let cleaned = FingerRemovalProcessor.shared.removeFingers(image: original)
            await MainActor.run {
                self.isProcessing = false
                self.onApply(cleaned)
            }
        }
    }
}
#endif
