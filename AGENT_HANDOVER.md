# AI Agent 專案交接與工程維護手冊 (Agent Handover Document)

> **專案名稱**：vFlat 逆向工程與 iOS 原生重構專案 (`vFlat-iOS`)  
> **專案版本**：`v1.2.4`（Build `124`）  
> **最後更新時間**：2026-10-30  
> **遠端儲存庫**：`https://github.com/y41418845-CY/vflat`（預設分支：`master`）  
> **本地工作目錄**：`g:\我的雲端硬碟\工具程式\vflat\`  
> **接手重點提示**：請新進 AI Agent 優先閱讀本手冊與全域規範。本專案嚴格遵守「無外掛純原生（Swift / Metal / Vision / PDFKit）」與「高幀率（60fps）零延遲」標準；**唯一支援的 CI 建置路徑是 XcodeGen**。

---

## 一、專案核心定位與目標 (Project Mission)

本專案承接兩大核心任務：

1. **vFlat 核心演算法與模型深度逆向 (REA Reverse Engineering Analysis)**：
   - 從官方 Android 發行版（XAPK）中解構其底層原生 C++ 函式庫（`libnative-scan.so` 等）、TFLite 神經網路模型（`freeform_v3_2.dat`, `optp_v3_3.dat`）與 GPU 渲染架構。
   - 破譯 VoyagerX 專利防逆向混淆（FlatBuffers vtable MSB 混淆、1250 浮點數輸出置換表、ARM NEON SIMD 向量化預處理、Eigen RQ 矩陣分解）。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：
   - 採用現代 Apple 原生技術棧（SwiftUI + AVFoundation + Metal + Vision + PDFKit）打造 60fps、極低功耗之書本與文件掃描器。
   - 實現自動穩定快門、多濾鏡增強、多頁 PDF 壓縮打包、放大鏡手動裁切、條碼/QR Code 解析、25×25 自由曲面 GPU 展平（需真實模型網格）與雙頁中縫自動分割。
   - GitHub Actions 雲端管線：**先跑單元測試，通過後才打包**，輸出可透過 Sideloadly 側載之 `vFlat.ipa`。

---

## 二、系統架構與關鍵模組切分 (Architecture & Components)

```
ios/
├── Package.swift                    # Swift 5.9 SPM 套件定義 (iOS 16.0+，本機除錯備援)
├── Info.plist                       # 由 project.yml 產生：相機 / 相簿讀取 / 相簿寫入權限
├── README.md                        # Xcode 本機工程開啟說明
├── Sources/
│   ├── Core/                        # 核心底層驅動與影像演算法
│   │   ├── Camera/                  # AVCaptureSession 4K/1080p 串流、60fps 嘗試、補光燈、單張抓幀 (CameraManager.swift)
│   │   ├── Motion/                  # CoreMotion 60Hz 俯拍水平傾角感測 (MotionSensor.swift)
│   │   ├── Dewarp/                  # 視覺偵測、曲面展平幾何與雙頁分割
│   │   │   ├── DocumentDetector.swift    # Vision 雙引擎邊界偵測（720p 推論）+ 條碼節流 + detectOnce 三種重載
│   │   │   ├── AutoCaptureDetector.swift # 幀間位移穩定度判定（自動快門觸發器）
│   │   │   ├── DetectedBarcode.swift     # 條碼/QR Code 資料模型（自訂 == 排除 id）
│   │   │   ├── BookPageSplitter.swift    # 書本中縫光度定位與雙頁自動分割
│   │   │   ├── DewarpGeometry.swift      # 25x25 弧長微分積分尺寸計算 + deobfuscate
│   │   │   ├── DewarpMesh.swift          # Metal 頂點與三角網格拓撲產生器
│   │   │   └── DocumentRectifier.swift   # 幾何階段（透視裁切）+ 濾鏡階段分離
│   │   ├── Storage/                 # ScanPageStore：JPEG 落盤、index.json、縮圖快取、批次讀取
│   │   ├── OCR/                     # OCRService：VNRecognizeTextRequest（zh-Hant/zh-Hans/en-US）
│   │   ├── Export/                  # 文件命名與 PDFKit 匯出服務
│   │   │   ├── DocumentNamingService.swift # 時間戳智慧命名規則器
│   │   │   └── PDFExporter.swift           # 原生 PDF 合成、A4/Letter 版面與壓縮品質
│   │   └── Metal/                   # Metal MSL Aspect-Fill 著色器與離屏 GPU 展平
│   │       ├── Shaders.metal               # 頂點/片段著色器（dewarpStrength 混合、edgeFeather）
│   │       ├── ShaderTypes.h               # C/Metal 共享結構定義
│   │       ├── DewarpUniforms.swift        # Swift Uniforms 映射
│   │       ├── MetalLibraryProvider.swift  # 統一解析 metallib（含 bundle 掃描與執行期編譯後備）
│   │       ├── MetalShaderSource.swift     # 執行期著色器原始碼（必須與 Shaders.metal 同步）
│   │       ├── MetalDewarpRenderer.swift   # MTKView 60fps 即時渲染器
│   │       └── MetalOffscreenDewarper.swift# 拍下後高畫質 GPU 離屏 25x25 展平（無真實網格時原樣回傳）
│   ├── UI/                          # 現代 SwiftUI 介面層
│   │   ├── Views/
│   │   │   ├── CameraScanView.swift        # 主取景畫面（條碼膠囊、自動快門進度環、倒數、錯誤橫幅）
│   │   │   ├── ScanControlBar.swift        # 底部控制列（單雙頁切換、縮圖、快門禁用態、倒數）
│   │   │   ├── ScanGuideOverlay.swift      # 邊界導引框與十字姿態儀（受 useScanGuide 控制）
│   │   │   ├── DocumentDetailView.swift    # 單頁檢視、6 大濾鏡、OCR 結果、裁剪、刪除
│   │   │   ├── LoupeCropView.swift         # 4 角點手動微調與 2.2x 放大鏡（具名座標系）
│   │   │   ├── PDFExportSheet.swift        # PDF 匯出面板（吃 ScanPage + Store，背景解碼）
│   │   │   ├── PhotoImportPickerView.swift # 真 PhotosPicker 多選 + 批次選項
│   │   │   └── SettingsView.swift          # 偏好設定頁（版本讀 Bundle、解析度 enum）
│   │   └── ViewModels/              # ScannerViewModel 主狀態協調器
│   └── vFlatApp/                    # 應用程式 App 進入點 (vFlatApp.swift)
└── Tests/
    └── DewarpTests/                 # 幾何、deobfuscate、DetectedBarcode、AutoCaptureDetector 測試
