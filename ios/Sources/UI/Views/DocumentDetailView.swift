import SwiftUI
import UIKit

struct DocumentDetailView: View {
    @EnvironmentObject var vm: ScannerViewModel
    @State private var showingFilterSelector = false
    @State private var showingAISelector = false
    @State private var activeModal: ActiveDetailModal?
    @State private var toast: String?

    private let accentGreen = Color(red: 0.22, green: 0.85, blue: 0.45)

    enum ActiveDetailModal: Identifiable {
        case pdfExport, ocrResult, jpgShare(URL)
        var id: String {
            switch self { case .pdfExport: return "pdf"; case .ocrResult: return "ocr"; case .jpgShare: return "jpg" }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // nav bar
            HStack {
                Button(action: { /* back to camera */ }) {
                    HStack { Image(systemName: "chevron.left"); Text("相機") }
                }
                Spacer()
                Text("\(vm.pageStore.count)頁 · \(UserDefaults.standard.string(forKey: "vflat_current_folder") ?? "Scan")")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { activeModal = .pdfExport }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(vm.pageStore.count == 0)
            }
            .padding()
            // image display
            GeometryReader { geo in
                ZStack {
                    Color(white: 0.96)
                    if let img = vm.lastPreviewImage {
                        Image(uiImage: img).resizable().scaledToFit().shadow(radius: 4)
                    } else {
                        VStack {
                            Image(systemName: "doc.text.magnifyingglass").font(.largeTitle)
                            Text("尚無文件")
                        }
                    }
                    if vm.isProcessingCapture {
                        Color.black.opacity(0.4)
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    }
                    // OCR button
                    Button(action: { Task { await vm.recognizeTextForCurrentPage(); activeModal = .ocrResult } }) {
                        Text("辨識文字")
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(Color(red:0.22,green:0.72,blue:0.62)))
                            .foregroundColor(.white)
                    }
                    .position(x: geo.size.width/2, y: geo.size.height - 30)
                    if let t = toast {
                        Text(t)
                            .padding(8)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                            .foregroundColor(.white)
                            .position(x: geo.size.width/2, y: geo.size.height - 72)
                    }
                }
            }
            // filter selector
            if showingFilterSelector {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(DocumentFilterMode.allCases) { mode in
                            Button(action: {
                                vm.selectedFilterMode = mode
                                if let img = vm.lastPreviewImage {
                                    let out = DocumentRectifier().applyFilter(mode, to: img, enhanceColor: true, darkenText: true)
                                    vm.lastPreviewImage = out
                                }
                            }) {
                                VStack {
                                    Image(systemName: mode.iconName).frame(width: 44, height: 44)
                                        .background(Circle().fill(Color.gray.opacity(0.2)))
                                    Text(mode.rawValue).font(.caption2)
                                }
                            }
                        }
                    }.padding()
                }
                .transition(.move(edge: .bottom))
            }
            // AI selector
            if showingAISelector {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        aiButton("極致全開", "wand.and.stars.inverse", .ultra, gradient: true)
                        aiButton("曲面展平", "arrow.left.and.right.square", .dewarp)
                        aiButton("消除陰影", "sun.max.fill", .shadow)
                        aiButton("文字銳化", "sparkles.rectangle.stack", .deblur)
                        aiButton("手指抹除", "hand.raised.slash", .finger)
                        aiButton("清除筆跡", "pencil.slash", .handwriting)
                    }.padding()
                }
                .transition(.move(edge: .bottom))
            }
            // bottom bar
            HStack {
                Button(action: {
                    // share jpg
                    if let img = vm.lastPreviewImage {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("page.jpg")
                        if let data = img.jpegData(compressionQuality: 0.92) { try? data.write(to: url); activeModal = .jpgShare(url) }
                    }
                }) { VStack { Image(systemName: "square.and.arrow.up"); Text("分享").font(.caption2) } }
                Spacer()
                Button(action: {}) { VStack { Image(systemName: "crop"); Text("裁剪").font(.caption2) } }
                Spacer()
                Button(action: { withAnimation { showingFilterSelector.toggle(); showingAISelector = false } }) {
                    VStack { Image(systemName: "slider.horizontal.3"); Text("濾鏡").font(.caption2) }
                }
                Spacer()
                Button(action: { withAnimation { showingAISelector.toggle(); showingFilterSelector = false } }) {
                    VStack { Image(systemName: "wand.and.stars"); Text("AI修復").font(.caption2) }
                }
            }
            .padding()
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .pdfExport:
                PDFExportSheet(pages: vm.pageStore.pages, store: vm.pageStore, defaultPrefix: UserDefaults.standard.string(forKey: "vflat_current_folder") ?? "Scan")
            case .ocrResult:
                OCRResultView(text: vm.lastOCRText)
            case .jpgShare(let url):
                ActivityView(url: url)
            }
        }
    }

    private func aiButton(_ title: String, _ icon: String, _ kind: AIKind, gradient: Bool = false) -> some View {
        Button(action: { Task { await vm.runAI(kind) } }) {
            VStack {
                if gradient {
                    Circle().fill(LinearGradient(colors: [Color(red:0.98,green:0.65,blue:0.22), Color(red:0.95,green:0.42,blue:0.21)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: icon).foregroundColor(.white))
                } else {
                    Image(systemName: icon).frame(width: 44, height: 44)
                        .background(Circle().fill(Color.gray.opacity(0.2)))
                }
                Text(title).font(.caption2)
            }
        }
    }
}

struct OCRResultView: View {
    let text: String?
    var body: some View {
        NavigationView {
            ScrollView { Text(text ?? "無文字").padding() }
                .navigationTitle("辨識結果")
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
