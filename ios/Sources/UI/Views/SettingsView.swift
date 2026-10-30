import SwiftUI

/// 完整復刻 REA 逆向成果中之 vFlat 設定中心 (Settings View)
/// 涵蓋相機掃描、雙頁跨頁邏輯、影像增強模型預設值與系統行為配置
///
/// 舊版所有 Toggle 都沒有實際消費端（P1-2），且版本字串寫死 `v0.8.0`、
/// 解析度 Picker 用字串 tag（型別不符，切換時直接崩潰）。此處全部改為
/// 綁定 `ScannerViewModel` 真正會被讀取的屬性。
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    @State private var folderName: String
    @State private var showingResetConfirm: Bool = false

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
        self._folderName = State(initialValue: viewModel.currentFolder)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let build = info?["CFBundleVersion"] as? String ?? "120"
        return "v\(short) (\(build))"
    }

    public var body: some View {
        NavigationView {
            Form {
                // 1. 掃描核心設定 (Camera & Scan)
                Section(header: Text("相機與掃描")) {
                    Toggle("掃描輔助引導線", isOn: $viewModel.useScanGuide)
                    Toggle("掃描前自動對焦", isOn: $viewModel.autofocusBeforeScan)
                    Toggle("觸控螢幕拍照", isOn: $viewModel.touchToScan)
                    Toggle("靜音快門", isOn: $viewModel.disableShutterSound)
                    Toggle("觸覺震動回饋", isOn: $viewModel.hapticFeedback)

                    Picker("自訂定時器", selection: $viewModel.cameraTimerSeconds) {
                        Text("關閉").tag(0)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                        Text("7 秒").tag(7)
                    }
                }

                // 2. 雙頁掃描設置 (Two-Page Scanning)
                Section(
                    header: Text("雙頁跨頁掃描模式"),
                    footer: Text("選擇「2 頁」模式時，單次快門會沿書本中縫自動拆分為左右兩頁，此處決定存檔順序。")
                ) {
                    Picker("翻頁順序", selection: $viewModel.twoPagesOrderLTR) {
                        Text("從左到右 (由左翻書)").tag(true)
                        Text("從右到左 (直排/傳統翻書)").tag(false)
                    }
                }

                // 3. AI 影像處理預設設定
                Section(
                    header: Text("AI 影像處理預設值"),
                    footer: Text("曲面平整需要真實模型輸出的 25x25 網格；目前未接上模型時會自動跳過，不會合成假曲面破壞照片。")
                ) {
                    Toggle("自動透視裁剪邊界", isOn: $viewModel.presetAutoCrop)
                    Toggle("曲面平整展開 (Dewarp)", isOn: $viewModel.presetCurveCorrection)
                    Toggle("智慧色彩校正與去底色", isOn: $viewModel.presetColorEnhance)
                    Toggle("使文本變暗 (強化對比)", isOn: $viewModel.presetTextDarken)
                }

                // 4. 存檔與匯出 (Storage & Export)
                Section(header: Text("存檔與匯出")) {
                    Toggle("自動備份照片至系統相簿", isOn: $viewModel.autoSaveToGallery)

                    Picker("預設掃描解析度", selection: $viewModel.scanResolution) {
                        ForEach(ScanResolution.allCases) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }

                    HStack {
                        Text("資料夾名稱")
                        Spacer()
                        TextField("Scan", text: $folderName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { applyFolderName() }
                    }
                }

                Section(header: Text("頁面管理")) {
                    HStack {
                        Text("目前已掃描頁數")
                        Spacer()
                        Text("\(viewModel.pageCount) 頁")
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Text("清除所有掃描頁面")
                    }
                    .disabled(viewModel.pageCount == 0)
                }

                // 5. 關於與版本資訊（實際讀取 Bundle，不再寫死）
                Section(header: Text("關於")) {
                    HStack {
                        Text("vFlat-iOS 版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("核心幾何演算法")
                        Spacer()
                        Text("25x25 Freeform Dewarp")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("AI 推論加速")
                        Spacer()
                        Text("Apple Neural Engine")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("相機目前解析度")
                        Spacer()
                        Text(viewModel.cameraManager.resolution.rawValue)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("相機實際幀率")
                        Spacer()
                        Text(viewModel.cameraManager.activeFrameRate > 0
                             ? String(format: "%.0f fps", viewModel.cameraManager.activeFrameRate)
                             : "量測中…")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        applyFolderName()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                }
            }
            .alert("清除所有掃描頁面？", isPresented: $showingResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    viewModel.clearAllPages()
                }
            } message: {
                Text("此動作會刪除裝置內所有已掃描的頁面與縮圖，無法復原。")
            }
        }
    }

    private func applyFolderName() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.currentFolder = trimmed.isEmpty ? "Scan" : trimmed
    }
}