```

### 資料流向 (Data Pipeline)

1. **相機串流輸入**：`AVCaptureVideoDataOutput` 盡可能以 60fps 採集 4K 或 1080p `CVPixelBuffer`；實際幀率寫入 `CameraManager.activeFrameRate`。
2. **GPU 即時預覽**：透過 `CVMetalTextureCache` 零拷貝導入 Metal 著色器，Aspect-Fill 映射至全螢幕；繪製時保留 `CVMetalTexture` 參照並縮小鎖範圍。
3. **神經視覺邊緣運算**：
   - `DocumentDetector` 在專屬序列佇列上運作，影格先降採樣至 720p 才進 Vision，避免 4K 造成推論堆積。
   - 條碼辨識有獨立節流，不與邊界偵測同頻。
   - 邊界結果經 EMA 平滑後發佈到主執行緒。
4. **自動快門判定**：`AutoCaptureDetector` 監控角點位移 $\Delta \le 0.02$ 持續 500ms，達標自動觸發快門（含 1.8s 防連擊）。
5. **拍照（主執行緒只做輕量工作）**：
   - 用 `latestPixelBufferSnapshot()` 取得當下影格。
   - 對**同一個影格**呼叫 `DocumentDetector.detectOnce(in:)`，避免平滑與 350ms 滯後造成裁切錯位。
   - 播放快門音/觸覺/白閃後立即把重活丟到 `Task.detached`。
6. **後處理（背景佇列）**：
   - 幾何階段：方向正規化 → 四邊形透視拉正 →（雙頁模式）中縫分割。
   - 濾鏡階段：對每個幾何頁套用 6 大濾鏡之一。
   - 落盤：`ScanPageStore.append` 寫入 `processed`（已上色）與 `raw`（已裁切未上色）兩份 JPEG，並更新 `index.json` 與縮圖快取。
7. **後續操作**：
   - 切換濾鏡／重新裁切都從 `raw` 重算，不重拍、不累積壓縮損失。
   - PDF 匯出時才由 `ScanPageStore.loadImages(for:)` 從磁碟解碼。

---

## 三、關鍵技術決策與約定 (Technical Decisions & Conventions)

1. **零第三方外部依賴 (YAGNI & Pure Native)**：
   - 堅持使用 Apple 原生框架（AVFoundation、Vision、Metal、CoreImage、CoreMotion、PDFKit、SwiftUI）。
   - 拒絕 OpenCV-iOS、Tesseract C++ 等龐大依賴。
2. **雙引擎自適應抓框架構 (Dual-Engine Detection)**：
   - **主引擎**：`VNDetectDocumentSegmentationRequest`，抗雜訊、抗手指遮擋。
   - **輔助引擎**：`VNDetectRectanglesRequest` 多候選四邊形。
3. **Aspect-Fill 物理級座標映射**：
   - 嚴格區分相機感光元件座標系與 iPhone 全螢幕座標系，導引層以 `aspectFillPoint()` 補償。
4. **幾何與色彩分離**：
   - `DocumentRectifier.geometryCorrected` 只做裁切，`applyFilter` 只做色彩。任何濾鏡切換都不應再次裁切。
5. **頁面一律落盤**：
   - 禁止再把 `[UIImage]` 全解析度陣列長期保存在記憶體。
6. **禁止合成假資料**：
   - 沒有真實 25×25 模型網格時，`MetalOffscreenDewarper.dewarpImage` 直接回傳原圖。
   - UI 不得再出現假樣張、假頁數（舊版 `capturedPageCount = 182` 已移除）。
7. **專案約定與規範**：
   - 每次代碼修改**必須同步遞增** `VERSION`（`vX.Y.Z`），CI Release tag 直接讀此檔。
   - Git Commit 必須使用繁體中文清楚註記修改原因。
   - 一鍵啟動檔（`.bat` / `.sh`）嚴禁包含任何中文字元。
   - 修改 `Shaders.metal` / `ShaderTypes.h` 必須同步 `MetalShaderSource.swift`。

---

## 四、深度逆向工程技術手冊 (REA In-Depth Technical Dossier)

> 本節完整收錄針對 vFlat Android 官方發行版 (`com.voyagerx.scanner`) 執行二進位反組譯、模型架構剖析與特徵比對之全方位技術細節。

### 1. 原生 ARM64 二進位函式庫剖析 (`libnative-scan.so`)

- **二進位資訊**：ELF 64-bit LSB shared object, ARM aarch64，大小 362,560 位元組，以 C++ 編寫並連結 Eigen 線性代數庫與 Android NDK。

#### (1) `Scan.btf`（點陣圖向量化正規化管線）
- **記憶體位址**：虛擬偏移 `0x1a9b0`，共 304 條機器碼指令。
- **演算法核心**：利用 ARM NEON SIMD 向量暫存器進行批次像素轉換。
  ```armasm
  fcvtl    v0.4s, v0.4h
  ucvtf.4s v0, v0
  fmov     v1.4s, #1.00000000
  fdiv.4s  v0, v0, 255.0f
  ```
- **技術意義**：相機輸入的 8 位元整數影像緩衝區（`[0..255]`）不經過通用 CPU 迴圈，而是直接透過 NEON 向量除法快速轉換為 `[0.0..1.0]` 單精度浮點數張量，作為神經網絡的直接輸入。

#### (2) `freeform::model::deobfuscate`（1250 浮點數反混淆解密）
- **記憶體位址**：虛擬偏移 `0x1c1a8`，共 452 條機器碼指令。
- **混淆機制**：
  - 自由曲面模型輸出維度為 $25 \times 25 \times 2 = 1250$ 個浮點數（即 625 對 $(x, y)$ 網格頂點座標）。
  - VoyagerX 為了防止模型輸出被直接抓取重用，在模型輸出層對這 1250 個浮點數實施了**全排列打散混淆 (Permutation Shuffle)**。
- **解混淆核心**：
  - 二進位內部內建了一張長度為 1250 的 32 位元整數置換表（Permutation Index Table）。
  - 函式透過置換表將亂序的一維陣列重排至連續的二維 $25 \times 25$ 網格結構中。
  - iOS 重構版對應實作：`DewarpGeometry.deobfuscate(shuffledPoints:permutationTable:)`（已有單元測試）。

#### (3) `Scan.otr` 與 `freeform::remap::fillRemapBuffer`（網格紋理映射）
- **記憶體位址**：`0x1afec`，跳轉至 `freeform::remap::fillRemapBuffer`。
- **功能**：根據反混淆後還原的 25x25 拓撲節點，進行雙線性網格插值，計算相機原始影像與目標展開平面之間的雙向 UV 貼圖紋理緩衝區，提供給 GPU 片段著色器做雙邊採樣拉平。

#### (4) `calcRQDecomp3x3`（透視單應性矩陣 RQ 分解）
- **記憶體位址**：虛擬偏移 `0x1cabc`，共 768 條機器碼指令。
- **數學原理**：
  - 使用 Eigen C++ 線性代數庫計算 $3 \times 3$ 平面單應性矩陣（Homography Matrix $H$）的 RQ 矩陣分解：
    $$H = R \cdot Q$$
    其中 $R$ 為上三角矩陣（包含內參幾何縮放與剪切），$Q$ 為正交旋轉矩陣。
  - 從正交矩陣 $Q$ 中分解出歐拉角（Euler Angles）：俯仰角（Pitch）、翻滾角（Roll）與偏航角（Yaw），用於判斷手機與書本平面的俯拍夾角與透視變形程度。

---

## 五、v1.2.0 稽核修復紀錄 (Audit Fix Log)

本輪僅處理 **P1 / P2 / P3**（P0 不在本輪範圍，且部分 P0 已於本次一併消除）。

### P1（功能正確性）

| 編號 | 問題 | 修法 |
|---|---|---|
| P1-1 | 拍照後製在主執行緒，造成卡頓 | `ScannerViewModel.processCapture` 改為 `nonisolated` + `Task.detached`；JPEG 編碼與寫檔在背景 |
| P1-2 | 設定頁多項 Toggle 無消費端 | `useScanGuide`、`presetAutoCrop`、`presetColorEnhance`、`presetTextDarken`、`twoPagesOrderLTR`、`scanResolution`、`autoSaveToGallery`、快門音/觸覺/定時器全部接到實際邏輯；移除未實作的「手指移除」 |
| P1-3 | 相簿匯入是 12 格假樣張 | 改為真正 `PhotosPicker` 多選 + `ImportOptions` + `importImages` 落盤 |
| P1-4 | OCR／簽名空實作 | `OCRService` 實作繁中辨識，底部「文字辨識」開啟結果 sheet 可複製；移除空「簽名」按鈕 |
| P1-5 | 裁切使用過期角點 | 拍照當下以同一影格 `detectOnce`；裁切來源改用 `raw` 影像 + 手動角點 `applyCrop` |
| P1-6 | 頁數顯示錯誤（寫死 182） | 一律以 `ScanPageStore.count` 為準；縮圖列顯示實際頁數角標 |

### P2（效能與穩定性）

| 編號 | 問題 | 修法 |
|---|---|---|
| P2-1 | 4K 影格直接餵 Vision | 推論前降採樣至 720p（`inferenceWidth = 720`） |
| P2-2 | 所有頁面以 `[UIImage]` 佔記憶體 | `ScanPageStore` 落盤 + 縮圖快取 + 匯出時才解碼 |
| P2-3 | 預覽未真正開 60fps | `MTKView.preferredFramesPerSecond = min(60, maxFPS)`；相機端依 activeFormat 嘗試 60fps 並記錄實際值 |
| P2-4 | `CVMetalTexture` 未保留、cache 未 flush | 保留 `currentCVTexture` 參照並在換幀後 `CVMetalTextureCacheFlush` |
| P2-5 | detector 競態與狀態污染 | 專屬 `detectionQueue` 收斂狀態、加入 `reset()`、條碼獨立節流 |
| P2-6 | 放大鏡裁切手勢座標漂移 | `.coordinateSpace(name:)` + `DragGesture(coordinateSpace:)`，並把觸控熱區縮到角點 |
| P2-7 | `dewarpStrength` 未被 shader 使用 | `Shaders.metal` 以 `mix(flatUV, texCoord, strength)` 實作；`edgeFeather` 防零除 |

### P3（一致性與整潔）

- 版本來源統一：`VERSION` → CI release tag；UI 版本讀 `Bundle`。
- `project.yml` 統一 CI 建置路徑，補 `NSPhotoLibraryAddUsageDescription`、版本設定、`vFlatTests` target 與 scheme。
- CI 新增 `xcodebuild test`（iPhone 16，失敗回退 iPhone 15）。
- 巢狀 `ObservableObject`（`pageStore`、`cameraManager`、`motionSensor`）以 Combine 轉發 `objectWillChange`。
- `DetectedBarcode` 自訂 `==` 排除每次新建的 `id`。
- 移除死碼與假資料（`isDewarpEnabled`、`presetFingerRemoval`、假頁數、假樣張）。
- 單元測試由 3 項擴充至 12 項（幾何、退化網格、反混淆、條碼、自動快門）。

---

## 六、當前完成進度與驗證狀態 (Current Status)

- [x] Metal 預覽（60fps 目標、Aspect-Fill、texture cache 生命週期）
- [x] 雙引擎視覺抓框 + 720p 推論 + EMA 平滑 + 邊界收縮
- [x] 自動穩定捕捉（位移門檻 + 時間門檻 + 防連擊）
- [x] 拍照零延遲：同影格瞬時偵測 + 背景後製
- [x] 6 大文件濾鏡、幾何/色彩分離、raw 重用
- [x] 頁面落盤（JPEG + index.json + 縮圖快取）
- [x] 繁中離線 OCR + 結果複製
- [x] 真 PhotosPicker 批次匯入 + 選項
- [x] PDF 匯出（背景解碼、A4/Letter/自適應、4 種壓縮）
- [x] 放大鏡 4 角點裁切（具名座標系）
- [x] 雙頁中縫分割（LTR/RTL）
- [x] QR/條碼解析與懸浮膠囊
- [x] 定時拍照倒數、快門音/觸覺開關、補光燈、解析度切換
- [x] GitHub Actions：測試 → 打包 → Release（tag 讀 `VERSION`）
- [x] 單元測試 12 項

> **驗證狀態**：本輪修改在 Windows 環境完成，**沒有 macOS / Xcode 可實際編譯或實機測試**。CI 已改為先跑測試，首次 push 後請以 Actions 結果為準。

---

## 七、待辦事項與下一步行動建議 (TODOs & Next Steps)

1. **接上真實 25×25 自由曲面模型（High Priority）**：
   - 目前 `MetalOffscreenDewarper` 只有在呼叫端提供 625 點真實網格時才會展平；整個 App 尚無模型推論端，因此曲面展平實際上是 no-op。
   - 建議：將 `freeform_v3_2.dat` 轉為 Core ML，輸出 1250 維張量，經 `DewarpGeometry.deobfuscate` 還原為 625 點後傳入 `dewarpGrid`。
   - 修改點：`ScannerViewModel.processCapture` 與 `DocumentRectifier.autoProcessCapture`。
2. **首次在 macOS 上編譯驗證（High Priority）**：
   - 針對 `@MainActor` / `nonisolated` 邊界、`Task.detached` 的 Sendable 警告做一輪清理（本輪以 Swift 5.9 最小併發檢查為準）。
3. **相機取景視野對齊（Medium）**：
   - 微調 `videoZoomFactor`（1.05 ~ 1.15）以貼近原廠視野。
4. **PDF 密碼加密（Medium）**：
   - `UIGraphicsPDFRenderer` 加入 `kCGPDFContextUserPassword`。
5. **大圖檢視與多頁瀏覽（Medium）**：
   - 目前 `DocumentDetailView` 只檢視最後一頁；可加入頁面瀏覽器／縮圖牆。

---

## 八、已知問題、風險與防坑指南 (Known Issues & Gotchas)

1. **曲面展平目前不會生效**：
   - 沒有真實模型網格時 `dewarpImage` 回傳原圖是**刻意設計**。切勿為了「看起來有展平」而合成正弦曲面（舊版 P0-2）。
2. **不可強行使用透視平行拘束 (`withPerspectiveParallelism`)**：
   - 手持拍攝下四邊形非嚴格平行，強行拘束會導致框線劇烈跳動。
3. **Preset 不可切換至 `.photo`**：
   - 相機串流必須維持 `.hd4K3840x2160` 或 `.hd1920x1080`；`.photo` 會讓 videoOutput 掉到 10~15fps。
4. **`CGContext(data:)` 緩衝區生命週期**：
   - 禁止再把 Swift Array 的位址傳給 `CGContext(data:)` 後就讓 Array 離開作用域（舊版 P0-3 懸空指標）。請用 `data: nil` 或自行 `allocate/deallocate`。
5. **xcodegen 會覆寫 `ios/Info.plist`**：
   - 權限與版本請改 `project.yml`，不要只改 plist。
6. **`MetalShaderSource.swift` 是手動同步的副本**：
   - 改 shader 卻忘記同步，會導致「Xcode 內正常、SPM/資源缺失時行為不同」。
7. **FlatBuffers 解析防坑**：
   - 處理 `optp_v3_3.dat` 前務必確認 `0x80000000` MSB 混淆已遮罩（`vdiff &= 0x7FFFFFFF`）。
8. **一鍵腳本編碼防坑**：
   - 根目錄 `.bat` / `.sh` 必須維持純 ASCII。
9. **Windows 主控台顯示 UTF-8 Swift 檔為亂碼**：
   - 這是顯示問題，不是檔案損壞；**切勿**用 PowerShell `Get-Content` / `Set-Content` 批次改寫，曾造成整檔編碼損毀。

---

## 九、版本歷程 (Version History)

| 版本 | 日期 | 重點 |
|---|---|---|
| `v1.2.4` | 2026-10-30 | 修正 DocumentRectifier optional binding 編譯錯誤 |
| `v1.2.3` | 2026-10-30 | 修正 @MainActor 預設引數編譯錯誤（ScannerViewModel convenience init） |
| `v1.2.2` | 2026-10-30 | 修正補光燈假成功、避免對焦鎖定、降低 Metal 快取 flush 頻率 |
| `v1.2.1` | 2026-10-30 | P0 強化：相簿權限確認、移除合成假曲面、CGContext 安全配置、展平網格驗證 |
| `v1.2.0` | 2026-10-30 | P1/P2/P3 稽核修復：背景後製、頁面落盤、真 OCR/相簿匯入、設定接線、Metal/shader 修正、CI 測試與版本統一、12 項單元測試 |
| `v1.1.1` | 2026-10-30 | 修正 DetectedBarcode、相機/偵測器重寫、Metal 緩衝區安全 |
| `v1.1.0` | 2026-10-29 | 首次完整 iOS 重構與 CI 打包 |
