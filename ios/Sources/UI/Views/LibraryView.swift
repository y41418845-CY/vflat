import SwiftUI

#if canImport(UIKit)
import UIKit
import Photos
#endif

/// 原廠 1:1 書庫、資料夾與批次文件管理中心 (LibraryViewController & FolderViewController)
public struct LibraryView: View {
    @StateObject private var viewModel = ScannerViewModel()

    // MARK: - 介面狀態
    @State private var isSelectingMode: Bool = false
    @State private var selectedPageIds: Set<UUID> = []
    @State private var searchText: String = ""
    @State private var isSearchActive: Bool = false
    @State private var gridColumnsCount: Int = 2
    @State private var sortAscending: Bool = true

    // 彈窗狀態
    @State private var showingCameraScan: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingTrashBin: Bool = false
    @State private var showingPhotoPicker: Bool = false
    @State private var showingCreateFolderAlert: Bool = false
    @State private var showingRenameFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    @State private var renameFolderName: String = ""
    @State private var activeDetailModal: ActiveLibraryModal? = nil
    @State private var toastMessage: String? = nil

    private enum ActiveLibraryModal: Identifiable {
        case pageDetail(UUID)
        case pdfExport
        case moveSelected([UUID])

        var id: String {
            switch self {
            case .pageDetail(let id):
                return "detail_\(id.uuidString)"
            case .pdfExport:
                return "pdfExport"
            case .moveSelected(let ids):
                return "move_\(ids.count)_\(ids.first?.uuidString ?? "")"
            }
        }
    }

    public init() {}

    // MARK: - 資料計算

    private var currentFolder: ScanFolder {
        viewModel.pageStore.currentFolder
    }

