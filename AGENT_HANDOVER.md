# AI Agent 專案交接與工程維護手冊 (Agent Handover Document)

> **專案名稱**：vFlat 逆向工程與 iOS 原生重構專案 (`vFlat-iOS`)  
> **專案版本**：`v1.1.1`  
> **最後更新時間**：2026-10-30  
> **遠端儲存庫**：`https://github.com/y41418845-CY/vflat` (預設分支：`master`)  
> **本地工作目錄**：`g:\我的雲端硬碟\工具程式\vflat\`  
> **接手重點提示**：請新進 AI Agent 優先閱讀本手冊與全域規範，本專案嚴格遵守無外掛純原生（Swift/Metal/Vision/PDFKit）與高幀率（60fps）零延遲標準。

---

## 一、專案核心定位與目標 (Project Mission)

本專案承接兩大核心任務：
1. **vFlat 核心演算法與模型深度逆向 (REA Reverse Engineering Analysis)**：
   - 從官方 Android 發行版（XAPK）中解構其底層原生 C++ 函式庫（`libnative-scan.so` 等）、TFLite 神經網路模型（`freeform_v3_2.dat`, `optp_v3_3.dat`）與 GPU 渲染架構。
   - 破譯 VoyagerX 專利防逆向混淆（FlatBuffers vtable MSB 混淆、1250 浮點數輸出置換表、ARM NEON SIMD 向量化預處理、Eigen RQ 矩陣分解）。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：
   - 採用現代 Apple 原生技術棧（SwiftUI + AVFoundation + Metal + Vision + PDFKit）打造 60fps 零延遲、極低功耗之書本與文件掃描器。
   - 結合業界優秀開源專案（OpenScan、OSS-DocumentScanner）之強大功能，實現自動穩定快門、多濾鏡增強、多頁 PDF 壓縮打包、放大鏡手動裁切、條碼/QR Code 自動解析、25×25 自由曲面 GPU 展平與雙頁中縫自動分割。
   - 建置 GitHub Actions 雲端自動編譯管線，一鍵輸出可透過 Sideloadly 側載之 `vFlat.ipa`。

---

## 二、系統架構與關鍵模組切分 (Architecture & Components)

```
ios/
├── Package.swift                    # Swift 5.9 SPM 套件定義 (iOS 16.0+)
├── Info.plist                       # 相機、相簿與動作感測權限宣告
├── README.md                        # Xcode 本機工程開啟說明
├── Sources/
│   ├── Core/                        # 核心底層驅動與影像演算法
│   │   ├── Camera/                  # AVCaptureSession 4K/60fps 串流採集、色彩設定、高畫質靜態抓幀 (CameraManager.swift)
│   │   ├── Motion/                  # CoreMotion 陀螺儀 60Hz 俯拍水平傾角感測 (MotionSensor.swift)
│   │   ├── Dewarp/                  # 視覺偵測、曲面展平幾何與雙頁分割
│   │   │   ├── DocumentDetector.swift    # Vision 雙引擎邊界偵測 + QR/條碼偵測
│   │   │   ├── AutoCaptureDetector.swift # 幀間位移穩定度判定 (自動快門觸發器)
│   │   │   ├── DetectedBarcode.swift     # 條碼/QR Code 資料模型
│   │   │   ├── BookPageSplitter.swift    # 書本中縫光度定位與雙頁自動分割
│   │   │   ├── DewarpGeometry.swift      # 25x25 弧長微分積分物理尺寸計算
│   │   │   ├── DewarpMesh.swift          # Metal 頂點與三角網格拓撲產生器
│   │   │   └── DocumentRectifier.swift   # 透視拉平與 6 大專用文件濾鏡管線
│   │   ├── Export/                  # 文件命名與 PDFKit 匯出服務
│   │   │   ├── DocumentNamingService.swift # 時間戳智慧命名規則器
│   │   │   └── PDFExporter.swift           # 原生 PDF 合成、A4/Letter 版面與壓縮品質
│   │   └── Metal/                   # Metal MSL Aspect-Fill 著色器與離屏 GPU 展平
│   │       ├── Shaders.metal               # 頂點與片段著色器 (Aspect-Fill 物理映射)
│   │       ├── ShaderTypes.h               # C/Metal 共享結構定義
│   │       ├── DewarpUniforms.swift        # Swift Uniforms 映射
│   │       ├── MetalDewarpRenderer.swift   # MTKView 60fps 實時渲染器
│   │       └── MetalOffscreenDewarper.swift# 拍下後高畫質影像 GPU 離屏 25x25 展平器
│   ├── UI/                          # 現代 SwiftUI 介面層
│   │   ├── Views/                   # 各功能視圖
│   │   │   ├── CameraScanView.swift        # 主取景畫面 (含條碼懸浮膠囊與自動快門進度環)
│   │   │   ├── ScanControlBar.swift        # 底部控制列 (單雙頁切換、縮圖卡片、快門)
│   │   │   ├── ScanGuideOverlay.swift      # 邊界導引框與十字姿態儀
│   │   │   ├── DocumentDetailView.swift    # 單頁檢視、6 大濾鏡橫列與操作列
│   │   │   ├── LoupeCropView.swift         # 4 角點手動微調與 2.2x 放大鏡
│   │   │   ├── PDFExportSheet.swift        # PDF 匯出面板與系統 Share Sheet
│   │   │   ├── PhotoImportPickerView.swift # 相簿匯入視圖
│   │   │   └── SettingsView.swift          # 偏好設定頁
│   │   └── ViewModels/              # ScannerViewModel 主狀態協調器
│   └── vFlatApp/                    # 應用程式 App 進入點 (vFlatApp.swift)
└── Tests/
    └── DewarpTests/                 # 幾何數學與弧長積分單元測試
