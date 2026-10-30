import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
/// 相簿多選與批次匯入設定面板。
///
/// 舊版畫面是 12 格「掃描樣張」假資料，完全沒有接上相簿權限與實際影像。
/// 現在改為真正的 `PhotosPicker` 多選，載入後才顯示批次處理選項，
/// 匯入結果會實際寫入 `ScanPageStore` 並出現在縮圖列與 PDF 匯出中。
public struct PhotoImportPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var importedImages: [UIImage] = []
    @State private var isParsingSelection: Bool = false
    @State private var showingBatchSettings: Bool = false

    // 批次處理選項（僅保留實際有實作的項目）
    @State private var isAutoCropEnabled: Bool = true
    @State private var isColorCorrectionEnabled: Bool = true
    @State private var isTextDarkenEnabled: Bool = true

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if showingBatchSettings {
                batchSettingsView
            } else {
                selectionView
            }

            if isParsingSelection || viewModel.isProcessingCapture {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text(isParsingSelection ? "正在載入相簿照片…" : "正在匯入與增強…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onChange(of: selectedItems) { _ in
            loadSelectedItems()
        }
    }

    // MARK: - 選取畫面

    private var selectionView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("關閉") { dismiss() }
                    .font(.system(size: 17))
                    .foregroundColor(.black)

                Spacer()

                Text("選擇照片")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)

                Spacer()

                Color.clear.frame(width: 44, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            if importedImages.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52))
                        .foregroundColor(.gray.opacity(0.5))

                    Text("從相簿選擇要匯入的文件照片")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)

                    photoPickerButton(label: "開啟相簿")
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 4
                    ) {
                        ForEach(Array(importedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .clipped()
                                    .cornerRadius(4)

                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.22, green: 0.72, blue: 0.62))
                                        .frame(width: 24, height: 24)
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(6)
                            }
                        }
                    }
                    .padding(4)
                }

                HStack(spacing: 12) {
                    photoPickerButton(label: "重新選擇")
                    Button(action: {
                        importedImages = []
                        selectedItems = []
                    }) {
                        Text("清除")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
                .padding(.vertical, 10)
            }

            Button(action: {
                guard !importedImages.isEmpty else { return }
                showingBatchSettings = true
            }) {
                Text("下一步 (\(importedImages.count))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        importedImages.isEmpty
                        ? Color(white: 0.85)
                        : Color(red: 0.38, green: 0.78, blue: 0.68)
                    )
            }
            .disabled(importedImages.isEmpty)
        }
    }

    private func photoPickerButton(label: String) -> some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 50,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Color(red: 0.22, green: 0.72, blue: 0.62))
                .clipShape(Capsule())
        }
    }

    private func loadSelectedItems() {
        guard !selectedItems.isEmpty else {
            importedImages = []
            return
        }

        isParsingSelection = true
        let items = selectedItems

        Task {
            var images: [UIImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                images.append(image)
            }

            await MainActor.run {
                self.importedImages = images
                self.isParsingSelection = false
            }
        }
    }

    // MARK: - 批次設定畫面

    private var batchSettingsView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回") {
                    showingBatchSettings = false
                }
                .font(.system(size: 16))
                .foregroundColor(.black)

                Spacer()

                Text("\(importedImages.count) 張照片")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.9))
                    .clipShape(Capsule())

                Spacer()

                Color.clear.frame(width: 44, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ZStack {
                Color(white: 0.95)
                if let preview = importedImages.first {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                }
            }
            .frame(maxHeight: 280)

            VStack(spacing: 12) {
                settingToggleRow(title: "自動裁剪", isOn: $isAutoCropEnabled)
                Divider()
                settingToggleRow(title: "色彩校正", isOn: $isColorCorrectionEnabled)
                Divider()
                settingToggleRow(title: "使文本變暗", isOn: $isTextDarkenEnabled)
                Divider()

                HStack {
                    Text("保存到")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(viewModel.currentFolder)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.9))
                }
                .padding(.vertical, 4)
            }
            .padding(16)
            .background(Color.white)

            Spacer()

            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color(red: 0.3, green: 0.5, blue: 0.9))

                Spacer()

                Button("導入") {
                    let options = ImportOptions(
                        autoCrop: isAutoCropEnabled,
                        colorEnhance: isColorCorrectionEnabled,
                        darkenText: isTextDarkenEnabled
                    )
                    let images = importedImages
                    Task {
                        _ = await viewModel.importImages(images, options: options)
                        await MainActor.run { dismiss() }
                    }
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.9))
                .disabled(viewModel.isProcessingCapture)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func settingToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.38, green: 0.78, blue: 0.68))
        }
    }
}
#else
/// 非 UIKit 平台（例如 macOS SwiftPM 建置）僅提供佔位畫面，確保型別仍可被引用。
public struct PhotoImportPickerView: View {
    public init(viewModel: ScannerViewModel) {}
    public var body: some View {
        Text("相簿匯入僅支援 iOS")
    }
}
#endif
