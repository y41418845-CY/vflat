import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: ScannerViewModel
    @AppStorage("vflat_camera_lens") private var lensRaw: String = CameraLens.ultraWide.rawValue
    @AppStorage("vflat_scan_resolution") private var resRaw: String = ScanResolution.ultraHD4K.rawValue
    @AppStorage("vflat_camera_timer") private var timer: Int = 0
    @AppStorage("vflat_auto_capture") private var autoCapture: Bool = false
    @AppStorage("vflat_touch_to_scan") private var touchScan: Bool = false
    @AppStorage("vflat_autofocus") private var autofocus: Bool = true
    @AppStorage("vflat_disable_shutter_sound") private var mute: Bool = false
    @AppStorage("vflat_haptic_feedback") private var haptic: Bool = true
    @AppStorage("vflat_scan_guide") private var guide: Bool = true
    @AppStorage("vflat_two_pages_ltr") private var ltr: Bool = true
    @AppStorage("vflat_preset_auto_crop") private var autoCrop: Bool = true
    @AppStorage("vflat_preset_curve_correction") private var curve: Bool = false
    @AppStorage("vflat_preset_color_enhance") private var colorEnhance: Bool = true
    @AppStorage("vflat_preset_text_darken") private var textDarken: Bool = true
    @AppStorage("vflat_ai_save_method") private var aiSave: String = "覆蓋此頁面"
    @AppStorage("vflat_auto_save_to_gallery") private var autoSave: Bool = false
    @AppStorage("vflat_current_folder") private var folder: String = "Scan"
    @AppStorage("vflat_start_screen_mode") private var startScreen: String = "相機取景 (秒開即掃)"
    @State private var showingTrash = false

    var body: some View {
        NavigationView {
            Form {
                Section("相機與硬體拍攝設定") {
                    Picker("相機鏡頭", selection: $lensRaw) {
                        ForEach(CameraLens.allCases) { l in Text(l.displayName).tag(l.rawValue) }
                    }
                    Picker("掃描解析度", selection: $resRaw) {
                        ForEach(ScanResolution.allCases) { r in Text(r.displayName).tag(r.rawValue) }
                    }
                    Picker("定時拍照器", selection: $timer) {
                        Text("關閉").tag(0); Text("2s").tag(2); Text("3s").tag(3); Text("5s").tag(5); Text("7s").tag(7)
                    }
                    Toggle("自動掃描 (防手震)", isOn: $autoCapture)
                    Toggle("觸控螢幕拍照", isOn: $touchScan)
                    Toggle("拍照前自動對焦", isOn: $autofocus)
                    Toggle("靜音快門", isOn: $mute)
                    Toggle("觸覺震動回饋", isOn: $haptic)
                    Toggle("相機輔助引導格線", isOn: $guide)
                }
                Section("掃描與書籍後處理設定") {
                    Picker("雙頁翻頁順序", selection: $ltr) {
                        Text("從左到右").tag(true); Text("從右到左").tag(false)
                    }
                    Toggle("自動透視裁剪邊界", isOn: $autoCrop)
                    Toggle("25x25 自由曲面展開 (Dewarp)", isOn: $curve)
                    Toggle("智慧色彩校正與純白去底色", isOn: $colorEnhance)
                    Toggle("使文字變暗", isOn: $textDarken)
                    Picker("AI 修復儲存方式", selection: $aiSave) {
                        Text("覆蓋此頁面").tag("覆蓋此頁面"); Text("另存新頁面").tag("另存新頁面")
                    }
                }
                Section("PDF 與檔案匯出設定") {
                    Toggle("自動備份新掃描至相簿 (.jpg)", isOn: $autoSave)
                    TextField("預設資料夾名稱", text: $folder)
                }
                Section("系統偏好與頁面管理") {
                    Picker("啟動畫面", selection: $startScreen) {
                        Text("相機取景").tag("相機取景 (秒開即掃)"); Text("資料庫首頁").tag("資料庫首頁")
                    }
                    Button("垃圾桶 (最近刪除)") { showingTrash = true }
                    Text("目前已儲存頁數: \(vm.pageStore.count) 頁")
                    Button("移至垃圾桶 (清除所有)", role: .destructive) { vm.pageStore.deleteAll() }
                }
                Section("關於與技術規格") {
                    Text("版本號: v1.5.9 (Build 159)")
                    Text("曲面拉平技術: 25x25 Dynamic Spline + Metal GPU")
                    Text("AI 離線加速: Apple Neural Engine / CoreImage")
                    Text("相機實際幀率: \(vm.cameraManager.activeFrameRate) fps")
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showingTrash) { TrashBinView() }
        }
    }
}
