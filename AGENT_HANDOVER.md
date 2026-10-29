# AI Agent 專案交接與工程維護文件 (Handover Document)

> **專案名稱**：vFlat 逆向工程與 iOS 原生重構專案 (`vFlat-iOS`)  
> **專案版本**：`v0.9.1`  
> **最後更新時間**：2026-10-29  
> **遠端儲存庫**：`https://github.com/y41418845-CY/vflat` (預設分支：`master`)  
> **本地工作目錄**：`h:\我的雲端硬碟\工具程式\vflat\`

---

## 一、專案全貌與核心目標 (Project Overview)

本專案承接兩大核心任務：
1. **vFlat 核心演算法逆向工程 (REA Analysis)**：從官方發行之 Android 安裝包（XAPK）中，解構其原生 C++ 函式庫、TFLite 神經網路模型與 GPU 著色器，徹底還原出「25×25 自由曲面展平（Freeform Dewarping）」之數學幾何模型與模型輸出反混淆機制。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：以現代 Apple 原生技術（SwiftUI + AVFoundation + Metal + Vision）完全重新打造零延遲、高幀率（60fps）、極低功耗的 iOS 書本與文件掃描器，並建置 GitHub Actions 雲端自動編譯管線，一鍵輸出可側載之 `vFlat.ipa`。

---

## 二、逆向工程成果與核心數學規格 (REA Findings)

### 1. 25×25 自由曲面展平演算法 (`libnative-scan.so`)
* **神經網路模型**：`assets/models/freeform_v3_2.dat`（5.17MB TFLite 卷積神經網路）。
* **輸出座標反混淆 (`freeform::model::deobfuscate`)**：
  * 模型輸出 1250 個浮點數（625 對 $(x, y)$ 座標），但順序經過置換打散。
  * 原生 C++ 透過長度為 1250 的索引置換表（Permutation Table）在記憶體中還原為標準 $25 \times 25$ 拓撲順序。
* **物理展開長度積分 (`freeform::model::calcOutputSize`)**：
  * 包含 25 行橫向曲線，每行 24 個線段。
  * 每行計算歐幾里得微分弧長：$\text{ArcLength}_k = \sum_{i=0}^{23} \sqrt{(x_{k, i+1} - x_{k, i})^2 + (y_{k, i+1} - y_{k, i})^2}$。
  * 取 25 行平均展開長度：$\text{AvgWidth} = \frac{1}{25} \sum_{k=0}^{24} \text{ArcLength}_k$。
  * 乘上原始相機輸入解析度與長寬比純量 $S$，換算得出物理展平後的目標像素尺寸。

### 2. 輔助 AI 模型清單 (`assets/models/`)
* `freeform_v3_2.dat` (5.17MB)：3D 自由曲面重建。
* `pptp_v1_1_0.dat` (6.03MB) / `optp_v3_3.dat` (2.09MB)：透視與正交角點校正。
* `finger_mask_v1_1.dat` (338KB)：邊緣按壓手指語意分割。
* `inpainter_v1_0_0.dat` (5.88MB)：手指抹除背景修復。
* `deblur_v1.1.dat` (15.72MB)：手震文字去模糊神經網路。

---

## 三、重大功能修復與技術突破 (v0.9.1 關鍵成果)

### 1. 拍照快門按鈕無功能問題徹底修復
* **根本原因**：舊版 `triggerCapture()` 僅累加計數與觸發輕微震動，未從相機管線採集畫面，未更新 `lastCapturedImage` 且缺乏視覺反饋。
* **解決方案**：
  * 在 `CameraManager.swift` 中建立線程安全的 `latestPixelBuffer` 緩存與 `captureCurrentFrame() -> UIImage?` 高畫質抓幀方法。
  * 在 `ScannerViewModel.swift` 實作原生相機白光快門閃爍動效（`isShutterFlashing`）、真實影格存檔與 `autoSaveToGallery` 相簿寫入。
  * 在 `ScanControlBar.swift` 將左下角縮圖由靜態圖示升級為即時渲染的實體照片縮圖，點擊直接進入 `DocumentDetailView` 檢視拍攝成果。

### 2. 邊緣辨識「抓不到物品上方、切邊偏差」問題徹底修復
* **根本原因**：
  1. 舊版 `VNDetectRectanglesRequest` 設定 `maximumObservations = 1`，當物品（如藥盒或文件）上半部有文字或不同色塊時，Vision 誤將下半部高對比區塊識別為獨立矩形，拋棄了上方結構。
  2. 舊版未做 Aspect-Fill 座標映射：相機影格為 9:16（0.5625），而 iPhone 全螢幕為 19.5:9（~0.461）。螢幕以高度填滿時左右被裁切，若直接使用原始標準化座標乘以螢幕寬度，會造成嚴重的水平與垂直幾何錯位。
* **解決方案**：
  * **多候選最大面積評估（Largest Bounding Box）**：放寬 `maximumObservations = 8`、`quadratureTolerance = 45.0`、`minimumAspectRatio = 0.1`，計算所有候選四邊形面積，挑選整體外輪廓最大之框線，徹底解決「上方抓不到邊」的困擾。
  * **物理級 Aspect-Fill 螢幕投影**：在 `ScanGuideOverlay.swift` 實作 `aspectFillPoint()`，精準補償相機與螢幕比例差帶來的位移，使框線與螢幕中物品 100% 貼合。
  * **Metal 著色器 1:1 比例保真**：在 `Shaders.metal` 中以 Aspect-Fill 取樣相機紋理，物品在螢幕上完全維持 1:1 真實物理比例，絕無拉伸扭曲。

---

## 四、iOS 原生專案代碼結構 (`ios/`)

```
ios/
├── Package.swift                    # Swift 5.9 SPM 套件定義 (iOS 16.0+)
├── Info.plist                       # 相機與相簿權限宣告
├── README.md                        # Xcode 本機開啟與執行手冊
├── Sources/
│   ├── Core/                        # 核心底層驅動與數學模組
│   │   ├── Camera/                  # AVCaptureSession 4K/60fps 串流採集與即時靜態抓幀
│   │   ├── Motion/                  # CoreMotion 陀螺儀 60Hz 俯拍水平傾角感測
│   │   ├── Dewarp/                  # 25x25 幾何弧長微分展開、Vision 多候選矩形偵測與 EMA 防抖
│   │   └── Metal/                   # Metal MSL Aspect-Fill 渲染器與零拷貝紋理快取
│   ├── UI/                          # 現代 SwiftUI 介面
│   │   ├── Views/                   # CameraScanView、ScanControlBar、ScanGuideOverlay、DocumentDetailView、PhotoImportPickerView、SettingsView
│   │   └── ViewModels/              # ScannerViewModel 主狀態協調器
│   └── vFlatApp/                    # 應用程式 App 進入點
└── Tests/
    └── DewarpTests/                 # 幾何數學單元測試
