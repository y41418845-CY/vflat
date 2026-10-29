import SwiftUI

/// 完整復刻 REA 逆向成果中之 vFlat 設定中心 (Settings View)
/// 涵蓋相機掃描、雙頁跨頁邏輯、影像增強模型預設值與系統行為配置
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
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
                Section(header: Text("雙頁跨頁掃描模式"), footer: Text("選擇掃描雙頁書本時，單次快門自動拆分為左右兩頁的存檔順序。")) {
                    Picker("翻頁順序", selection: $viewModel.twoPagesOrderLTR) {
                        Text("從左到右 (由左翻書)").tag(true)
                        Text("從右到左 (直排/傳統翻書)").tag(false)
                    }
                }

                // 3. AI 影像處理預設設定 (Image Processing & Models)
                Section(header: Text("AI 影像處理預設值"), footer: Text("對應 vFlat 原版深度學習管線：自動透視切邊、25x25 曲面平整、手指塗抹修復與文字清晰化。")) {
                    Toggle("自動透視裁剪邊界 (PPTP)", isOn: $viewModel.presetAutoCrop)
                    Toggle("曲面平整展開 (Dewarp)", isOn: $viewModel.presetCurveCorrection)
                    Toggle("智慧色彩校正與去底色", isOn: $viewModel.presetColorEnhance)
                    Toggle("邊緣手指偵測與消除修復", isOn: $viewModel.presetFingerRemoval)
                    Toggle("使文本變暗 (強化對比)", isOn: $viewModel.presetTextDarken)
                }

                // 4. 存檔與匯出 (Storage & Export)
                Section(header: Text("存檔與匯出")) {
                    Toggle("自動備份照片至系統相簿", isOn: $viewModel.autoSaveToGallery)
                    Picker("預設掃描解析度", selection: $viewModel.scanResolution) {
                        Text("超高畫質 4K (2160p)").tag("4K")
                        Text("標準高畫質 (1080p)").tag("1080p")
                    }
                }

                // 5. 關於與版本資訊
                Section(header: Text("關於")) {
                    HStack {
                        Text("vFlat-iOS 版本")
                        Spacer()
                        Text("v0.8.0 (REA 原生重構)")
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
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                }
            }
        }
    }
}
