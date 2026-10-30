import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 復刻圖一：單頁文件檢視、OCR 辨識與底部 6 大影像後處理工具頁面
/// 整合 OpenScan 6 種濾鏡即時切換列、手動放大鏡裁剪與 PDF 匯出
public struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    @State private var showingFilterSelector: Bool = false
    @State private var showingLoupeCropView: Bool = false
    @State private var showingPDFSheet: Bool = false
    @State private var activeDocument: DetectedDocument = DetectedDocument(
        topLeft: CGPoint(x: 0.05, y: 0.05),
        topRight: CGPoint(x: 0.95, y: 0.05),
        bottomRight: CGPoint(x: 0.95, y: 0.95),
        bottomLeft: CGPoint(x: 0.05, y: 0.95),
        confidence: 1.0
    )

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            // 背景白底
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 頂部導航列 (< 相機、頁數 / 資料夾、PDF 匯出)
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

                    Button(action: {
                        showingPDFSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)

                Divider()

                // 2. 中央區域：文件大圖展示與狀態
                ZStack {
                    Color(white: 0.96)

                    #if canImport(UIKit)
                    if let image = viewModel.lastCapturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            .padding(16)
                    } else {
                        // 範例表格模擬圖
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
                    #endif

                    // 懸浮「辨識文字」按鈕
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

                // 3. 濾鏡切換選擇橫列 (對齊 OpenScan 6 種濾鏡模式)
                #if canImport(UIKit)
                if showingFilterSelector {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(DocumentFilterMode.allCases) { mode in
                                Button(action: {
                                    viewModel.updateFilterMode(mode)
                                }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: mode.iconName)
                                            .font(.system(size: 18))
                                            .foregroundColor(viewModel.selectedFilterMode == mode ? .white : .black)
                                            .frame(width: 40, height: 40)
                                            .background(
                                                viewModel.selectedFilterMode == mode ?
                                                Color(red: 0.22, green: 0.72, blue: 0.62) :
                                                Color(white: 0.92)
                                            )
                                            .clipShape(Circle())

                                        Text(mode.rawValue)
                                            .font(.system(size: 11, weight: viewModel.selectedFilterMode == mode ? .bold : .regular))
                                            .foregroundColor(.black)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color.white)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #endif

                Divider()

                // 4. 底部 6 大功能操作列 (分享、裁剪、人工智慧增強器、簽名、重新掃描、刪除)
                HStack(spacing: 0) {
                    bottomToolButton(title: "分享", icon: "square.and.arrow.up") {
                        showingPDFSheet = true
                    }
                    Spacer()
                    bottomToolButton(title: "裁剪", icon: "crop") {
                        if let currentDoc = viewModel.detectedDocument {
                            activeDocument = currentDoc
                        }
                        showingLoupeCropView = true
                    }
                    Spacer()
                    bottomToolButton(title: "增強\n濾鏡", icon: "wand.and.stars") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingFilterSelector.toggle()
                        }
                    }
                    Spacer()
                    bottomToolButton(title: "簽名", icon: "pencil.tip.crop.circle") {}
                    Spacer()
                    bottomToolButton(title: "重新掃描", icon: "arrow.clockwise") {
                        dismiss()
                    }
                    Spacer()
                    bottomToolButton(title: "刪除", icon: "trash") {
                        #if canImport(UIKit)
                        if !viewModel.capturedImages.isEmpty {
                            _ = viewModel.capturedImages.popLast()
                            viewModel.lastCapturedImage = viewModel.capturedImages.last
                        }
                        #endif
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
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showingLoupeCropView) {
            if let img = viewModel.lastRawCapturedImage ?? viewModel.lastCapturedImage {
                LoupeCropView(image: img, document: $activeDocument) { newDoc in
                    viewModel.detectedDocument = newDoc
                    if let raw = viewModel.lastRawCapturedImage {
                        let cropped = DocumentRectifier.shared.autoProcessCapture(
                            image: raw,
                            document: newDoc,
                            autoCrop: true,
                            enableDewarp: viewModel.presetCurveCorrection,
                            filterMode: viewModel.selectedFilterMode
                        )
                        viewModel.lastCapturedImage = cropped
                    }
                }
            }
        }
        .sheet(isPresented: $showingPDFSheet) {
            PDFExportSheet(
                images: viewModel.capturedImages.isEmpty ?
                    (viewModel.lastCapturedImage != nil ? [viewModel.lastCapturedImage!] : []) :
                    viewModel.capturedImages,
                defaultPrefix: viewModel.currentFolder
            )
        }
        #endif
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