```

---

## 五、雲端 CI/CD 自動編譯與發布管線

* **設定檔**：`.github/workflows/build_ios.yml`
* **工程生成**：`project.yml` 搭配 `xcodegen`。
* **建置環境**：GitHub Actions `macos-15` (macOS Sequoia + Xcode 16)。
* **輸出機制**：
  * 自動編譯產出未簽名之 `vFlat.app` 並打包為 `vFlat.ipa`。
  * 自動下載至本地專案目錄 `vFlat.ipa`。
* **實體手機安裝路徑**：
  * 使用 Windows 版 **Sideloadly** 拖入 `vFlat.ipa` -> 輸入個人 Apple ID 即可一鍵簽名側載至實體 iPhone。

---

## 六、開發規範與維護守則 (Project Rules)

後續修改此專案時，**必須持續嚴格遵守以下準則**：
1. **版本號嚴格遞增**：凡修改任何程式碼、工作流程或設定，必須同步更新根目錄之 `VERSION` 檔案（語意化版本 `vX.Y.Z`）。
2. **Git Commit 繁體中文註解**：每次修改完成後即時執行 `git add .` 與 `git commit`，訊息必須使用繁體中文（台灣習慣）與 Conventional Commits。
3. **一鍵啟動檔嚴禁中文字元**：任何 `.bat` / `.sh` 腳本檔案內部嚴禁包含任何中文字元，確保在 Windows 命令列環境執行不當機。
4. **安全防護**：推送到遠端儲存庫時嚴禁硬編碼任何 GitHub Personal Access Token 或憑證金鑰。
