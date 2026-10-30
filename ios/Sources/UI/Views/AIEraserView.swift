import SwiftUI

#if canImport(UIKit)
import UIKit

/// 1:1 復刻原廠「AI 塗鴉橡皮擦」互動編輯視窗 (AIEraserView)
/// 支援手指塗抹標記瑕疵、筆刷粗細切換、復原 (Undo) 與一鍵智慧無痕修補 (Inpainting)
public struct AIEraserView: View {
    public let sourceImage: UIImage
    public let onApply: (UIImage) -> Void
    public let onCancel: () -> Void

    @State private var lines: [DoodleLine] = []
    @State private var currentLine: DoodleLine? = nil
    @State private var brushSize: CGFloat = 28
    @State private var isProcessing: Bool = false
    @State private var imageDisplaySize: CGSize = .zero

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
            // 背景深黑
            Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 頂部導航工具列
                topBar

                // 2. 中央畫布取景與塗抹手勢區
                GeometryReader { geo in
                    ZStack {
                        // 原始圖片
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFit()
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

                        // 塗抹路徑預覽 (半透明翡翠綠筆觸，原廠經典效果)
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
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if currentLine == nil {
                                    currentLine = DoodleLine(points: [value.location], lineWidth: brushSize)
                                } else {
                                    currentLine?.points.append(value.location)
                                }
                            }
                            .onEnded { _ in
                                if let finished = currentLine {
                                    lines.append(finished)
                                    currentLine = nil
                                }
                            }
                    )
                }

                // 3. 底部筆刷與工具列
                bottomBar
            }

            // 4. 運算中進度遮罩
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                        Text("AI 塗鴉擦除修復中...")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color(white: 0.2, opacity: 0.95))
                    .cornerRadius(16)
                }
            }
        }
    }

    // MARK: - 頂部工具列

    private var topBar: some View {
        HStack {
            Button("取消") {
                onCancel()
            }
            .font(.system(size: 16))
            .foregroundColor(.white)

            Spacer()

            Text("AI 塗鴉橡皮擦")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // 復原 (Undo)
            Button(action: {
                if !lines.isEmpty {
                    lines.removeLast()
                }
            }) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(lines.isEmpty ? .gray : .white)
            }
            .disabled(lines.isEmpty)
            .padding(.trailing, 8)

            // 完成按鈕
            Button(action: {
                performInpaint()
            }) {
                Text("完成")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.08, green: 0.78, blue: 0.44))
                    .cornerRadius(14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
    }

    // MARK: - 底部控制列

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // 提示文案
            Text(lines.isEmpty ? "請用手指直接塗抹想要擦除的污漬、手指或印章" : "已標記 \(lines.count) 處區域，點擊「完成」即可進行 AI 擦除")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(lines.isEmpty ? .gray : Color(red: 0.16, green: 0.85, blue: 0.55))

            HStack(spacing: 24) {
                // 筆刷粗細快速切換
                ForEach([
                    ("細", CGFloat(16)),
                    ("中", CGFloat(28)),
                    ("粗", CGFloat(48))
                ], id: \.0) { name, size in
                    Button(action: {
                        brushSize = size
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(brushSize == size ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.white.opacity(0.6))
                                .frame(width: size / 2.5, height: size / 2.5)

                            Text(name)
                                .font(.system(size: 14, weight: brushSize == size ? .bold : .regular))
                                .foregroundColor(brushSize == size ? .white : .gray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(brushSize == size ? Color.white.opacity(0.15) : Color.clear)
                        .cornerRadius(12)
                    }
                }

                Spacer()

                // 自動抹除手指捷徑
                Button(action: {
                    performAutoFingerRemoval()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 13))
                        Text("自動消手指")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
    }

    // MARK: - 核心運算

    private func performInpaint() {
        guard !lines.isEmpty else {
            // 沒有塗抹則直接返回原圖
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
            let scale = max(scaleX, scaleY)

            // 建立黑白遮罩 Bitmap (黑底白線)
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

            // 黑色背景
            maskContext.setFillColor(gray: 0.0, alpha: 1.0)
            maskContext.fill(CGRect(x: 0, y: 0, width: imgW, height: imgH))

            // 白色筆觸
            maskContext.setStrokeColor(gray: 1.0, alpha: 1.0)
            maskContext.setLineCap(.round)
            maskContext.setLineJoin(.round)

            for line in capturedLines {
                guard let first = line.points.first else { continue }
                maskContext.setLineWidth(line.lineWidth * scale)
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
