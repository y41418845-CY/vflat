import SwiftUI

#if canImport(UIKit)
import UIKit

/// 完整復刻並對齊原廠 vFlat 設定中心 (Settings View)
/// 涵蓋：1. 相機與硬體拍攝設定；2. 掃描與書籍後處理設定；3. PDF 與檔案匯出設定；4. 啟動畫面設定與垃圾桶 (最近刪除)
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScannerViewModel

    @State private var folderName: String
    @State private var showingResetConfirm: Bool = false
    @State private var showingTrashBin: Bool = false

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
        self._folderName = State(initialValue: viewModel.currentFolder)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.4.1"
        let build = info?["CFBundleVersion"] as? String ?? "141"
        return "v\(short) (\(build))"
    }

    public var body: some View {
        NavigationView {
            Form {
                // 0. 旗艦功能解鎖狀態 (去除所有商業限制)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))
                            Text("旗艦功能全解鎖 (無限制版)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                        }

                        Text("已徹底去除原廠商業訂閱、每日 OCR 配額、浮水印與廣告干擾。所有 25×25 自由曲面展開、AI 去陰影去手指、可搜尋 PDF 匯出均無限次數使用，100% 本地離線保護隱私。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 4)
                }

                // 1. 相機與硬體拍攝設定 (對齊原廠 Camera & Lens Settings)
                Section(
                    header: Text("項目 1. 相機與硬體拍攝設定"),
                    footer: Text("原廠強烈推薦使用超廣角相機，在相同手持距離下能提供開闊視野，消除近距離對焦模糊與框線亂跳問題。")
                ) {
                    Picker("相機鏡頭", selection: $viewModel.cameraLens) {
                        ForEach(CameraLens.allCases) { lens in
                            Text(lens.displayName).tag(lens)
                        }
                    }

                    Picker("掃描解析度", selection: $viewModel.scanResolution) {
                        ForEach(ScanResolution.allCases) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }

                    Picker("定時拍照器", selection: $viewModel.cameraTimerSeconds) {
                        Text("關閉").tag(0)
                        Text("2 秒").tag(2)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                        Text("7 秒").tag(7)
                    }

                    Toggle("自動掃描 (防手震穩定自動拍)", isOn: $viewModel.isAutoCaptureEnabled)
                    Toggle("觸控螢幕拍照 (點擊畫面快門)", isOn: $viewModel.touchToScan)
                    Toggle("拍照前自動對焦", isOn: $viewModel.autofocusBeforeScan)
                    Toggle("靜音快門 (關閉拍照聲)", isOn: $viewModel.disableShutterSound)
                    Toggle("觸覺震動回饋", isOn: $viewModel.hapticFeedback)
                    Toggle("相機輔助引導格線", isOn: $viewModel.useScanGuide)
                }

                // 2. 掃描與書籍後處理設定 (對齊原廠 Scan & Processing Settings)
                Section(
                    header: Text("項目 2. 掃描與書籍後處理設定"),
                    footer: Text("包含書籍中縫展開、雙頁分割閱讀方向、邊界修剪與 AI 魔法修復設定。")
                ) {
                    Picker("雙頁翻頁順序", selection: $viewModel.twoPagesOrderLTR) {
                        Text("從左到右 (左翻書 / 橫排)").tag(true)
                        Text("從右到左 (右翻書 / 直排)").tag(false)
                    }

                    Toggle("自動透視裁剪邊界", isOn: $viewModel.presetAutoCrop)
                    Toggle("25x25 自由曲面平整展開 (Dewarp)", isOn: $viewModel.presetCurveCorrection)
                    Toggle("智慧色彩校正與純白去底色", isOn: $viewModel.presetColorEnhance)
                    Toggle("使文字變暗 (文字筆畫加深)", isOn: $viewModel.presetTextDarken)

                    Picker("AI 修復儲存方式", selection: $viewModel.aiSaveMethod) {
                        ForEach(AISaveMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }

                // 3. PDF 與檔案匯出設定 (對齊原廠 Export Settings)
                Section(
                    header: Text("項目 3. PDF 與檔案匯出設定"),
                    footer: Text("可設定自動備份相簿、資料夾名稱以及匯出 PDF 的預設規格。")
                ) {
                    Toggle("自動備份新掃描至相簿 (.jpg)", isOn: $viewModel.autoSaveToGallery)

                    HStack {
                        Text("預設資料夾名稱")
                        Spacer()
                        TextField("Scan", text: $folderName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { applyFolderName() }
                    }

                    HStack {
                        Text("PDF 預設尺寸")
                        Spacer()
                        Text("A4 / 適應寬度 / 原圖")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("可搜尋 PDF (OCR 文字層)")
                        Spacer()
                        Text("自動嵌入 (支援反白複製)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("PDF 密碼保護")
                        Spacer()
                        Text("匯出時可自訂加密")
                            .foregroundColor(.secondary)
                    }
                }

                // 4. 系統行為與頁面管理 (對齊原廠 啟動畫面設定 與 垃圾桶)
                Section(
                    header: Text("項目 4. 系統偏好與頁面管理"),
                    footer: Text("垃圾桶可保存最近 30 天內刪除的頁面，支援單頁復原、批次還原與徹底清空。")
                ) {
                    Picker("用...啟動應用", selection: $viewModel.startScreenMode) {
                        ForEach(StartScreenMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Button {
                        showingTrashBin = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("垃圾桶 (最近刪除)")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(viewModel.trashCount) 頁")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }

                    HStack {
                        Text("目前已儲存頁數")
                        Spacer()
                        Text("\(viewModel.pageCount) 頁")
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        showingResetConfirm = true
                    } label: {
                        Text("移至垃圾桶 (清除所有頁面)")
                    }
                    .disabled(viewModel.pageCount == 0)
                }

                // 5. 關於與版本資訊
                Section(header: Text("關於與技術規格")) {
                    HStack {
                        Text("版本號")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("曲面拉平技術")
                        Spacer()
                        Text("25x25 Dynamic Spline + Metal GPU")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("AI 離線加速")
                        Spacer()
                        Text("Apple Neural Engine / CoreImage")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("相機實際幀率")
                        Spacer()
                        Text(viewModel.cameraManager.activeFrameRate > 0
                             ? String(format: "%.0f fps", viewModel.cameraManager.activeFrameRate)
                             : "60 fps")
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
            .sheet(isPresented: $showingTrashBin) {
                TrashBinView(viewModel: viewModel)
            }
            .alert("移至垃圾桶？", isPresented: $showingResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("移至垃圾桶", role: .destructive) {
                    viewModel.clearAllPages()
                }
            } message: {
                Text("所有頁面將移入垃圾桶並保留 30 天，在此期間您可以隨時還原。")
            }
        }
    }

    private func applyFolderName() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.currentFolder = trimmed.isEmpty ? "Scan" : trimmed
    }
}
#endif
