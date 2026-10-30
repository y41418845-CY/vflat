import SwiftUI

#if canImport(UIKit)
import UIKit
import Photos
#endif

/// 縮放圖片檢視器元件，支援雙指放大縮小與雙擊還原
public struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    public init(image: UIImage) {
        self.image = image
    }

    public var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 1.0), 4.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale <= 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.0
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// 原廠 1:1 左右水平翻頁閱讀器與全功能後處理中心 (PageSwipeViewController)
public struct PageSwipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel
    let initialPageId: UUID?

    @State private var selectedIndex: Int = 0
    @State private var showingFilterSelector: Bool = false
    @State private var showingAISelector: Bool = false
    @State private var showingLoupeCropView: Bool = false
    @State private var showingExportActionSheet: Bool = false
    @State private var showingThumbnailStrip: Bool = false
    @State private var toastMessage: String? = nil

    private enum ActiveModal: Identifiable {
        case pdfExport
        case ocrResult(String)
        case jpgShare(URL)
        case moveFolder(UUID)

        var id: String {
            switch self {
            case .pdfExport:
                return "pdfExport"
            case .ocrResult(let text):
                return "ocrResult_\(text.hashValue)"
            case .jpgShare(let url):
                return "jpgShare_\(url.absoluteString)"
            case .moveFolder(let id):
                return "moveFolder_\(id.uuidString)"
            }
        }
    }
    @State private var activeModal: ActiveModal? = nil

    public init(viewModel: ScannerViewModel, initialPageId: UUID? = nil) {
        self.viewModel = viewModel
        self.initialPageId = initialPageId
    }

    /// 當前資料夾過濾後的頁面清單
    private var pages: [ScanPage] {
        let folderPages = viewModel.pageStore.pages(in: viewModel.pageStore.currentFolderId)
        return folderPages.isEmpty ? viewModel.pages : folderPages
    }

    private var currentPage: ScanPage? {
        guard !pages.isEmpty, selectedIndex >= 0, selectedIndex < pages.count else { return nil }
        return pages[selectedIndex]
    }

    public var body: some View {
        ZStack {
            // 背景深色（原廠檢視器背景）
            Color(red: 0.10, green: 0.10, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 頂部導航列
                topNavigationBar

                // 2. 中央水平翻頁 TabView
                centralPagingView

                // 3. 底部快捷縮圖導覽條 (可切換顯示/隱藏)
                if showingThumbnailStrip {
                    thumbnailStripView
                }

                // 4. 底部原廠 5 大影像編輯工具列
                bottomToolBar
            }

            // 5. AI 後處理進度遮罩
            if viewModel.isProcessingCapture {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                        Text("AI 增強處理中...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color(white: 0.2, opacity: 0.9))
                    .cornerRadius(16)
                }
            }

            // 6. Toast 提示膠囊
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(24)
                        .padding(.bottom, 90)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeInOut(duration: 0.25), value: toastMessage)
            }
        }
        .onAppear {
            if let targetId = initialPageId,
               let foundIndex = pages.firstIndex(where: { $0.id == targetId }) {
                selectedIndex = foundIndex
            } else if !pages.isEmpty {
                selectedIndex = max(0, min(selectedIndex, pages.count - 1))
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .pdfExport:
                PDFExportSheet(viewModel: viewModel)
            case .ocrResult(let text):
                OCRResultSheet(
                    text: text,
                    onCopy: {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = text
                        showToast("已複製文字至剪貼簿")
                        #endif
                    }
                )
            case .jpgShare(let fileURL):
                ActivityView(activityItems: [fileURL])
            case .moveFolder(let pageId):
                MoveFolderSheet(viewModel: viewModel, pageIds: [pageId])
            }
        }
        .sheet(isPresented: $showingLoupeCropView) {
            if let page = currentPage, let image = viewModel.pageStore.rawImage(for: page) ?? viewModel.pageStore.image(for: page) {
                LoupeCropView(
                    sourceImage: image,
                    initialDocument: page.document ?? DetectedDocument(
                        topLeft: CGPoint(x: 0, y: 0),
                        topRight: CGPoint(x: 1, y: 0),
                        bottomRight: CGPoint(x: 1, y: 1),
                        bottomLeft: CGPoint(x: 0, y: 1),
                        confidence: 1.0
                    ),
                    onApply: { updatedDoc in
                        showingLoupeCropView = false
                        Task {
                            await applyCrop(document: updatedDoc, for: page)
                        }
                    },
                    onCancel: {
                        showingLoupeCropView = false
                    }
                )
            }
        }
        .confirmationDialog("匯出與分享", isPresented: $showingExportActionSheet, titleVisibility: .visible) {
            Button("儲存此頁至相簿 (.jpg)") {
                saveCurrentPageToPhotos()
            }
            Button("儲存全部頁面至相簿 (.jpg)") {
                saveAllPagesToPhotos()
            }
            Button("分享此頁 JPEG 實體檔案") {
                shareCurrentPageJPG()
            }
            Button("匯出為 PDF 文件...") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    activeModal = .pdfExport
                }
            }
            if let page = currentPage {
                Button("移動此頁至其他資料夾...") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeModal = .moveFolder(page.id)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .actionSheet(isPresented: $showingAISelector) {
            ActionSheet(
                title: Text("AI 魔法修復工具 (旗艦全功能無限制)"),
                message: Text("採用 Clean Room 純原生數學演算法與 Metal 著色器，離線保證隱私"),
                buttons: [
                    .default(Text("🌟 極致全開 (Ultra Scan)")) {
                        runAI(.ultra)
                    },
                    .default(Text("☀️ 手機陰影消除 (Shadow Removal)")) {
                        runAI(.shadow)
                    },
                    .default(Text("🖐️ 邊緣手指抹除 (Finger Removal)")) {
                        runAI(.finger)
                    },
                    .default(Text("✍️ 手寫筆跡消除 (Handwriting Removal)")) {
                        runAI(.handwriting)
                    },
                    .default(Text("🔍 文字清晰去模糊 (Deblur)")) {
                        runAI(.deblur)
                    },
                    .default(Text("📖 25×25 自由曲面展開 (Dewarp)")) {
                        runAI(.dewarp)
                    },
                    .cancel(Text("取消"))
                ]
            )
        }
    }

    // MARK: - 頂部導航列

    private var topNavigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 16))
                }
                .foregroundColor(.white)
            }

            Spacer()

            // 頁碼指示（點擊展開/收合縮圖條）
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingThumbnailStrip.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Text(pages.isEmpty ? "無頁面" : "\(selectedIndex + 1) / \(pages.count)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: showingThumbnailStrip ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(14)
            }

            Spacer()

            // 右側功能鈕：OCR 與分享
            HStack(spacing: 16) {
                Button(action: { recognizeCurrentPageText() }) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 20))
                        .foregroundColor(currentPage != nil ? .white : .gray)
                }
                .disabled(currentPage == nil)

                Button(action: { showingExportActionSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundColor(currentPage != nil ? .white : .gray)
                }
                .disabled(currentPage == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }

    // MARK: - 中央左右翻頁 TabView

    private var centralPagingView: some View {
        ZStack {
            if pages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("資料夾內尚無任何掃描頁面")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(pages.indices, id: \.self) { index in
                        let page = pages[index]
                        if let img = viewModel.pageStore.image(for: page) {
                            ZoomableImageView(image: img)
                                .tag(index)
                                .padding(.horizontal, 8)
                        } else {
                            ProgressView()
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部快捷縮圖導覽列

    private var thumbnailStripView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        let page = pages[index]
                        let isSelected = (index == selectedIndex)
                        Button(action: {
                            selectedIndex = index
                        }) {
                            ZStack(alignment: .bottomTrailing) {
                                if let thumb = viewModel.pageStore.thumbnail(for: page, maxPixel: 160) {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 70)
                                        .clipped()
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.clear, lineWidth: 2.5)
                                        )
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 70)
                                        .cornerRadius(6)
                                }

                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.75))
                                    .cornerRadius(4)
                                    .padding(3)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.14, green: 0.14, blue: 0.15))
            .onAppear {
                scrollProxy.scrollTo(selectedIndex, anchor: .center)
            }
            .onChange(of: selectedIndex) { newIndex in
                withAnimation {
                    scrollProxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - 底部 5 大工具列 (對齊原廠)

    private var bottomToolBar: some View {
        VStack(spacing: 0) {
            // 濾鏡切換子選單（點擊濾鏡按鈕時展開）
            if showingFilterSelector {
                filterSelectorBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                // 1. 裁剪 Crop
                toolButton(title: "裁剪", icon: "crop") {
                    showingLoupeCropView = true
                }

                // 2. AI 增強
                toolButton(title: "AI 增強", icon: "sparkles", isHighlighted: true) {
                    showingAISelector = true
                }

                // 3. 色彩濾鏡
                toolButton(title: "濾鏡", icon: "slider.horizontal.3") {
                    withAnimation(.spring()) {
                        showingFilterSelector.toggle()
                    }
                }

                // 4. 文字辨識 OCR
                toolButton(title: "文字", icon: "text.magnifyingglass") {
                    recognizeCurrentPageText()
                }

                // 5. 刪除
                toolButton(title: "刪除", icon: "trash", isDestructive: true) {
                    deleteCurrentPage()
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        }
    }

    private func toolButton(
        title: String,
        icon: String,
        isHighlighted: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(
                isDestructive ? Color.red.opacity(0.85) :
                isHighlighted ? Color(red: 0.08, green: 0.78, blue: 0.44) :
                Color.white.opacity(0.9)
            )
        }
        .disabled(currentPage == nil && !isDestructive)
    }

    // MARK: - 濾鏡橫向快速選擇列

    private var filterSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DocumentFilterMode.allCases, id: \.self) { mode in
                    let isCurrent = (currentPage?.filterMode == mode)
                    Button(action: {
                        applyFilter(mode)
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isCurrent ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(red: 0.15, green: 0.15, blue: 0.16))
    }

    // MARK: - 動作邏輯 (AI, 濾鏡, 裁剪, 匯出)

    private func applyFilter(_ mode: DocumentFilterMode) {
        guard let page = currentPage,
              let raw = viewModel.pageStore.rawImage(for: page) ?? viewModel.pageStore.image(for: page) else { return }
        Task {
            let processed = DocumentRectifier.shared.applyFilter(mode, to: raw)
            await viewModel.pageStore.updateProcessed(id: page.id, image: processed, filterMode: mode)
            showToast("已套用 \(mode.rawValue)")
        }
    }

    private func applyCrop(document: DetectedDocument, for page: ScanPage) async {
        guard let raw = viewModel.pageStore.rawImage(for: page) ?? viewModel.pageStore.image(for: page) else { return }
        let cropped = DocumentRectifier.shared.correctPerspective(image: raw, document: document) ?? raw
        let filtered = DocumentRectifier.shared.applyFilter(page.filterMode, to: cropped)
        await viewModel.pageStore.updateProcessed(id: page.id, image: filtered, filterMode: page.filterMode)
        showToast("裁剪與幾何透視已更新")
    }

    private func runAI(_ type: ScannerViewModel.AIEnhancerType) {
        guard let page = currentPage else { return }
        Task {
            await viewModel.runAIEnhancer(type: type, targetPageID: page.id)
            showToast("AI \(type.rawValue) 已完成")
        }
    }

    private func recognizeCurrentPageText() {
        guard let page = currentPage else { return }
        if let existing = page.ocrText, !existing.isEmpty {
            activeModal = .ocrResult(existing)
            return
        }
        guard let image = viewModel.pageStore.image(for: page) else { return }
        Task {
            let recognized = await OCRService.shared.recognizeText(in: image) ?? ""
            let resultText = recognized.isEmpty ? "未偵測到清晰文字" : recognized
            viewModel.pageStore.updateOCR(id: page.id, text: resultText)
            activeModal = .ocrResult(resultText)
        }
    }

    private func deleteCurrentPage() {
        guard let page = currentPage else { return }
        let oldIndex = selectedIndex
        viewModel.pageStore.delete(id: page.id)
        if pages.isEmpty {
            dismiss()
        } else {
            selectedIndex = max(0, min(oldIndex, pages.count - 1))
        }
        showToast("已移至垃圾桶 (保留 30 天)")
    }

    private func saveCurrentPageToPhotos() {
        guard let page = currentPage, let image = viewModel.pageStore.image(for: page) else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.showToast("儲存失敗：請至系統設定開啟相片寫入權限")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.showToast("已成功將第 \(self.selectedIndex + 1) 頁儲存至相簿")
                        } else {
                            self.showToast("儲存至相簿失敗：\(error?.localizedDescription ?? "未知錯誤")")
                        }
                    }
                }
            }
        }
    }

    private func saveAllPagesToPhotos() {
        let allPages = pages
        guard !allPages.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.showToast("儲存失敗：請至系統設定開啟相片寫入權限")
                    return
                }
                Task {
                    var successCount = 0
                    for page in allPages {
                        if let img = self.viewModel.pageStore.image(for: page) {
                            let ok = await withCheckedContinuation { continuation in
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                                }) { ok, _ in
                                    continuation.resume(returning: ok)
                                }
                            }
                            if ok { successCount += 1 }
                        }
                    }
                    self.showToast("已將 \(successCount) 頁完整存入相簿")
                }
            }
        }
    }

    private func shareCurrentPageJPG() {
        guard let page = currentPage else { return }
        let url = viewModel.pageStore.rootURL.appendingPathComponent(page.processedFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            showToast("找不到實體 JPEG 檔案")
            return
        }
        activeModal = .jpgShare(url)
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastMessage == msg {
                toastMessage = nil
            }
        }
    }
}
