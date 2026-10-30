import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 復刻圖一：單頁文件檢視、OCR 辨識與底部影像後處理工具頁面
/// 整合 OpenScan 6 種濾鏡即時切換列、手動放大鏡裁剪與 PDF 匯出
public struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    private enum ActiveDetailModal: Identifiable {
        case pdfExport
        case ocrResult
        case jpgShare(URL)

        var id: String {
            switch self {
            case .pdfExport:
                return "pdfExport"
            case .ocrResult:
                return "ocrResult"
            case .jpgShare(let url):
                return "jpgShare_\(url.absoluteString)"
            }
        }
    }

    @State private var showingFilterSelector: Bool = false
    @State private var showingAISelector: Bool = false
    @State private var showingLoupeCropView: Bool = false
    @State private var showingExportActionSheet: Bool = false
    @State private var activeModal: ActiveDetailModal? = nil
    @State private var toastMessage: String? = nil
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

                    Button(action: { showingExportActionSheet = true }) {
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
                                        activeModal = .ocrResult
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

                    // Toast 訊息提示浮層
                    if let message = toastMessage {
                        VStack {
                            Spacer()
                            Text(message)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.85))
                                .clipShape(Capsule())
                                .padding(.bottom, 72)
                                .transition(.opacity.combined(with: .scale))
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

                // 3.1 AI 旗艦修復橫列 (極致全開 / 展平 / 消陰影 / 去模糊 / 消手指 / 除筆跡)
                #if canImport(UIKit)
                if showingAISelector {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // 1. 一鍵極致全開 (Ultra Scan)
                            Button(action: {
                                Task {
                                    await viewModel.applyUltraScan()
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "wand.and.stars.inverse")
                                        .font(.system(size: 19, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 46, height: 46)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color(red: 0.98, green: 0.65, blue: 0.22), Color(red: 0.95, green: 0.42, blue: 0.21)]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .clipShape(Circle())
                                        .shadow(color: Color.orange.opacity(0.35), radius: 4, y: 2)

                                    Text("極致全開")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.orange)
                                }
                            }
                            .disabled(viewModel.isProcessingCapture || viewModel.pageCount == 0)

                            // 2. 25x25 自由曲面展平
                            aiFeatureButton(title: "曲面展平", icon: "arrow.left.and.right.square") {
                                await viewModel.applyDewarp()
                            }

                            // 3. 手機陰影均勻化消除
                            aiFeatureButton(title: "消除陰影", icon: "sun.max.fill") {
                                await viewModel.applyShadowRemoval()
                            }

                            // 4. 文字清晰去模糊
                            aiFeatureButton(title: "文字銳化", icon: "sparkles.rectangle.stack") {
                                await viewModel.applyDeblur()
                            }

                            // 5. 邊緣手指抹除
                            aiFeatureButton(title: "手指抹除", icon: "hand.raised.slash") {
                                await viewModel.applyFingerRemoval()
                            }

                            // 6. 手寫筆跡消除
                            aiFeatureButton(title: "清除筆跡", icon: "pencil.slash") {
                                await viewModel.applyHandwritingRemoval()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color(white: 0.98))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #endif

                Divider()

                // 4. 底部功能操作列
                HStack(spacing: 0) {
                    bottomToolButton(title: "分享/匯出", icon: "square.and.arrow.up") {
                        showingExportActionSheet = true
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
                                activeModal = .ocrResult
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
        .actionSheet(isPresented: $showingExportActionSheet) {
            ActionSheet(
                title: Text("匯出與分享"),
                message: Text("請選擇檔案格式或儲存方式"),
                buttons: [
                    .default(Text("📄 匯出 PDF 文件")) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activeModal = .pdfExport
                        }
                    },
                    .default(Text("🖼️ 儲存成 .jpg 檔 (儲存至相簿)")) {
                        Task {
                            let result = await viewModel.saveCurrentPageToPhotos()
                            switch result {
                            case .success:
                                showToast("✅ 已成功將頁面儲存為 .jpg 至相簿！")
                            case .failure(let err):
                                showToast("❌ \(err)")
                            }
                        }
                    },
                    .default(Text("📤 分享當前頁 .jpg 檔案")) {
                        Task {
                            if let url = await viewModel.exportCurrentPageAsJPEGFile() {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    activeModal = .jpgShare(url)
                                }
                            } else {
                                showToast("❌ 生成分享 JPG 檔案失敗")
                            }
                        }
                    },
                    .default(Text("📚 批次儲存全部 \(viewModel.pageCount) 頁為 .jpg 到相簿")) {
                        Task {
                            let (success, total, err) = await viewModel.saveAllPagesToPhotos()
                            if let err = err {
                                showToast("❌ \(err)")
                            } else {
                                showToast("✅ 已批次將 \(success)/\(total) 頁儲存為 .jpg 至相簿！")
                            }
                        }
                    },
                    .cancel(Text("取消"))
                ]
            )
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .pdfExport:
                PDFExportSheet(
                    pages: viewModel.pages,
                    store: viewModel.pageStore,
                    defaultPrefix: viewModel.currentFolder
                )
            case .ocrResult:
                OCRResultSheet(
                    text: viewModel.lastOCRText ?? "",
                    onCopy: {
                        UIPasteboard.general.string = viewModel.lastOCRText
                    }
                )
            case .jpgShare(let url):
                ActivityView(activityItems: [url])
            }
        }
        #endif
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                toastMessage = nil
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
        .disabled(viewModel.pageCount == 0 && icon != "arrow.clockwise")
        .opacity(viewModel.pageCount == 0 && icon != "arrow.clockwise" ? 0.35 : 1)
    }

    @ViewBuilder
    private func aiFeatureButton(title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                    .clipShape(Circle())
                    .shadow(color: Color(red: 0.22, green: 0.72, blue: 0.62).opacity(0.3), radius: 4, y: 2)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .disabled(viewModel.isProcessingCapture || viewModel.pageCount == 0)
    }
}

#if canImport(UIKit)
/// OCR 辨識結果檢視（可全選複製）
public struct OCRResultSheet: View {
    public let text: String
    public let onCopy: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(text: String, onCopy: @escaping () -> Void = {}) {
        self.text = text
        self.onCopy = onCopy
    }

    public init(ocrText: String) {
        self.text = ocrText
        self.onCopy = {
            #if canImport(UIKit)
            UIPasteboard.general.string = ocrText
            #endif
        }
    }

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
