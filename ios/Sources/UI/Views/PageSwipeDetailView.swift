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

/// 左右水平翻頁閱讀器 (1:1 完美對齊原廠圖二配置)
public struct PageSwipeDetailView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @ObservedObject private var pageStore: ScanPageStore
    @Environment(\.dismiss) private var dismiss

    private let initialPageId: UUID?
    @State private var selectedIndex: Int = 0
    @State private var showingFilterSelector: Bool = false
    @State private var showingLoupeCropView: Bool = false
    @State private var showingMoreMenuActionSheet: Bool = false
    @State private var showingThumbnailStrip: Bool = false
    @State private var toastMessage: String? = nil
    @State private var processingDescription: String? = nil
    @State private var showingAIEraser: Bool = false
    @State private var eraserImage: UIImage? = nil
    @State private var imageRevision: UUID = UUID()

    private enum ActiveModal: Identifiable {
        case aiEnhancer
        case pdfExport
        case ocrResult(String)
        case jpgShare(URL)
        case moveFolder(UUID)

        var id: String {
            switch self {
            case .aiEnhancer:
                return "aiEnhancer"
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
        self._pageStore = ObservedObject(wrappedValue: viewModel.pageStore)
        self.initialPageId = initialPageId
    }

    /// 當前資料夾過濾後的頁面清單
    private var pages: [ScanPage] {
        let folderPages = pageStore.pages(in: pageStore.currentFolderId)
        return folderPages.isEmpty ? pageStore.pages : folderPages
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
                // 1. 頂部導航列 (1:1 對齊原廠圖二：< 相機 | 183 / 183 | 文件夾 ...)
                topNavigationBar

                // 2. 中央水平翻頁 TabView
                centralPagingView

                // 3. 底部快捷縮圖導覽條 (可切換顯示/隱藏)
                if showingThumbnailStrip {
                    thumbnailStripView
                }

                // 4. 底部原廠 5 大影像編輯工具列 (裁剪、增強、濾鏡、OCR、刪除)
                bottomToolBar
            }

            // 5. AI 後處理進度遮罩
            if let desc = processingDescription ?? (viewModel.isProcessingCapture ? "處理中..." : nil) {
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.4)
                        Text(desc)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(26)
                    .background(Color(white: 0.18, opacity: 0.95))
                    .cornerRadius(18)
                    .shadow(radius: 12)
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
               let targetIndex = pages.firstIndex(where: { $0.id == targetId }) {
                selectedIndex = targetIndex
            } else if !pages.isEmpty {
                selectedIndex = pages.count - 1
            }
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .aiEnhancer:
                AIEnhancerSheet { type in
                    if type == .eraser, let page = currentPage, let img = pageStore.image(for: page) {
                        eraserImage = img
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingAIEraser = true
                        }
                    } else {
                        runAI(type)
                    }
                }
            case .pdfExport:
                PDFExportSheet(viewModel: viewModel)
            case .ocrResult(let text):
                OCRResultSheet(ocrText: text)
            case .jpgShare(let fileURL):
                ActivityView(activityItems: [fileURL])
            case .moveFolder(let pageId):
                MoveFolderSheet(viewModel: viewModel, pageIds: [pageId])
            }
        }
        .fullScreenCover(isPresented: $showingAIEraser) {
            if let img = eraserImage, let page = currentPage {
                AIEraserView(
                    sourceImage: img,
                    onApply: { cleaned in
                        showingAIEraser = false
                        Task {
                            await pageStore.updateProcessed(id: page.id, image: cleaned, filterMode: page.filterMode)
                            await MainActor.run {
                                self.showToast("塗鴉橡皮擦完成")
                            }
                        }
                    },
                    onCancel: {
                        showingAIEraser = false
                        showToast("塗鴉橡皮擦已取消")
                    }
                )
            }
        }
        .sheet(isPresented: $showingLoupeCropView) {
            if let page = currentPage, let image = pageStore.rawImage(for: page) ?? pageStore.image(for: page) {
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
        .confirmationDialog("更多選項", isPresented: $showingMoreMenuActionSheet, titleVisibility: .visible) {
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
                Button("移動此頁至其他文件夾...") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activeModal = .moveFolder(page.id)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 頂部導航列 (1:1 對齊原廠圖二：< 相機 | 183 / 183 | 文件夾 ...)

    private var topNavigationBar: some View {
        HStack(alignment: .center) {
            // 左側返回相機鈕 (< 相機)
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    Text("相機")
                        .font(.system(size: 17, weight: .medium))
                }
                .foregroundColor(.white)
            }

            Spacer()

            // 中間大頁碼 (183 / 183)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingThumbnailStrip.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Text(pages.isEmpty ? "0 / 0" : "\(selectedIndex + 1) / \(pages.count)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: showingThumbnailStrip ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
            }

            Spacer()

            // 右側：文件夾 + 更多按鈕 (...)
            HStack(spacing: 16) {
                // 文件夾快速移動
                Button(action: {
                    if let page = currentPage {
                        activeModal = .moveFolder(page.id)
                    }
                }) {
                    Text("文件夾")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(currentPage != nil ? .white : .gray)
                }
                .disabled(currentPage == nil)

                // 更多功能選單按鈕 (...)
                Button(action: { showingMoreMenuActionSheet = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
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
                    Text("文件夾內尚無任何掃描頁面")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(pages.indices, id: \.self) { index in
                        let page = pages[index]
                        if let img = pageStore.image(for: page) {
                            ZoomableImageView(image: img)
                                .tag(index)
                                .id("\(page.id.uuidString)_\(imageRevision.uuidString)")
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
                                if let thumb = pageStore.thumbnail(for: page, maxPixel: 160) {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 70)
                                        .clipped()
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.clear, lineWidth: 2)
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
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(4)
                                    .padding(3)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(red: 0.14, green: 0.14, blue: 0.15))
            .onChange(of: selectedIndex) { newIndex in
                withAnimation {
                    scrollProxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - 底部原廠 5 大影像編輯工具列 (裁剪、增強、濾鏡、OCR、刪除)

    private var bottomToolBar: some View {
        VStack(spacing: 0) {
            if showingFilterSelector {
                filterSelectorBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                // 1. 裁剪
                toolButton(
                    icon: "crop",
                    title: "裁剪",
                    action: { showingLoupeCropView = true }
                )

                // 2. 增強 (點擊開啟原廠 1:1 人工智慧增強器卡片面板)
                toolButton(
                    icon: "sparkles",
                    title: "增強",
                    highlight: true,
                    action: { activeModal = .aiEnhancer }
                )

                // 3. 濾鏡
                toolButton(
                    icon: "slider.horizontal.3",
                    title: "濾鏡",
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFilterSelector.toggle()
                        }
                    }
                )

                // 4. 文字辨識 (OCR)
                toolButton(
                    icon: "doc.text.viewfinder",
                    title: "文字",
                    action: { recognizeCurrentPageText() }
                )

                // 5. 刪除
                toolButton(
                    icon: "trash",
                    title: "刪除",
                    isDestructive: true,
                    action: { deleteCurrentPage() }
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        }
    }

    private func toolButton(
        icon: String,
        title: String,
        highlight: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(
                isDestructive ? Color.red.opacity(0.85) :
                highlight ? Color(red: 0.16, green: 0.85, blue: 0.55) :
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
              let raw = pageStore.rawImage(for: page) ?? pageStore.image(for: page) else { return }
        processingDescription = "套用 \(mode.rawValue)..."
        Task {
            let processed = DocumentRectifier.shared.applyFilter(mode, to: raw)
            await pageStore.updateProcessed(id: page.id, image: processed, filterMode: mode)
            await MainActor.run {
                self.imageRevision = UUID()
                self.processingDescription = nil
                self.showToast("已套用 \(mode.rawValue)")
            }
        }
    }

    private func applyCrop(document: DetectedDocument, for page: ScanPage) async {
        guard let raw = pageStore.rawImage(for: page) ?? pageStore.image(for: page) else { return }
        await MainActor.run {
            self.processingDescription = "重新裁切與幾何拉直中..."
        }
        let cropped = DocumentRectifier.shared.correctPerspective(image: raw, document: document) ?? raw
        let filtered = DocumentRectifier.shared.applyFilter(page.filterMode, to: cropped)
        await pageStore.updateProcessed(id: page.id, image: filtered, filterMode: page.filterMode)
        await MainActor.run {
            self.imageRevision = UUID()
            self.processingDescription = nil
            self.showToast("裁剪與幾何透視已更新")
        }
    }

    private func runAI(_ type: ScannerViewModel.AIEnhancerType) {
        guard let page = currentPage else { return }
        processingDescription = "正在為您進行\(type.rawValue)..."
        Task {
            await viewModel.runAIEnhancer(type: type, targetPageID: page.id)
            await MainActor.run {
                self.imageRevision = UUID()
                self.processingDescription = nil
                self.showToast("AI \(type.rawValue) 已完成")
            }
        }
    }

    private func recognizeCurrentPageText() {
        guard let page = currentPage else { return }
        if let existing = page.ocrText, !existing.isEmpty {
            activeModal = .ocrResult(existing)
            return
        }
        guard let image = pageStore.image(for: page) else { return }
        processingDescription = "離線文字辨識中..."
        Task {
            let recognized = await OCRService.shared.recognizeText(in: image) ?? ""
            let resultText = recognized.isEmpty ? "未偵測到清晰文字" : recognized
            await MainActor.run {
                self.pageStore.updateOCR(id: page.id, text: resultText)
                self.processingDescription = nil
                self.activeModal = .ocrResult(resultText)
            }
        }
    }

    private func deleteCurrentPage() {
        guard let page = currentPage else { return }
        let oldIndex = selectedIndex
        pageStore.delete(id: page.id)
        if pages.isEmpty {
            dismiss()
        } else {
            selectedIndex = max(0, min(oldIndex, pages.count - 1))
        }
        showToast("已移至垃圾桶 (保留 30 天)")
    }

    private func saveCurrentPageToPhotos() {
        guard let page = currentPage, let image = pageStore.image(for: page) else { return }
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
                        if let img = self.pageStore.image(for: page) {
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
        let url = pageStore.rootURL.appendingPathComponent(page.processedFileName)
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
