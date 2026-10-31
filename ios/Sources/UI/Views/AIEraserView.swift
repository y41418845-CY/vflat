import SwiftUI

#if canImport(UIKit)
import UIKit

/// 1:1 復刻原廠「AI 橡皮擦 / InpaintViewController」互動編輯視窗
/// 像素級對齊 10:17 原廠截圖配置與即時擦除行為：
/// 1. 隨塗隨擦：使用者手指劃過並放開時，立即在該區域進行 AI Inpaint 即時抹平，消除字跡/污漬
/// 2. 筆刷尺寸粗細無級滑動調節 (左：細 cursive 筆畫 icon、中：原廠薄荷綠滑塊、右：粗 cursive 筆畫 icon)
/// 3. 底部原廠操作列：左側「取消」、中央雙圓環「Undo 復原 / Redo 重做」、右側「儲存」
/// 4. 歷史堆疊：支援多步復原與重做
/// 5. 沉浸深色畫布，文檔頂格居中全幅展現
public struct AIEraserView: View {
    public let sourceImage: UIImage
    public let onApply: (UIImage) -> Void
    public let onCancel: () -> Void

    @State private var currentImage: UIImage
    @State private var undoStack: [UIImage] = []
    @State private var redoStack: [UIImage] = []
    @State private var activeStroke: [CGPoint] = []
    @State private var brushSize: CGFloat = 26
    @State private var isErasingStroke: Bool = false
    @State private var showingCancelAlert: Bool = false

