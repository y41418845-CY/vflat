import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 復刻圖一：單頁文件檢視、OCR 辨識與底部影像後處理工具頁面
/// 整合 OpenScan 6 種濾鏡即時切換列、手動放大鏡裁剪與 PDF 匯出
public struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    @State private var showingFilterSelector: Bool = false
    @State private var showingAISelector: Bool = false
    @State private var showingLoupeCropView: Bool = false
    @State private var showingPDFSheet: Bool = false
    @State private var showingOCRResult: Bool = false
    @State private var activeDocument: DetectedDocument = DetectedDocument(
        topLeft: CGPoint(x: 0.0, y: 0.0),
        topRight: CGPoint(x: 1.0, y: 0.0),
        bottomRight: CGPoint(x: 1.0, y: 1.0),
        bottomLeft: CGPoint(x: 0.0, y: 1.0),
        confidence: 1.0
    )

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    /// 目前檢視的頁面（永遠是佇列中的最後一頁）
    private var currentPage: ScanPage? { viewModel.pages.last }

    public var body: some View {
        ZStack {
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

                    Text(viewModel.pageCount > 0
                         ? "\(viewModel.pageCount) 頁 · \(viewModel.currentFolder)"
                         : "尚無頁面 · \(viewModel.currentFolder)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: { showingPDFSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(viewModel.pageCount > 0 ? .black : .gray.opacity(0.4))
                    }
                    .disabled(viewModel.pageCount == 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)

                Divider()

                // 2. 中央區域：文件大圖展示與狀態
                ZStack {
                    Color(white: 0.96)

                    #if canImport(UIKit)
                    if let image = viewModel.lastPreviewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            .padding(16)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 56))
                                .foregroundColor(.gray.opacity(0.45))
                            Text("回到相機拍下第一頁")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    #endif

                    // 處理中遮罩
                    if viewModel.isProcessingCapture {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                    }

                    // 懸浮「辨識文字」按鈕
                    if viewModel.pageCount > 0 {
                        VStack {
                            Spacer()
                            Button(action: {
                                Task {
                                    await viewModel.recognizeLastPageText()
                                    if viewModel.lastOCRText != nil {
                                        showingOCRResult = true
                                    }
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if viewModel.isRecognizingText {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "viewfinder")
                                            .font(.system(size: 15, weight: .bold))
                                    }
                                    Text(viewModel.isRecognizingText ? "辨識中…" : "辨識文字")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                                .clipShape(Capsule())
                                .shadow(color: Color(red: 0.22, green: 0.72, blue: 0.62).opacity(0.4), radius: 8, y: 4)
                            }
                            .disabled(viewModel.isRecognizingText)
                            .padding(.bottom, 20)
                        }
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
                                                viewModel.selectedFilterMode == mode
                                                ? Color(red: 0.22, green: 0.72, blue: 0.62)
                                                : Color(white: 0.92)
                                            )
                                            .clipShape(Circle())

                                        Text(mode.rawValue)
                                            .font(.system(size: 11, weight: viewModel.selectedFilterMode == mode ? .bold : .regular))
                                            .foregroundColor(.black)
                                    }
                                }
                                .disabled(viewModel.pageCount == 0)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color.white)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #endif

                // 3.1 AI 魔法工具橫列 (去模糊 / 消手指 / 除筆跡)
                #if canImport(UIKit)
                if showingAISelector {
                    HStack(spacing: 24) {
                        Button(action: {
                            Task {
                                await viewModel.applyDeblur()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                                    .clipShape(Circle())
                                Text("去模糊")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                        .disabled(viewModel.isProcessingCapture || viewModel.pageCount == 0)

                        Button(action: {
                            Task {
                                await viewModel.applyFingerRemoval()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "hand.raised.slash")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                                    .clipShape(Circle())
                                Text("消手指")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                        .disabled(viewModel.isProcessingCapture || viewModel.pageCount == 0)

                        Button(action: {
                            Task {
                                await viewModel.applyHandwritingRemoval()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "pencil.slash")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                                    .clipShape(Circle())
                                Text("除筆跡")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                        .disabled(viewModel.isProcessingCapture || viewModel.pageCount == 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.98))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #endif

                Divider()

                // 4. 底部功能操作列
                HStack(spacing: 0) {
                    bottomToolButton(title: "分享", icon: "square.and.arrow.up") {
                        showingPDFSheet = true
                    }
                    Spacer()
                    bottomToolButton(title: "裁剪", icon: "crop") {
                        activeDocument = currentPage?.document ?? viewModel.detectedDocument ?? activeDocument
                        showingLoupeCropView = true
                    }
                    Spacer()
                    bottomToolButton(title: "濾鏡", icon: "slider.horizontal.3") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingAISelector = false
                            showingFilterSelector.toggle()
                        }
                    }
                    Spacer()
                    bottomToolButton(title: "AI 修復", icon: "wand.and.stars") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showingFilterSelector = false
                            showingAISelector.toggle()
                        }
                    }
                    Spacer()
                    bottomToolButton(title: "文字辨識", icon: "text.viewfinder") {
                        Task {
                            await viewModel.recognizeLastPageText()
                            if viewModel.lastOCRText != nil {
                                showingOCRResult = true
                            }
                        }
                    }
                    Spacer()
                    bottomToolButton(title: "重新掃描", icon: "arrow.clockwise") {
                        viewModel.showingDocumentDetail = false
                        dismiss()
                    }
                    Spacer()
                    bottomToolButton(title: "刪除", icon: "trash") {
                        viewModel.deleteLastPage()
                        if viewModel.pageCount == 0 {
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showingLoupeCropView) {
            if let source = viewModel.lastRawPageImage
                ?? currentPage.flatMap({ viewModel.pageStore.rawImage(for: $0) })
                ?? viewModel.lastPreviewImage {
                LoupeCropView(image: source, document: $activeDocument) { newDoc in
                    viewModel.applyCrop(document: newDoc)
                }
            }
        }
        .sheet(isPresented: $showingPDFSheet) {
            PDFExportSheet(
                pages: viewModel.pages,
                store: viewModel.pageStore,
                defaultPrefix: viewModel.currentFolder
            )
        }
        .sheet(isPresented: $showingOCRResult) {
            OCRResultSheet(
                text: viewModel.lastOCRText ?? "",
                onCopy: {
                    UIPasteboard.general.string = viewModel.lastOCRText
                }
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
        .disabled(viewModel.pageCount == 0 && icon != "arrow.clockwise")
        .opacity(viewModel.pageCount == 0 && icon != "arrow.clockwise" ? 0.35 : 1)
    }
}

#if canImport(UIKit)
/// OCR 辨識結果檢視（可全選複製）
public struct OCRResultSheet: View {
    public let text: String
    public let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationView {
            ScrollView {
                Text(text.isEmpty ? "未辨識到文字" : text)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .navigationTitle("辨識結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("複製") {
                        onCopy()
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
    }
}
#endif