```

### 資料流向 (Data Pipeline)
1. **相機串流輸入**：`AVCaptureVideoDataOutput` 以 60fps 採集 4K/1080p `CVPixelBuffer`。
2. **GPU 即時預覽**：透過 `CVMetalTextureCache` 零拷貝導入 Metal 著色器，使用 Aspect-Fill 幾何取樣映射至 iPhone 全螢幕（19.5:9），保持 1:1 物理真實比例。
3. **神經視覺邊緣運算**：`DocumentDetector` 在背景線程同步運行雙引擎（Apple Vision 深度分割 `VNDetectDocumentSegmentationRequest` + 多候選高階矩形 `VNDetectRectanglesRequest`）與條碼辨識（`VNDetectBarcodesRequest`）。
4. **自動快門判定**：`AutoCaptureDetector` 監控角點位移量 $\Delta \le 0.02$ 持續 500ms，達標自動呼叫快門。
5. **後處理校正與雙頁分割**：
   - 拍下照片後依序進行：四邊形透視拉正 $\rightarrow$ `MetalOffscreenDewarper` 25×25 自由曲面 GPU 展平 $\rightarrow$ 6 大文件專用濾鏡增強。
   - 若為「雙頁模式」，呼叫 `BookPageSplitter` 分析中縫光度，自動切割為左右兩頁獨立文件，依閱讀方向（LTR/RTL）存入相簿或 PDF 圖集。

---

## 三、關鍵技術決策與約定 (Technical Decisions & Conventions)

1. **零第三方外部依賴 (YAGNI & Pure Native)**：
   - 堅持使用 Apple 原生框架（AVFoundation、Vision、Metal、CoreImage、CoreMotion、PDFKit、SwiftUI）。
   - 拒絕引入龐大且吃電的 OpenCV-iOS、Tesseract C++ 或未最佳化的第三方套件，維持冷啟動極速與極低耗電。
2. **雙引擎自適應抓框架構 (Dual-Engine Detection)**：
   - **主引擎**：Apple Vision 官方深度學習語意分割（`VNDetectDocumentSegmentationRequest`），具備強大抗雜訊、抗手指遮擋與陰影能力。
   - **輔助引擎**：多候選幾何四邊形偵測（`VNDetectRectanglesRequest`），提供即時互補。
3. **Aspect-Fill 物理級座標映射**：
   - 嚴格區分「相機感光元件座標系（9:16）」與「iPhone 全螢幕座標系（19.5:9）」，所有導引層繪製與點位投影均經由 `aspectFillPoint()` 精確補償，杜絕任何畫面位移或形變。
4. **專案約定與規範**：
   - 每次代碼修改**必須同步遞增** `VERSION` 檔案版本號（`vX.Y.Z`）。
   - Git Commit 必須使用繁體中文清楚註記修改原因。
   - 一鍵啟動檔（`.bat` / `.sh`）嚴禁包含任何中文字元，確保在純英文環境與 Windows 命令列下穩定運作。

---

## 四、深度逆向工程技術手冊 (REA In-Depth Technical Dossier)

> 本節完整收錄針對 vFlat Android 官方發行版 (`com.voyagerx.scanner`) 執行二進位反組譯、模型架構剖析與特徵比對之全方位技術細節。

### 1. 原生 ARM64 二進位函式庫剖析 (`libnative-scan.so`)

- **二進位資訊**：ELF 64-bit LSB shared object, ARM aarch64, 大小 362,560 位元組，以 C++ 編寫並連結 Eigen 線性代數庫與 Android NDK。

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

## 五、當前完成進度與驗證狀態 (Current Status & Verified Features)

- [x] **60fps 極致流暢預覽**：Metal MSL 著色器硬體加速渲染，透過 `CVMetalTextureCache` 零拷貝導入視訊影格。
- [x] **物理 Aspect-Fill 投影**：消除 9:16 相機與 19.5:9 螢幕比例差所造成的幾何偏位。
- [x] **雙引擎視覺抓框**：結合語意分割與矩形辨識，解決多色塊、上緣文字切除問題。
- [x] **實體貼膜級邊界收縮**：套用自適應微調邊界收縮（寬 1%、高 1.5%），消除頂部與底部溢出，精準貼合物體邊緣。
- [x] **自動穩定捕捉拍照 (Auto-Capture)**：監控角點位移率 $\Delta \le 0.02$ 持續 500ms 自動擊發快門，並帶有綠色環狀進度條動畫。
- [x] **6 大專用文件增強濾鏡**：原圖、智慧自動平衡、去暗角增亮、黑白灰階、高反差清晰二值、白板去雜訊模式。
- [x] **多頁 PDF 打包與壓縮匯出**：原生 `PDFKit` 支援連拍批次合成為單一 PDF，提供 A4 / Letter / 自適應版面與 4 種壓縮品質。
- [x] **放大鏡手動角點微調 (Loupe Crop)**：拖曳四角點時即時浮現 2.2x 圓形放大鏡與十字準心，徹底消除手指遮擋。
- [x] **QR Code / 條碼自動解析**：Apple Vision 實時偵測，頂部彈簧動畫滑出懸浮智慧膠囊，一鍵複製或開啟網址。
- [x] **25×25 自由曲面 GPU 離屏展平**：`MetalOffscreenDewarper` 結合 25 條橫向弧長微分積分自適應計算物理展開尺寸，透過 GPU 著色器撫平書頁裝訂波浪彎曲。
- [x] **雙頁跨頁中縫自動分割**：`BookPageSplitter` 透過灰度積分抽樣自動定位中縫，智慧切割為獨立左右兩頁，並剔除裝訂線陰影。
- [x] **GitHub Actions 自動化打包**：每次 Push 自動在 macOS Sequoia 雲端環境完成編譯並生成 `vFlat.ipa`。
- [x] **本地一鍵下載工具**：提供純 ASCII 之 `download_ipa.bat` 與 `download_ipa.py` 一鍵自 GitHub 下載最新 IPA。

---

## 六、待辦事項與下一步行動建議 (TODOs & Next Steps)

1. **相機取景遠近/視野對齊 (High Priority)**：
   * 建議修改檔案：`ios/Sources/Core/Camera/CameraManager.swift`
   * 調試方向：微調 `AVCaptureDevice` 的 `videoZoomFactor`（例如從預設 `1.0` 設定至 `1.05 ~ 1.15`），使同一物理拍攝距離下的取景範圍與原廠 100% 吻合。
2. **Apple Vision 原生繁中離線 OCR 文字辨識 (Medium Priority)**：
   * 建議修改檔案：`ios/Sources/UI/Views/DocumentDetailView.swift`
   * 調試方向：將「辨識文字」按鈕串接 `VNRecognizeTextRequest`，辨識影像中的文字並彈出複製卡片。
3. **PDF 密碼加密保護 (Medium Priority)**：
   * 建議修改檔案：`ios/Sources/Core/Export/PDFExporter.swift` 與 `PDFExportSheet.swift`
   * 調試方向：在 `UIGraphicsPDFRenderer` 繪製選項中加入 `kCGPDFContextUserPassword` 屬性，為產出的 PDF 提供密碼鎖定。

---

## 七、已知問題、風險與防坑指南 (Known Issues & Gotchas)

1. **不可強行使用透視平行拘束 (`withPerspectiveParallelism`)**：
   * 嚴禁透過強制修改下邊界斜率以求平行。在手持拍攝或俯拍微斜角度下，四邊形非嚴格平行四邊形，強行拘束會導致邊框劇烈跳動甚至抓不到框。
2. **Preset 選擇不可切換至 `.photo`**：
   * 相機串流必須維持 `.hd4K3840x2160` 或 `.hd1920x1080`。若設定為 `.photo`，iOS 會將 `videoOutput` 降頻至 10~15fps，導致預覽與框線追蹤產生嚴重延遲。
3. **FlatBuffers 解析防坑**：
   * 若未來需二次處理 `assets/models/optp_v3_3.dat`，解碼前務必確認是否已處理 `0x80000000` MSB 混淆（`vdiff &= 0x7FFFFFFF`），否則任何第三方解析庫皆會觸發記憶體崩潰。
4. **一鍵啟動腳本編碼防坑**：
   * 根目錄所有 `.bat` 與 `.sh` 檔案必須維持純 ASCII 英文，嚴禁包含任何中文字元與中文字碼頁依賴。
