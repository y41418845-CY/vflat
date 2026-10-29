import SwiftUI

#if canImport(PhotosUI)
import PhotosUI
#endif

/// 復刻圖二與圖三：相簿多選與批次匯入增強微調設定面板
public struct PhotoImportPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    // 選取狀態 (支援多選序號)
    @State private var selectedIndices: [Int] = [0] // 預設示範選取第 1 張
    @State private var showingBatchSettings: Bool = false

    // 圖三之 6 項增強開關狀態 (完全對齊圖三)
    @State private var isAutoCropEnabled: Bool = true
    @State private var isStraightenEnabled: Bool = false
    @State private var isColorCorrectionEnabled: Bool = true
    @State private var isTextDarkenEnabled: Bool = true
    @State private var isRemoveFingersEnabled: Bool = false

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if showingBatchSettings {
                // 圖三：一頁一頁調整與批次匯入開關設定
                batchSettingsView
            } else {
                // 圖二：相簿照片多選網格流
                photoGridView
            }
        }
    }

    // MARK: - 圖二：相簿多選畫面
    private var photoGridView: some View {
        VStack(spacing: 0) {
            // 頂部導航列 (關閉、最近項目 ⌄)
            HStack {
                Button("關閉") {
                    dismiss()
                }
                .font(.system(size: 17))
                .foregroundColor(.black)

                Spacer()

                HStack(spacing: 4) {
                    Text("最近項目")
                        .font(.system(size: 17, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.black)

                Spacer()

                Color.clear.frame(width: 44, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            // 照片網格 (三欄式排列)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(0..<12) { index in
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(white: 0.92))
                                .frame(height: 120)
                                .overlay(
                                    VStack {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.gray.opacity(0.5))
                                        Text("掃描樣張 \(index + 1)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.gray)
                                    }
                                )

                            // 選取序號標籤 (如圖二之青綠色圓標 ①)
                            if let pos = selectedIndices.firstIndex(of: index) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.22, green: 0.72, blue: 0.62))
                                        .frame(width: 24, height: 24)
                                    Text("\(pos + 1)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(6)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let pos = selectedIndices.firstIndex(of: index) {
                                selectedIndices.remove(at: pos)
                            } else {
                                selectedIndices.append(index)
                            }
                        }
                    }
                }
                .padding(4)
            }

            // 底部青綠色按鈕：下一步 (N) - 完全對齊圖二
            Button(action: {
                if !selectedIndices.isEmpty {
                    showingBatchSettings = true
                }
            }) {
                Text("下一步 (\(selectedIndices.count))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(red: 0.38, green: 0.78, blue: 0.68))
            }
        }
    }

    // MARK: - 圖三：一頁一頁微調與功能開關面板
    private var batchSettingsView: some View {
        VStack(spacing: 0) {
            // 頂部導航
            HStack {
                Button("返回") {
                    showingBatchSettings = false
                }
                .font(.system(size: 16))
                .foregroundColor(.black)

                Spacer()

                Text("1 of \(max(selectedIndices.count, 1))")
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

            // 中央預覽圖
            ZStack {
                Color(white: 0.95)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                    .overlay(
                        VStack {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 54))
                                .foregroundColor(.gray.opacity(0.4))
                            Text("樣張預覽 (微調處理中)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .padding(20)
            }
            .frame(maxHeight: 280)

            // 功能微調開關列表 (對齊圖三 6 大開關)
            VStack(spacing: 12) {
                settingToggleRow(title: "自動裁剪", isOn: $isAutoCropEnabled)
                Divider()
                settingToggleRow(title: "拉直", isOn: $isStraightenEnabled)
                Divider()
                settingToggleRow(title: "色彩校正", isOn: $isColorCorrectionEnabled)
                Divider()
                settingToggleRow(title: "使文本變暗", isOn: $isTextDarkenEnabled)
                Divider()
                settingToggleRow(title: "移除手指", isOn: $isRemoveFingersEnabled)
                Divider()

                // 保存到資料夾膠囊
                HStack {
                    Text("保存到")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(viewModel.currentFolder)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.9))
                }
                .padding(.vertical, 4)
            }
            .padding(16)
            .background(Color.white)

            Spacer()

            // 底部操作列 (取消、導入) - 對齊圖三最底
            HStack {
                Button("取消") {
                    dismiss()
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color(red: 0.3, green: 0.5, blue: 0.9))

                Spacer()

                Button("導入") {
                    viewModel.capturedPageCount += selectedIndices.count
                    dismiss()
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.9))
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
