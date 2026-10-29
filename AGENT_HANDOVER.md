# AI Agent 專案交接與工程維護手冊 (Agent Handover Document)

> **專案名稱**：vFlat 逆向工程與 iOS 原生重構專案 (`vFlat-iOS`)  
> **專案版本**：`v0.9.8`  
> **最後更新時間**：2026-10-30  
> **遠端儲存庫**：`https://github.com/y41418845-CY/vflat` (預設分支：`master`)  
> **本地工作目錄**：`h:\我的雲端硬碟\工具程式\vflat\`  
> **接手重點提示**：請新進 AI Agent 優先閱讀本手冊與全域規範，本專案嚴格遵守無外掛純原生（Swift/Metal/Vision）與高幀率（60fps）零延遲標準。

---

## 一、專案核心定位與目標 (Project Mission)

本專案承接兩大核心任務：
1. **vFlat 核心演算法與模型深度逆向 (REA Reverse Engineering Analysis)**：
   - 從官方 Android 發行版（XAPK）中解構其底層原生 C++ 函式庫（`libnative-scan.so` 等）、TFLite 神經網路模型（`freeform_v3_2.dat`, `optp_v3_3.dat`）與 GPU 渲染架構。
   - 破譯 VoyagerX 專利防逆向混淆（FlatBuffers vtable MSB 混淆、1250 浮點數輸出置換表、ARM NEON SIMD 向量化預處理、Eigen RQ 矩陣分解）。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：
   - 採用現代 Apple 原生技術棧（SwiftUI + AVFoundation + Metal + Vision）打造 60fps 零延遲、極低功耗之書本與文件掃描器。
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
│   │   ├── Motion/                  # CoreMotion 陀螺儀 60Hz 俯拍水平傾角感測 (MotionManager.swift)
│   │   ├── Dewarp/                  # 雙引擎邊界偵測、EMA 平滑防抖、25x25 弧長微分積分展開 (DocumentDetector.swift)
│   │   └── Metal/                   # Metal MSL Aspect-Fill 著色器、零拷貝紋理快取與即時渲染 (MetalRenderer.swift, Shaders.metal)
│   ├── UI/                          # 現代 SwiftUI 介面層
│   │   ├── Views/                   # CameraScanView、ScanControlBar、ScanGuideOverlay、DocumentDetailView、SettingsView
│   │   └── ViewModels/              # ScannerViewModel 主狀態協調器
│   └── vFlatApp/                    # 應用程式 App 進入點 (App.swift)
└── Tests/
    └── DewarpTests/                 # 幾何數學與弧長積分單元測試
```

### 資料流向 (Data Pipeline)
1. **相機影格輸入**：`AVCaptureVideoDataOutput` 以 60fps 採集 4K/1080p `CVPixelBuffer`。
2. **GPU 即時預覽**：透過 `CVMetalTextureCache` 零拷貝導入 Metal 著色器，使用 Aspect-Fill 幾何取樣映射至 iPhone 全螢幕（19.5:9），保持 1:1 物理真實比例。
3. **神經視覺邊緣運算**：`DocumentDetector` 在背景專用線程運行雙引擎（Apple Vision 深度分割 `VNDetectDocumentSegmentationRequest` + 多候選高階矩形 `VNDetectRectanglesRequest`）。
4. **時序幾何防抖與收縮**：輸出四角點經 EMA 平滑濾波（$\alpha = 0.35$）消除邊緣抖動，並套用物理貼膜級微調收縮（`marginRatioX = 0.01`, `marginRatioY = 0.015`），使導引框完美緊咬文件邊界。
5. **拍照與儲存**：按下快門觸發快門白光閃爍，直接自相機管線捕獲高解析度影格，更新左下角即時縮圖並自動寫入系統相簿。

---

## 三、關鍵技術決策與約定 (Technical Decisions & Conventions)

