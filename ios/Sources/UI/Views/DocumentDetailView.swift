import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 復刻圖一：單頁文件檢視、OCR 辨識與底部 6 大影像後處理工具頁面
public struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            // 背景白底 (對齊圖一)
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 頂部導航列 (對齊圖一：< 相機、182 / 183 文件夾、•••)
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("相機")
                                .font(.system(size: 17, weight: .regular))
                        }
                        .foregroundColor(.black)
                    }

                    Spacer()

                    Text("\(viewModel.capturedPageCount) / \(max(viewModel.capturedPageCount, 1)) \(viewModel.currentFolder)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)

                Divider()

                // 2. 中央區域：文件大圖展示與右側姿態水印
                ZStack {
                    Color(white: 0.96)

                    if let image = viewModel.lastCapturedImage {
                        #if canImport(UIKit)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            .padding(16)
                        #endif
                    } else {
                        // 範例表格模擬圖 (如圖一中冷氣開關記錄表)
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
                                .overlay(
                                    VStack {
                                        Text("冷氣開關記錄表 (示範文件)")
                                            .font(.headline)
                                            .foregroundColor(.black.opacity(0.8))
                                            .padding(.top, 24)

                                        Spacer()

                                        Image(systemName: "doc.text")
                                            .font(.system(size: 64))
                                            .foregroundColor(.gray.opacity(0.4))

                                        Spacer()
                                    }
                                )
                                .padding(24)
                        }
                    }

                    // 右側：十字方向姿態儀
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.12))
                                    .frame(width: 48, height: 48)

                                Image(systemName: "plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(.black.opacity(0.3))
                            }
                            .padding(.trailing, 16)
                            .padding(.bottom, 80)
                        }
                    }

                    // 懸浮「辨識文字」按鈕 (對齊圖一中下方深青色膠囊按鈕)
                    VStack {
                        Spacer()
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 15, weight: .bold))
                                Text("辨識文字")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.22, green: 0.72, blue: 0.62).opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(.bottom, 20)
                    }
                }

                Divider()

                // 3. 底部 6 大功能操作列 (分享、裁剪、人工智慧增強器、簽名、重新掃描、刪除)
                HStack(spacing: 0) {
                    bottomToolButton(title: "分享", icon: "square.and.arrow.up") {}
                    Spacer()
                    bottomToolButton(title: "裁剪", icon: "crop") {}
                    Spacer()
                    bottomToolButton(title: "人工智慧\n增強器", icon: "wand.and.stars") {}
                    Spacer()
                    bottomToolButton(title: "簽名", icon: "pencil.tip.crop.circle") {}
                    Spacer()
                    bottomToolButton(title: "重新掃描", icon: "arrow.clockwise") {}
                    Spacer()
                    bottomToolButton(title: "刪除", icon: "trash") {
                        if viewModel.capturedPageCount > 0 {
                            viewModel.capturedPageCount -= 1
                        }
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
            }
        }
    }

    @ViewBuilder
    private func bottomToolButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(height: 24)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(minWidth: 46)
        }
    }
}