    public init(sourceImage: UIImage, onApply: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.sourceImage = sourceImage
        self._currentImage = State(initialValue: sourceImage)
        self.onApply = onApply
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            // 背景深色（原廠相片檢視底色）
            Color(red: 0.10, green: 0.10, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 中央主要畫布取景與即時塗抹擦除手勢區
                GeometryReader { geo in
                    let containerSize = geo.size
                    let displayRect = calculateImageDisplayRect(containerSize: containerSize, image: currentImage)

                    ZStack {
                        // 當前底圖 (即時反映擦除效果)
                        Image(uiImage: currentImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: containerSize.width, height: containerSize.height)

                        // 手繪塗抹中路徑預覽 (原廠經典半透明青綠色 #36D1BC 筆觸)
                        Canvas { context, size in
                            if activeStroke.count >= 2 {
                                var path = Path()
                                path.move(to: activeStroke[0])
                                for pt in activeStroke.dropFirst() {
                                    path.addLine(to: pt)
                                }
                                context.stroke(
                                    path,
                                    with: .color(Color(red: 0.21, green: 0.82, blue: 0.74).opacity(0.50)),
                                    style: StrokeStyle(lineWidth: brushSize, lineCap: .round, lineJoin: .round)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                activeStroke.append(value.location)
                            }
                            .onEnded { _ in
                                handleStrokeEnded(displayRect: displayRect)
                            }
                    )
                }

                // 2. 底部原廠 1:1 控制抽屜面板 (筆刷滑塊 + 取消 / 復原 / 重做 / 儲存)
                bottomControlPanel
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

    // MARK: - 計算圖片在 scaledToFit 下的實際呈現矩形

    private func calculateImageDisplayRect(containerSize: CGSize, image: UIImage) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return .zero }

        let imgAspect = imgSize.width / imgSize.height
        let containerAspect = containerSize.width / containerSize.height

        var renderW: CGFloat = 0
        var renderH: CGFloat = 0
        if imgAspect > containerAspect {
            renderW = containerSize.width
            renderH = containerSize.width / imgAspect
        } else {
            renderH = containerSize.height
            renderW = containerSize.height * imgAspect
        }

        let originX = (containerSize.width - renderW) / 2
        let originY = (containerSize.height - renderH) / 2
        return CGRect(x: originX, y: originY, width: renderW, height: renderH)
    }

    // MARK: - 手指放開瞬間：即刻執行單筆局部 AI Inpaint 擦除

    private func handleStrokeEnded(displayRect: CGRect) {
        guard activeStroke.count >= 2, displayRect.width > 0, displayRect.height > 0 else {
            activeStroke.removeAll()
            return
        }

        let strokePoints = activeStroke
        activeStroke.removeAll()

        guard let baseCG = currentImage.cgImage else { return }
        let imgW = baseCG.width
        let imgH = baseCG.height
        let scaleX = CGFloat(imgW) / displayRect.width
        let scaleY = CGFloat(imgH) / displayRect.height
        let linePx = brushSize * max(scaleX, scaleY)

        // 1. 將當前畫面備份至 Undo 堆疊
        undoStack.append(currentImage)
        redoStack.removeAll()

        // 2. 在背景極速繪製 Mask 並計算 Inpaint
        isErasingStroke = true
        let snapshotImage = currentImage

        Task.detached(priority: .userInitiated) {
            let colorSpace = CGColorSpaceCreateDeviceGray()
            guard let maskCtx = CGContext(
                data: nil,
                width: imgW,
                height: imgH,
                bitsPerComponent: 8,
                bytesPerRow: imgW,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return
            }

            // 黑色背景 (代表保留原圖)
            maskCtx.setFillColor(gray: 0.0, alpha: 1.0)
            maskCtx.fill(CGRect(x: 0, y: 0, width: imgW, height: imgH))

            // 白色筆劃 (代表擦除修復區域)
            maskCtx.setStrokeColor(gray: 1.0, alpha: 1.0)
            maskCtx.setLineCap(.round)
            maskCtx.setLineJoin(.round)
            maskCtx.setLineWidth(linePx)

            maskCtx.beginPath()
            let first = strokePoints[0]
            let firstImgX = (first.x - displayRect.origin.x) * scaleX
            let firstImgY = CGFloat(imgH) - (first.y - displayRect.origin.y) * scaleY
            maskCtx.move(to: CGPoint(x: firstImgX, y: firstImgY))

            for pt in strokePoints.dropFirst() {
                let imgX = (pt.x - displayRect.origin.x) * scaleX
                let imgY = CGFloat(imgH) - (pt.y - displayRect.origin.y) * scaleY
                maskCtx.addLine(to: CGPoint(x: imgX, y: imgY))
            }
            maskCtx.strokePath()

            guard let maskCG = maskCtx.makeImage() else { return }
            let maskImg = UIImage(cgImage: maskCG)

            // 執行即時泊松邊緣擴散 Inpaint
            let erased = AIInpainter.shared.inpaint(image: snapshotImage, maskImage: maskImg)

            await MainActor.run {
                self.currentImage = erased
                self.isErasingStroke = false
            }
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
                    if undoStack.isEmpty {
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
                        if let prev = undoStack.popLast() {
                            redoStack.append(currentImage)
                            currentImage = prev
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(undoStack.isEmpty ? Color.gray.opacity(0.25) : Color.gray.opacity(0.45), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(undoStack.isEmpty ? Color.gray.opacity(0.3) : Color(red: 0.15, green: 0.15, blue: 0.15))
                        }
                    }
                    .disabled(undoStack.isEmpty)

                    // 重做 (Redo) 圓環按鈕
                    Button(action: {
                        if let next = redoStack.popLast() {
                            undoStack.append(currentImage)
                            currentImage = next
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(redoStack.isEmpty ? Color.gray.opacity(0.25) : Color.gray.opacity(0.45), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(redoStack.isEmpty ? Color.gray.opacity(0.3) : Color(red: 0.15, green: 0.15, blue: 0.15))
                        }
                    }
                    .disabled(redoStack.isEmpty)
                }

                Spacer()

                // 右側：儲存按鈕 (有擦除時點亮綠色，無擦除時呈淺灰置灰)
                Button(action: {
                    onApply(currentImage)
                }) {
                    Text("儲存")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(undoStack.isEmpty ? Color(white: 0.78) : Color(red: 0.13, green: 0.62, blue: 0.48))
                }
                .disabled(undoStack.isEmpty)
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
