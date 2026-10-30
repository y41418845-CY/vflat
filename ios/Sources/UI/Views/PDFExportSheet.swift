import SwiftUI

#if canImport(UIKit)
import UIKit

/// 原生 PDF 匯出與分享設定彈窗 (對齊 OpenScan 匯出體驗)
public struct PDFExportSheet: View {
    public let images: [UIImage]
    public let defaultPrefix: String
    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String
    @State private var selectedPageSize: PDFPageSize = .a4
    @State private var selectedQuality: PDFCompressionQuality = .medium
    @State private var isExporting: Bool = false
    @State private var shareURL: URL? = nil
    @State private var showingShareActivity: Bool = false

    public init(images: [UIImage], defaultPrefix: String = "涓建築") {
        self.images = images
        self.defaultPrefix = defaultPrefix
        let initialName = DocumentNamingService.generateName(prefix: defaultPrefix, ext: "pdf")
        self._fileName = State(initialValue: initialName)
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
                }

                Section(header: Text("壓縮品質")) {
                    Picker("品質等級", selection: $selectedQuality) {
                        ForEach(PDFCompressionQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }

                Section(header: Text("掃描頁數資訊")) {
                    HStack {
                        Text("包含頁數")
                        Spacer()
                        Text("\(images.count) 頁")
                            .foregroundColor(.secondary)
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
                    .disabled(isExporting || images.isEmpty)
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
        guard !images.isEmpty else { return }
        isExporting = true

        DispatchQueue.global(qos: .userInitiated).async {
            let finalName = fileName.hasSuffix(".pdf") ? fileName : "\(fileName).pdf"
            let exportedURL = PDFExporter.shared.exportTemporaryPDF(
                images: images,
                fileName: finalName,
                pageSize: selectedPageSize,
                quality: selectedQuality
            )

            DispatchQueue.main.async {
                self.isExporting = false
                if let url = exportedURL {
                    self.shareURL = url
                    self.showingShareActivity = true
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
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