1. **零第三方外部依賴 (YAGNI & Pure Native)**：
   - 堅持使用 Apple 原生框架（AVFoundation、Vision、Metal、CoreMotion、SwiftUI）。
   - 拒絕引入龐大且笨重的 OpenCV-iOS 或未經深度最佳化的 Python/ONNX 包裝，維持極速冷啟動與極低電量消耗。
2. **雙引擎自適應抓框架構 (Dual-Engine Detection)**：
   - **主引擎**：Apple Vision 官方深度學習語意分割（`VNDetectDocumentSegmentationRequest`），具備強大抗雜訊、抗手指遮擋與陰影能力。
   - **輔助引擎**：多候選幾何四邊形偵測（`VNDetectRectanglesRequest`），放寬 `quadratureTolerance = 45.0`，當光照或高反差背景時提供即時互補。
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
- **調用包裝**：`Scan.dof`（位址 `0x1af6c`）為 JNI 入口點，負責調度呼叫 `freeform::model::deobfuscate`。

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

### 2. 神經網絡模型結構與反反向工程混淆破解 (`optp_v3_3.dat`)

- **檔案路徑**：`assets/models/optp_v3_3.dat`（大小 1,732,388 位元組）。
- **底層架構**：TFLite FlatBuffers 格式（Version 3）。
- **模型規模**：1 個 Subgraph、224 個 Operators、379 個 Tensors。
- **算子組成**：純標準 12 種內建運算子（無任何自訂非標算子，非常適合跨平台移植）：
  - `CONV_2D`, `DEPTHWISE_CONV_2D`, `ADD`, `SIGMOID`, `SOFTMAX`, `RESHAPE`, `TRANSPOSE`, `CONCATENATION`, `PAD`, `STRIDED_SLICE`, `MUL`, `SUB`。

#### VoyagerX 專利防解析混淆破譯
- **攻擊現象**：使用標準 Python `flatbuffers`、Google 官方 TFLite 解析工具或 Netron 開啟 `optp_v3_3.dat` 時，會觸發指標越界崩潰：
  `struct.error: unpack_from requires a buffer of at least 2149393562 bytes`
- **混淆手法**：
  - VoyagerX 修改了 FlatBuffers 的 vtable 虛擬表偏移量。
  - 對於空指標或預設緩衝區，其偏移量被故意加上了最高有效位元符號旗標（MSB, `0x80000000`）。在 32 位元有符號整數解讀下變為負值（`-2147483648`），導致標準解碼器計算絕對指標時發生整數溢出。
- **解法（De-obfuscation Mask）**：
  - 只要在解讀 vtable 偏移時施加遮罩：`vdiff &= 0x7FFFFFFF`，即可完全消除該混淆標記，還原出完全符合標準 TFLite 規範的模型檔案。

#### 模型輸出工作機制
- 該模型主要負責書本透視角點熱圖回歸（Corner Heatmap Regression）。
- 輸出包含 4 個角點的熱圖分佈與高斯中心座標，即使在書角破損、手指壓邊或嚴重陰影下，依然能藉由全域語意推斷出物理邊界。

---

### 3. 抓框技術路線比較與決策矩陣

| 評比維度 | 路線一：Apple Vision 雙引擎 (當前採用) | 路線二：VoyagerX TFLite/CoreML 移植 |
| :--- | :--- | :--- |
| **技術棧** | Apple 原生 `VNDetectDocumentSegmentationRequest` + `VNDetectRectanglesRequest` | Python 解混淆後轉 CoreML，整合 `Scan.btf` 向量前處理 |
| **執行幀率** | **60 fps**（Metal/ANE 零拷貝即時串流） | 15 ~ 30 fps（取決於 CoreML 量化與 ANE 排程） |
| **外部依賴** | **0 MB**（完全使用 iOS 系統內建模組） | 需自帶 2MB ~ 7MB 神經網絡權重檔與自訂推論包裝 |
| **記憶體佔用** | 極低（無額外張量緩衝區開銷） | 中等（需維護 Model Input/Output Tensors） |
| **邊界表現** | 平整文件與藥盒效果極佳，抗背景雜訊 | 彎曲書頁表現最佳，但模型轉換成本與維護難度高 |
| **結論** | **作為主力生產版本**，達成零外部依賴與極致流暢 | 已完成所有逆向逆推與破譯，作為下一階段可選技術儲備 |