    /// 當前資料夾內的頁面（支援搜尋與排序）
    private var displayedPages: [ScanPage] {
        var list = viewModel.pageStore.pages(in: viewModel.pageStore.currentFolderId)
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            list = list.filter {
                ($0.ocrText?.lowercased().contains(query) ?? false) ||
                $0.processedFileName.lowercased().contains(query)
            }
        }
        if sortAscending {
            list.sort { $0.createdAt < $1.createdAt }
        } else {
            list.sort { $0.createdAt > $1.createdAt }
        }
        return list
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: gridColumnsCount)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // 背景：原廠純白/淺灰背景
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // 1. 搜尋列（啟動搜尋時展開）
                    if isSearchActive {
                        searchBarView
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // 2. 主內容：頁面網格 或 空狀態
                    if displayedPages.isEmpty {
                        emptyFolderView
                    } else {
                        pageGridView
                    }

                    // 3. 底部動作列（一般模式為相機按鈕；選取模式為批次操作列）
                    if isSelectingMode {
                        batchActionBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        bottomCameraBar
                    }
                }

                // 4. Toast 提示膠囊
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
                            .padding(.bottom, 100)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.easeInOut(duration: 0.25), value: toastMessage)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左側：資料夾切換選單
                ToolbarItem(placement: .navigationBarLeading) {
                    folderMenuButton
                }

                // 右側：搜尋、選取、更多選單
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isSelectingMode {
                        Button(selectedPageIds.count == displayedPages.count ? "取消全選" : "全選") {
                            if selectedPageIds.count == displayedPages.count {
                                selectedPageIds.removeAll()
                            } else {
                                selectedPageIds = Set(displayedPages.map { $0.id })
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))

                        Button("完成") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectingMode = false
                                selectedPageIds.removeAll()
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    } else {
                        Button(action: {
                            withAnimation {
                                isSearchActive.toggle()
                                if !isSearchActive { searchText = "" }
                            }
                        }) {
                            Image(systemName: isSearchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                                .font(.system(size: 17))
                        }

                        Button("選取") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectingMode = true
                                selectedPageIds.removeAll()
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .disabled(displayedPages.isEmpty)

                        moreMenuButton
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCameraScan) {
                CameraScanView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingTrashBin) {
                TrashBinView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoImportPickerView(viewModel: viewModel)
            }
            .sheet(item: $activeDetailModal) { modal in
                switch modal {
                case .pageDetail(let pageId):
                    PageSwipeDetailView(viewModel: viewModel, initialPageId: pageId)
                case .pdfExport:
                    PDFExportSheet(viewModel: viewModel)
                case .moveSelected(let ids):
                    MoveFolderSheet(viewModel: viewModel, pageIds: Set(ids))
                }
            }
            .alert("新增資料夾", isPresented: $showingCreateFolderAlert) {
                TextField("輸入資料夾名稱", text: $newFolderName)
                Button("取消", role: .cancel) {}
                Button("建立") {
                    let folder = viewModel.pageStore.createFolder(name: newFolderName)
                    showToast("已建立資料夾「\(folder.name)」")
                }
            }
            .alert("重新命名資料夾", isPresented: $showingRenameFolderAlert) {
                TextField("輸入新名稱", text: $renameFolderName)
                Button("取消", role: .cancel) {}
                Button("儲存") {
                    viewModel.pageStore.renameFolder(id: currentFolder.id, newName: renameFolderName)
                    showToast("資料夾已更名為「\(renameFolderName)」")
                }
            }
            .onAppear {
                if viewModel.startScreenMode == .camera && !showingCameraScan && viewModel.pageCount == 0 {
                    // 若設定為預設相機秒開，且首次啟動無頁面時自動展開相機
                    showingCameraScan = true
                }
            }
        }
    }

    // MARK: - 資料夾切換選單

    private var folderMenuButton: some View {
        Menu {
            Section(header: Text("切換資料夾")) {
                ForEach(viewModel.pageStore.folders) { folder in
                    Button(action: {
                        viewModel.pageStore.currentFolderId = folder.id
                    }) {
                        HStack {
                            Text(folder.name)
                            if folder.id == currentFolder.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section {
                Button(action: {
                    newFolderName = ""
                    showingCreateFolderAlert = true
                }) {
                    Label("新增資料夾", systemImage: "folder.badge.plus")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))

                Text(currentFolder.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)

                Text("(\(displayedPages.count))")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 更多選單 (排序、檢視、垃圾桶、設定)

    private var moreMenuButton: some View {
        Menu {
            Section(header: Text("排序與顯示")) {
                Button(action: { sortAscending = true }) {
                    Label("依時間由舊到新", systemImage: sortAscending ? "checkmark" : "")
                }
                Button(action: { sortAscending = false }) {
                    Label("依時間由新到舊", systemImage: !sortAscending ? "checkmark" : "")
                }
                Button(action: {
                    gridColumnsCount = (gridColumnsCount == 2) ? 3 : 2
                }) {
                    Label(gridColumnsCount == 2 ? "切換至 3 列密集網格" : "切換至 2 列標準網格",
                          systemImage: gridColumnsCount == 2 ? "square.grid.3x3" : "square.grid.2x2")
                }
            }

            Section(header: Text("資料夾操作")) {
                Button(action: {
                    newFolderName = ""
                    showingCreateFolderAlert = true
                }) {
                    Label("新增資料夾", systemImage: "folder.badge.plus")
                }

                if currentFolder.id != ScanFolder.defaultId {
                    Button(action: {
                        renameFolderName = currentFolder.name
                        showingRenameFolderAlert = true
                    }) {
                        Label("重新命名此資料夾", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: {
                        let name = currentFolder.name
                        viewModel.pageStore.deleteFolder(id: currentFolder.id)
                        showToast("已刪除「\(name)」，頁面已移至垃圾桶")
                    }) {
                        Label("刪除此資料夾", systemImage: "trash")
                    }
                }
            }

            Section {
                Button(action: { showingTrashBin = true }) {
                    HStack {
                        Label("垃圾桶 (最近刪除)", systemImage: "trash")
                        if !viewModel.pageStore.trashPages.isEmpty {
                            Spacer()
                            Text("\(viewModel.pageStore.trashPages.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button(action: { showingSettings = true }) {
                    Label("設定中心", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18))
        }
    }

    // MARK: - 搜尋列

    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜尋 OCR 辨識文字或頁面名稱...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - 空狀態

    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(red: 0.08, green: 0.78, blue: 0.44).opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "book.closed")
                    .font(.system(size: 46))
                    .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))
            }

            Text("此資料夾尚無掃描內容")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Text("點擊下方綠色相機按鈕即可秒開拍攝\n或從 iPhone 相簿批次匯入書籍照片")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button(action: { showingPhotoPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                    Text("從相簿匯入圖片")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 0.08, green: 0.78, blue: 0.44).opacity(0.12))
                .cornerRadius(18)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - 頁面網格 (Grid)

    private var pageGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(displayedPages.indices, id: \.self) { index in
                    let page = displayedPages[index]
                    let isSelected = selectedPageIds.contains(page.id)

                    Button(action: {
                        if isSelectingMode {
                            if isSelected {
                                selectedPageIds.remove(page.id)
                            } else {
                                selectedPageIds.insert(page.id)
                            }
                        } else {
                            activeDetailModal = .pageDetail(page.id)
                        }
                    }) {
                        ZStack(alignment: .topTrailing) {
                            VStack(spacing: 0) {
                                // 縮圖展示
                                ZStack(alignment: .bottomLeading) {
                                    if let thumb = viewModel.pageStore.thumbnail(for: page, maxPixel: 360) {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity)
                                            .background(Color.white)
                                            .cornerRadius(10)
                                            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .aspectRatio(0.72, contentMode: .fit)
                                            .cornerRadius(10)
                                    }

                                    // 左下角原廠精緻頁碼圓標
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Color.black.opacity(0.65))
                                        .clipShape(Circle())
                                        .padding(6)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.clear, lineWidth: 3)
                            )

                            // 多選 Checkbox
                            if isSelectingMode {
                                ZStack {
                                    Circle()
                                        .fill(isSelected ? Color(red: 0.08, green: 0.78, blue: 0.44) : Color.white.opacity(0.9))
                                        .frame(width: 26, height: 26)
                                        .shadow(color: .black.opacity(0.2), radius: 2)

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Circle()
                                            .stroke(Color.gray.opacity(0.6), lineWidth: 2)
                                            .frame(width: 22, height: 22)
                                    }
                                }
                                .padding(8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
    }

    // MARK: - 底部常態相機列

    private var bottomCameraBar: some View {
        HStack {
            // 左側：相簿匯入
            Button(action: { showingPhotoPicker = true }) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                    Text("相簿匯入")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .frame(width: 70)
            }

            Spacer()

            // 中央：原廠經典相機大圓鈕
            Button(action: {
                showingCameraScan = true
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.85, blue: 0.48), Color(red: 0.06, green: 0.72, blue: 0.40)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 66, height: 66)
                        .shadow(color: Color(red: 0.08, green: 0.78, blue: 0.44).opacity(0.4), radius: 10, x: 0, y: 5)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .offset(y: -8)

            Spacer()

            // 右側：垃圾桶快捷
            Button(action: { showingTrashBin = true }) {
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash")
                            .font(.system(size: 20))
                        if !viewModel.pageStore.trashPages.isEmpty {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -2)
                        }
                    }
                    Text("最近刪除")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .frame(width: 70)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(
            Color(UIColor.secondarySystemGroupedBackground)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: -4)
        )
    }

    // MARK: - 底部多選批次操作列

    private var batchActionBar: some View {
        HStack(spacing: 0) {
            // 1. 匯出 PDF
            batchButton(title: "匯出 PDF", icon: "doc.richtext") {
                activeDetailModal = .pdfExport
            }

            // 2. 存入相簿 JPG
            batchButton(title: "存入相簿", icon: "square.and.arrow.down") {
                batchSavePhotos()
            }

            // 3. 移動資料夾
            batchButton(title: "移動", icon: "folder") {
                activeDetailModal = .moveSelected(Array(selectedPageIds))
            }

            // 4. 刪除
            batchButton(title: "刪除", icon: "trash", isDestructive: true) {
                batchDelete()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(
            Color(UIColor.secondarySystemGroupedBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: -4)
        )
    }

    private func batchButton(
        title: String,
        icon: String,
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
                selectedPageIds.isEmpty ? Color.gray.opacity(0.4) :
                isDestructive ? Color.red : Color(red: 0.08, green: 0.78, blue: 0.44)
            )
        }
        .disabled(selectedPageIds.isEmpty)
    }

    // MARK: - 批次動作處理

    private func batchSavePhotos() {
        let targetPages = displayedPages.filter { selectedPageIds.contains($0.id) }
        guard !targetPages.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    self.showToast("儲存失敗：請至系統設定開啟相片存取權限")
                    return
                }
                Task {
                    var count = 0
                    for page in targetPages {
                        if let img = self.viewModel.pageStore.image(for: page) {
                            let ok = await withCheckedContinuation { cont in
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                                }) { ok, _ in
                                    cont.resume(returning: ok)
                                }
                            }
                            if ok { count += 1 }
                        }
                    }
                    self.showToast("已成功將 \(count) 頁儲存至相簿")
                    self.isSelectingMode = false
                    self.selectedPageIds.removeAll()
                }
            }
        }
    }

    private func batchDelete() {
        let count = selectedPageIds.count
        viewModel.pageStore.delete(ids: selectedPageIds)
        showToast("已將 \(count) 個頁面移至垃圾桶 (保留 30 天)")
        isSelectingMode = false
        selectedPageIds.removeAll()
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
