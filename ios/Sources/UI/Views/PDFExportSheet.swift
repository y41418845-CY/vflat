import SwiftUI

#if canImport(UIKit)
import UIKit

/// 原生 PDF 匯出與分享設定彈窗 (對齊 OpenScan 匯出體驗)
///
/// 只接收 `ScanPage` 中繼資料，實際影像在匯出時才由 `ScanPageStore` 從磁碟解碼，
/// 避免一次把所有全解析度頁面載入記憶體（舊版 `[UIImage]` 會在數十頁後 OOM）。
public struct PDFExportSheet: View {
    public let pages: [ScanPage]
    public let store: ScanPageStore
    public let defaultPrefix: String
    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String
    @State private var selectedPageSize: PDFPageSize = .a4
    @State private var selectedOrientation: PDFPageOrientation = .auto
    @State private var selectedColorMode: PDFColorMode = .color
    @State private var selectedQuality: PDFCompressionQuality = .medium
    @State private var enablePassword: Bool = false
    @State private var passwordText: String = ""
    @State private var isExporting: Bool = false
    @State private var shareURL: URL? = nil
    @State private var showingShareActivity: Bool = false
    @State private var errorMessage: String? = nil

    public init(pages: [ScanPage], store: ScanPageStore, defaultPrefix: String = "Scan") {
        self.pages = pages
        self.store = store
        self.defaultPrefix = defaultPrefix
        let initialName = DocumentNamingService.generateName(prefix: defaultPrefix, ext: "pdf")
        self._fileName = State(initialValue: initialName)
    }

    public init(viewModel: ScannerViewModel) {
        self.init(pages: viewModel.pages, store: viewModel.pageStore, defaultPrefix: viewModel.currentFolder)
    }

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("檔案名稱")) {
                    TextField("輸入檔名", text: $fileName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("頁面規格與版面")) {
                    Picker("紙張尺寸", selection: $selectedPageSize) {
                        ForEach(PDFPageSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }

                    Picker("頁面方向", selection: $selectedOrientation) {
                        ForEach(PDFPageOrientation.allCases) { orientation in
                            Text(orientation.rawValue).tag(orientation)
                        }
                    }

                    Picker("色彩模式", selection: $selectedColorMode) {
                        ForEach(PDFColorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                Section(header: Text("壓縮品質")) {
                    Picker("品質等級", selection: $selectedQuality) {
                        ForEach(PDFCompressionQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }

                Section(header: Text("安全與進階設定")) {
                    Toggle("啟用 PDF 密碼保護", isOn: $enablePassword)
                    if enablePassword {
                        SecureField("輸入開啟密碼", text: $passwordText)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Text("可搜尋 PDF (OCR 文字層)")
                        Spacer()
                        Text("自動嵌入")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("掃描頁數資訊")) {
                    HStack {
                        Text("包含頁數")
                        Spacer()
                        Text("\(pages.count) 頁")
                            .foregroundColor(.secondary)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(action: exportAndShare) {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isExporting ? "正在合成 PDF..." : "匯出並分享 PDF")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color(red: 0.22, green: 0.72, blue: 0.62))
                    .disabled(isExporting || pages.isEmpty)
                }
            }
            .navigationTitle("匯出 PDF 文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareActivity) {
                if let url = shareURL {
                    ActivityView(activityItems: [url])
                }
            }
        }
    }

    private func exportAndShare() {
        guard !pages.isEmpty, !isExporting else { return }
        isExporting = true
        errorMessage = nil

        let finalName = fileName.hasSuffix(".pdf") ? fileName : "\(fileName).pdf"
        let pageSize = selectedPageSize
        let orientation = selectedOrientation
        let colorMode = selectedColorMode
        let quality = selectedQuality
        let password = enablePassword ? passwordText : nil
        let pageSnapshot = pages
        let ocrList = pageSnapshot.map { $0.ocrText }
        let store = self.store

        Task {
            // 影像解碼與 PDF 合成都在背景，期間 UI 保持可互動
            let images = await store.loadImages(for: pageSnapshot)

            guard images.count == pageSnapshot.count, !images.isEmpty else {
                await MainActor.run {
                    self.isExporting = false
                    self.errorMessage = "部分頁面檔案遺失，請重新掃描後再匯出"
                }
                return
            }

            let exportedURL = await Task.detached(priority: .userInitiated) {
                PDFExporter.shared.exportTemporaryPDF(
                    images: images,
                    ocrTexts: ocrList,
                    fileName: finalName,
                    pageSize: pageSize,
                    orientation: orientation,
                    colorMode: colorMode,
                    quality: quality,
                    password: password
                )
            }.value

            await MainActor.run {
                self.isExporting = false
                if let url = exportedURL {
                    self.shareURL = url
                    self.showingShareActivity = true
                } else {
                    self.errorMessage = "PDF 產生失敗，請確認裝置儲存空間"
                }
            }
        }
    }
}

/// UIActivityViewController 原生分享面包裝
public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]? = nil

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        if let popover = controller.popoverPresentationController,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