---

## 五、當前完成進度與驗證狀態 (Current Status & Verified Features)

- [x] **快門抓幀與相簿寫入**：點擊快門按鈕觸發 60fps 無延遲白光反饋，自動抓取全解析度畫面並存入系統相簿。
- [x] **即時縮圖渲染**：左下角縮圖動態更新最後一張拍攝成果，點擊進入詳細檢視視圖。
- [x] **雙引擎視覺抓框**：結合語意分割與矩形辨識，解決多色塊、上緣文字切除問題。
- [x] **物理 Aspect-Fill 投影**：消除 9:16 相機與 19.5:9 螢幕比例差所造成的幾何偏位。
- [x] **實體貼膜級邊界收縮**：套用自適應微調邊界收縮，消除頂部與底部溢出，精準貼合物體邊緣。
- [x] **GitHub Actions 自動化打包**：每次 Push 自動在 macOS Sequoia 雲端環境完成編譯並生成 `vFlat.ipa`。
- [x] **本地自動下載腳本**：提供 `fetch_ipa.bat` 與 `download_ipa.py` 一鍵自 GitHub 下載最新 IPA。

---

## 六、待辦事項與下一步行動建議 (TODOs & Next Steps)

1. **相機拍攝視角/遠近與原廠對齊 (High Priority)**：
   - 依據使用者實測反饋（相同實體距離下，目前預覽畫面物體比例與原廠有細微差異）。
   - 建議修改檔案：`ios/Sources/Core/Camera/CameraManager.swift`
   - 調試方向：微調 `AVCaptureDevice` 的 `videoZoomFactor`（例如從預設 `1.0` 設定至 `1.05 ~ 1.15`），使同一物理拍攝距離下的取景範圍與原廠 100% 吻合。
2. **25x25 自由曲面展平（Metal GPU Dewarping）(Medium Priority)**：
   - 目前幾何展開數學函式庫已完成驗證 (`Sources/Core/Dewarp/`)。
   - 建議在拍攝後處理流程中，將捕獲的圖像依據網格弧長積分展開並輸出展平照片。
3. **雙頁自動分割 (Two-Page Split) (Low Priority)**：
   - 針對展開的跨頁書本，沿中縫特徵垂直切割為左右兩頁。

---

## 七、已知問題、風險與防坑指南 (Known Issues & Gotchas)

1. **不可強行使用透視平行拘束 (`withPerspectiveParallelism`)**：
   - 嚴禁透過強制修改下邊界斜率以求平行。在手持拍攝或俯拍微斜角度下，四邊形非嚴格平行四邊形，強行拘束會導致邊框劇烈跳動甚至抓不到框（此錯誤已在 `v0.9.7` 徹底回滾修復）。
2. **Preset 選擇不可切換至 `.photo`**：
   - 相機串流必須維持 `.hd4K3840x2160` 或 `.hd1920x1080`。若設定為 `.photo`，iOS 會將 `videoOutput` 降頻至 10~15fps，導致預覽與框線追蹤產生嚴重延遲。
3. **FlatBuffers 解析防坑**：
   - 若未來需二次處理 `assets/models/optp_v3_3.dat`，解碼前務必確認是否已處理 `0x80000000` MSB 混淆，否則任何第三方解析庫皆會觸發崩潰。
4. **一鍵啟動腳本編碼防坑**：
   - 根目錄所有 `.bat` 與 `.sh` 檔案必須維持純 ASCII 英文，嚴禁包含任何中文字元與中文字碼頁依賴。
