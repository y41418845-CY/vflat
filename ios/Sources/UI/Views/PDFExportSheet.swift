import SwiftUI

struct PDFExportSheet: View {
    let pages: [ScanPage]
    let store: ScanPageStore
    let defaultPrefix: String
    @State private var fileName: String = ""
    @State private var sizeChoice: Int = 0
    @State private var password: String = ""
    @State private var usePassword: Bool = false
    @State private var searchable: Bool = true
    @Environment(\.dismiss) var dismiss
    @State private var exportedURL: URL?

    var body: some View {
        NavigationView {
            Form {
                Section("檔名") {
                    TextField("檔名", text: $fileName)
                }
                Section("PDF 尺寸") {
                    Picker("尺寸", selection: $sizeChoice) {
                        Text("A4").tag(0)
                        Text("適應寬度").tag(1)
                        Text("原圖比例").tag(2)
                    }
                }
                Section("密碼保護") {
                    Toggle("啟用密碼", isOn: $usePassword)
                    if usePassword {
                        SecureField("密碼", text: $password)
                    }
                }
                Section {
                    Toggle("可搜尋文字 (OCR)", isOn: $searchable)
                }
                Section {
                    Button("匯出") {
                        let size: PDFPageSize = sizeChoice == 0 ? .a4 : (sizeChoice == 1 ? .fitWidth : .original)
                        let name = fileName.isEmpty ? DocumentNamingService.defaultName(folder: defaultPrefix) : fileName
                        let exporter = PDFExporter()
                        if let url = exporter.export(pages: pages, store: store, fileName: name, pageSize: size, password: usePassword ? password : nil, searchable: searchable) {
                            exportedURL = url
                        }
                    }
                }
            }
            .navigationTitle("匯出 PDF")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .sheet(item: Binding(get: { exportedURL.map { ShareItem(url: $0) } }, set: { _ in exportedURL = nil })) { item in
            ActivityView(url: item.url)
        }
    }

    struct ShareItem: Identifiable { let id = UUID(); let url: URL }
}
