import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 1:1 像素級復刻原廠 AI 增強功能比對檢視視窗 (AIEnhanceComparisonView)
/// 支援「擦除筆記」、「模糊校正」、「拉直」三項功能。
/// 具備 Before/After 左右分割滑桿、長按比對原圖、雙指縮放平移、以及「覆蓋」/「保存為新頁面」的原廠儲存流程。
public struct AIEnhanceComparisonView: View {
    public enum Mode: String, Identifiable {
        case handwriting = "擦除筆記"
        case deblur = "模糊校正"
        case dewarp = "拉直"

        public var id: String { rawValue }

        public var processingText: String {
            switch self {
            case .handwriting: return "正在擦除手寫筆記..."
            case .deblur: return "正在校正模糊文字..."
            case .dewarp: return "正在計算 25×25 自由曲面展開..."
            }
        }
    }

    public let mode: Mode
    public let beforeImage: UIImage
    public let onOverwrite: (UIImage) -> Void
    public let onSaveAsNew: (UIImage) -> Void
    public let onCancel: () -> Void

    @State private var afterImage: UIImage? = nil
    @State private var isProcessing: Bool = true
    @State private var splitRatio: CGFloat = 0.5 // 0.0 ~ 1.0 左右分割線位置
    @State private var isPressingPeekOriginal: Bool = false
    @State private var showingSaveConfirmation: Bool = false

    // 縮放平移狀態
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    public init(
        mode: Mode,
        beforeImage: UIImage,
        onOverwrite: @escaping (UIImage) -> Void,
        onSaveAsNew: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.beforeImage = beforeImage
        self.onOverwrite = onOverwrite
        self.onSaveAsNew = onSaveAsNew
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            // 深色沉浸背景（原廠比對背景色）
            Color(red: 0.10, green: 0.10, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 頂部原廠導航列 (取消 | 標題 | 儲存)
                topNavigationBar

                // 2. 中央影像比對畫布 (支援左右分割拖曳線 + 雙指縮放)
                GeometryReader { geo in
                    ZStack {
                        if let after = afterImage {
                            comparisonCanvas(size: geo.size, after: after)
                        } else {
                            // 演算中先顯示原圖
                            Image(uiImage: beforeImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                        }

                        // 浮動提示膠囊（左右分界）
                        if afterImage != nil && !isProcessing {
                            comparisonBadges(size: geo.size)
                        }

                        // 演算中進度指示器
                        if isProcessing {
                            processingOverlay
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }

                // 3. 底部提示列（原廠長按比對說明）
                bottomHintBar
            }
        }
        .task {
            await computeEnhancedImage()
        }
        .confirmationDialog(
            "覆蓋這個頁面嗎？",
            isPresented: $showingSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("覆蓋", role: .destructive) {
                if let after = afterImage {
                    onOverwrite(after)
                }
            }
            Button("保存為新頁面") {
                if let after = afterImage {
                    onSaveAsNew(after)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("覆蓋將替換此頁面。")
        }
    }

    // MARK: - 頂部導航列

    private var topNavigationBar: some View {
        HStack {
            // 取消按鈕
            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                    Text("取消")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
            }

            Spacer()

            // 功能名稱標題
            Text(mode.rawValue)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // 儲存按鈕（原廠薄荷綠）
            Button(action: {
                showingSaveConfirmation = true
            }) {
                Text("儲存")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(
                        afterImage != nil && !isProcessing
                            ? Color(red: 0.13, green: 0.62, blue: 0.48)
                            : Color.gray.opacity(0.6)
                    )
            }
            .disabled(afterImage == nil || isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }

    // MARK: - 中央影像對比畫布

    @ViewBuilder
    private func comparisonCanvas(size: CGSize, after: UIImage) -> some View {
        ZStack {
            // 底層：處理前（Before）原始圖
            Image(uiImage: beforeImage)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)

            // 頂層：處理後（After）增強圖（由左至右依滑桿位置遮罩）
            if !isPressingPeekOriginal {
                Image(uiImage: after)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .mask(
                        HStack(spacing: 0) {
                            Spacer()
                                .frame(width: max(0, size.width * splitRatio))
                            Rectangle()
                                .fill(Color.white)
                        }
                    )
            }

            // 分割線與可拖動把手
            if !isPressingPeekOriginal {
                let dividerX = size.width * splitRatio
                ZStack {
                    // 分割白線
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: size.height)
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 0)

                    // 圓形把手按鈕
                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
                        .overlay(
                            HStack(spacing: 4) {
                                Image(systemName: "arrowtriangle.left.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(white: 0.25))
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(white: 0.25))
                            }
                        )
                }
                .position(x: dividerX, y: size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newRatio = value.location.x / size.width
                            splitRatio = min(max(newRatio, 0.05), 0.95)
                        }
                )
            }
        }
        .scaleEffect(zoomScale)
        .offset(panOffset)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastZoomScale
                    lastZoomScale = value
                    zoomScale = min(max(zoomScale * delta, 1.0), 4.0)
                }
                .onEnded { _ in
                    lastZoomScale = 1.0
                    if zoomScale <= 1.0 {
                        withAnimation(.spring()) {
                            zoomScale = 1.0
                            panOffset = .zero
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if zoomScale > 1.0 {
                        panOffset = CGSize(
                            width: lastPanOffset.width + value.translation.width,
                            height: lastPanOffset.height + value.translation.height
                        )
                    }
                }
                .onEnded { _ in
                    lastPanOffset = panOffset
                }
        )
    }

    // MARK: - 處理前 / 處理後浮動標籤

    private func comparisonBadges(size: CGSize) -> some View {
        VStack {
            HStack {
                // 左側標籤：處理前
                Text("處理前")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(6)
                    .padding(.leading, 12)

                Spacer()

                // 右側標籤：處理後
                Text("處理後")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.13, green: 0.62, blue: 0.48))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(6)
                    .padding(.trailing, 12)
            }
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - 底部說明列與長按比對

    private var bottomHintBar: some View {
        HStack {
            Spacer()

            // 長按即時檢視原圖手勢按鈕
            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                    Text(isPressingPeekOriginal ? "放開恢復處理效果" : "長按比對原圖")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .cornerRadius(20)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressingPeekOriginal {
                            isPressingPeekOriginal = true
                        }
                    }
                    .onEnded { _ in
                        isPressingPeekOriginal = false
                    }
            )

            Spacer()
        }
        .padding(.vertical, 14)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }

    // MARK: - 演算中進度遮罩

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.13, green: 0.62, blue: 0.48)))
                    .scaleEffect(1.4)

                Text(mode.processingText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(Color(white: 0.15, opacity: 0.95))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }

    // MARK: - 背景非同步影像演算

    private func computeEnhancedImage() async {
        let source = beforeImage
        let targetMode = mode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage in
            switch targetMode {
            case .handwriting:
                return HandwritingRemovalProcessor.shared.removeHandwriting(image: source)
            case .deblur:
                return DeblurProcessor.shared.deblur(image: source)
            case .dewarp:
                let grid = DynamicDewarpPredictor.shared.predictGrid(for: source)
                return MetalOffscreenDewarper.shared.dewarpImage(
                    image: source,
                    curvedGrid: grid,
                    dewarpStrength: 1.0
                ) ?? source
            }
        }.value

        await MainActor.run {
            self.afterImage = result
            self.isProcessing = false
        }
    }
}
