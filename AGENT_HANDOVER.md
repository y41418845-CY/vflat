# AI Agent 專案交接與工程維護文件 (Handover Document)

> **專案名稱**：vFlat 逆向工程與 iOS 原生重構專案 (`vFlat-iOS`)  
> **專案版本**：`v0.5.0`  
> **最後更新時間**：2026-10-29  
> **遠端儲存庫**：`https://github.com/y41418845-CY/vflat` (預設分支：`master`)  
> **本地工作目錄**：`G:\我的雲端硬碟\工具程式\vflat\`

---

## 一、專案全貌與核心目標 (Project Overview)

本專案承接兩大核心任務：
1. **vFlat 核心演算法逆向工程 (REA Analysis)**：從官方發行之 Android 安裝包（XAPK）中，解構其原生 C++ 函式庫、TFLite 神經網路模型與 GPU 著色器，徹底還原出「25×25 自由曲面展平（Freeform Dewarping）」之數學幾何模型與模型輸出反混淆機制。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：拋棄舊式 OpenGL ES 與 Android JNI 架構，以現代 Apple 原生技術（SwiftUI + AVFoundation + Metal + Accelerate SIMD）完全重新打造零延遲、高幀率（60fps）、極低功耗的 iOS 書本掃描器，並建置 GitHub Actions 雲端自動編譯管線，一鍵輸出可側載之 `vFlat.ipa`。

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

## 三、iOS 原生專案代碼結構 (`ios/`)

```
ios/
├── Package.swift                    # Swift 5.9 SPM 套件定義 (iOS 16.0+)
├── Info.plist                       # 相機權限宣告 (NSCameraUsageDescription)
├── README.md                        # Xcode 本機開啟與執行手冊
├── Sources/
│   ├── Core/                        # 核心底層驅動與數學模組
│   │   ├── Camera/                  # AVCaptureSession 4K/60fps 串流採集
│   │   ├── Motion/                  # CoreMotion 陀螺儀 60Hz 俯拍水平傾角感測
│   │   ├── Dewarp/                  # 25x25 幾何弧長微分展開與網格生成 (SIMD)
│   │   └── Metal/                   # Metal MSL 雙線性重採樣展平著色器與零拷貝渲染器
│   ├── UI/                          # 現代 SwiftUI 介面
│   │   ├── Views/                   # CameraScanView、ScanControlBar、ScanGuideOverlay
│   │   └── ViewModels/              # ScannerViewModel 主狀態協調器
│   └── vFlatApp/                    # 應用程式 App 進入點
└── Tests/
    └── DewarpTests/                 # 幾何數學單元測試 (驗證平坦與彎曲微積分物理特性)
```

---

## 四、雲端 CI/CD 自動編譯與發布管線

* **設定檔**：`.github/workflows/build_ios.yml`
* **工程生成**：`project.yml` 搭配 `xcodegen`。
* **建置環境**：GitHub Actions `macos-15` (macOS Sequoia + Xcode 16)。
* **輸出機制**：
  * 編譯產出未簽名之 `vFlat.app` 並打包為 `vFlat.ipa`。
  * 自動推送並發布至 **GitHub Releases (`v0.4.4` 及後續版本)**，徹底繞過 GitHub Actions 免費用戶之 Artifact 空間配額限制。
* **實體手機安裝路徑**：
  * 下載 `vFlat.ipa` -> 使用 Windows 版 **Sideloadly** 拖入 IPA -> 輸入個人 Apple ID 即可一鍵簽名側載至實體 iPhone。

---

## 五、接手 Agent 下一步待辦清單 (Roadmap & Next Steps)

後續接手的 AI Agent 或工程師，可依照以下優先順序繼續擴充專案：

### 優先級 1：Core ML 模型整合 (替換 POC 模擬網格)
1. **模型格式轉換**：使用 Python `coremltools` 將 `assets/models/freeform_v3_2.dat` 轉換為 Apple Core ML 格式（`.mlpackage`），啟用 Apple Neural Engine (ANE) 加速。
2. **張量管線接入**：在 `CameraManager` 影格回呼中，以 15~20fps 節流（Throttle）非同步調用 Core ML 模型，將預測出的 625 個控制點座標即時傳入 `MetalDewarpRenderer.updateMesh()`。

### 優先級 2：多頁 PDF 匯出與離線 OCR (VisionKit)
1. 整合 iOS 原生 `VisionKit` (`VNRecognizeTextRequest`)，在拍照時擷取畫面中的文字座標與內容（支援離線繁體中文/英文）。
2. 使用 `PDFKit` 將展平後的高解析度圖檔合成多頁 PDF，並嵌入不可見文字層，產出標準可搜尋的 **Searchable PDF**。

### 優先級 3：雙頁中縫分割與手指修復 (Inpainting)
1. 實作雙頁模式的中縫偵測與裁切邏輯（單次快門自動拆分為左右兩頁）。
2. 移植 `finger_mask_v1_1.dat` 與 Metal Inpainting 著色器，抹除按壓在書本邊緣的手指。

---

## 六、開發規範與維護守則 (Project Rules)

後續修改此專案時，**必須持續嚴格遵守以下準則**：
1. **版本號嚴格遞增**：凡修改任何程式碼、工作流程或設定，必須同步更新根目錄之 `VERSION` 檔案（語意化版本 `vX.Y.Z`）。
2. **Git Commit 繁體中文註解**：每次修改完成後即時執行 `git add .` 與 `git commit`，訊息必須使用繁體中文（台灣習慣）與 Conventional Commits。
3. **一鍵啟動檔嚴禁中文字元**：任何 `.bat` / `.sh` 腳本檔案內部嚴禁包含任何中文字元，確保在 Windows 命令列環境執行不當機。
4. **安全防護**：推送到遠端儲存庫時嚴禁硬編碼任何 GitHub Personal Access Token 或憑證金鑰。
