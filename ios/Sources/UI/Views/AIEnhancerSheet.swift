import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 1:1 原廠「人工智慧增強器」底部抽屜彈窗 (AIEnhancerSheet)
/// 採用 2x2 精美大圓角卡片式排版，完美復刻原廠視覺插圖與交互回饋
public struct AIEnhancerSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let onSelect: (ScannerViewModel.AIEnhancerType) -> Void

    public init(onSelect: @escaping (ScannerViewModel.AIEnhancerType) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 頂部拖曳把手
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.8))
                    .frame(width: 36, height: 5)
                Spacer()
            }
            .padding(.top, 8)

            // 標題
            Text("人工智慧增強器")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.12))
                .padding(.horizontal, 20)

            // 2x2 增強器矩陣
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                // 1. 擦除筆記
                enhancerCard(
                    title: "擦除筆記",
                    crown: true,
                    illustration: AnyView(handwritingIllustration)
                ) {
                    onSelect(.handwriting)
                    dismiss()
                }

                // 2. 模糊校正
                enhancerCard(
                    title: "模糊校正",
                    crown: false,
                    illustration: AnyView(deblurIllustration)
                ) {
                    onSelect(.deblur)
                    dismiss()
                }

                // 3. 拉直
                enhancerCard(
                    title: "拉直",
                    crown: true,
                    illustration: AnyView(dewarpIllustration)
                ) {
                    onSelect(.dewarp)
                    dismiss()
                }

                // 4. AI 橡皮擦 (塗鴉與手指抹除)
                enhancerCard(
                    title: "AI 橡皮擦",
                    crown: false,
                    illustration: AnyView(eraserIllustration)
                ) {
                    onSelect(.eraser)
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.white)
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 單一功能卡片

    private func enhancerCard(
        title: String,
        crown: Bool,
        illustration: AnyView,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // 標題列
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.16, green: 0.55, blue: 0.45))

                    if crown {
                        Text("👑")
                            .font(.system(size: 12))
                    }

                    Spacer()
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                Spacer()

                // 插圖容器
                illustration
                    .frame(height: 85)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
            }
            .frame(height: 140)
            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.03), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 向量插圖 1：擦除筆記

    private var handwritingIllustration: some View {
        ZStack {
            // 紙張本體
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 70, height: 65)
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)

            // 紙張灰色橫線
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.88))
                    .frame(width: 50, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.88))
                    .frame(width: 50, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.88))
                    .frame(width: 50, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(white: 0.88))
                    .frame(width: 50, height: 2)
            }

            // 被擦除的紅色筆跡
            Path { path in
                path.move(to: CGPoint(x: 20, y: 38))
                path.addCurve(
                    to: CGPoint(x: 55, y: 30),
                    control1: CGPoint(x: 30, y: 46),
                    control2: CGPoint(x: 45, y: 22)
                )
            }
            .stroke(Color.red.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 3]))

            // 綠色擦拭筆
            Image(systemName: "pencil")
                .font(.system(size: 26))
                .foregroundColor(Color(red: 0.16, green: 0.65, blue: 0.52))
                .rotationEffect(.degrees(-45))
                .offset(x: -12, y: 6)
        }
    }

    // MARK: - 向量插圖 2：模糊校正

    private var deblurIllustration: some View {
        ZStack {
            // 文檔本體
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 65, height: 68)
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)

            // 左右對比文檔條
            HStack(spacing: 3) {
                // 左邊模糊條
                VStack(spacing: 6) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.35))
                            .frame(width: 22, height: 3)
                            .blur(radius: 0.7)
                    }
                }

                // 中間薄荷綠垂直分界線
                Rectangle()
                    .fill(Color(red: 0.16, green: 0.65, blue: 0.52))
                    .frame(width: 2, height: 48)

                // 右邊銳利條
                VStack(spacing: 6) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(red: 0.16, green: 0.65, blue: 0.52).opacity(0.75))
                            .frame(width: 22, height: 3)
                    }
                }
            }

            // 右下角金色星星
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("✨")
                        .font(.system(size: 14))
                        .offset(x: 8, y: -4)
                }
            }
            .frame(width: 70, height: 70)
        }
    }

    // MARK: - 向量插圖 3：拉直 (曲面展開)

    private var dewarpIllustration: some View {
        ZStack {
            // 彎曲書本與拉直對比
            HStack(spacing: 8) {
                // 左側翹曲書本 (彎曲波紋)
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                        .frame(width: 32, height: 36)
                        .rotationEffect(.degrees(-8))

                    // 彎曲線
                    Path { path in
                        path.move(to: CGPoint(x: 4, y: 18))
                        path.addQuadCurve(to: CGPoint(x: 28, y: 18), control: CGPoint(x: 16, y: 8))
                    }
                    .stroke(Color.teal.opacity(0.7), lineWidth: 2)
                }

                // 右側拉直完成之平整紙張
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white)
                    .frame(width: 38, height: 50)
                    .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                    .overlay(
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 26, height: 2.5)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 26, height: 2.5)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 26, height: 2.5)
                        }
                    )
            }

            // 中間黃色魔法星星
            Text("✨")
                .font(.system(size: 12))
                .offset(x: 18, y: -18)
        }
    }

    // MARK: - 向量插圖 4：AI 橡皮擦 (去除陰影/手指)

    private var eraserIllustration: some View {
        ZStack {
            // 文檔本體
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 65, height: 68)
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 2)
                .overlay(
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 44, height: 3)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 36, height: 3)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 40, height: 3)
                    }
                )

            // 斜放的立體雙色橡皮擦
            ZStack {
                HStack(spacing: 0) {
                    // 白色部分
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.92))
                        .frame(width: 14, height: 18)
                    // 墨綠色握柄部分
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.16, green: 0.65, blue: 0.52))
                        .frame(width: 16, height: 18)
                }
                .rotationEffect(.degrees(-35))
                .shadow(color: Color.black.opacity(0.15), radius: 2, x: 1, y: 1)
            }
            .offset(x: 14, y: -20)

            // 右下角閃亮星光
            Text("✨")
                .font(.system(size: 12))
                .offset(x: 6, y: -8)
        }
    }
}
