# vFlat 逆向工程與 iOS 原生重構專案 (vFlat-iOS)

![Version](https://img.shields.io/badge/version-v1.1.1-blue.svg)
![Platform](https://img.shields.io/badge/platform-iOS%2016.0%2B-black.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Metal](https://img.shields.io/badge/Metal-60fps-red.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

本專案由兩大核心部分組成：
1. **vFlat 深度逆向工程分析 (REA)**：對 vFlat Android 官方發行版 (`com.voyagerx.scanner`) 之二進位函式庫（`libnative-scan.so`）、AI 神經網路模型（`freeform_v3_2.dat`, `optp_v3_3.dat`）進行底層逆向，解密其專利防逆向混淆、1250 浮點數輸出置換表、ARM NEON 向量正規化與 RQ 矩陣分解。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：基於現代 Apple 原生技術棧（SwiftUI + AVFoundation + Metal + Vision + PDFKit）完全重新打造零第三方依賴、60fps 超流暢、低功耗之文件與書本掃描器。

詳細技術交接手冊與底層二進位逆向細節請參閱：[`AGENT_HANDOVER.md`](file:///AGENT_HANDOVER.md)

---

## 核心亮點與特色

- **零外部第三方依賴 (Zero 3rd-Party Dependencies)**：
  - 核心全採 Apple 原生框架（AVFoundation、Vision、Metal、CoreImage、CoreMotion、PDFKit、SwiftUI），無需笨重且吃電的外部函式庫。
- **60fps 極致流暢預覽**：
  - Metal MSL 著色器硬體加速渲染，透過 `CVMetalTextureCache` 零拷貝導入視訊影格。
  - 物理 Aspect-Fill 投影，杜絕畫面拉伸變形。
- **雙引擎自適應抓框 (Dual-Engine Boundary Detection)**：
  - 主引擎：Apple Vision 深度學習語意分割（`VNDetectDocumentSegmentationRequest`）。
  - 輔助引擎：多候選高階幾何四邊形偵測（`VNDetectRectanglesRequest`）。
  - 套用 EMA 時序平滑濾波與物理貼膜級邊界收縮，緊咬物體邊緣。
- **自動穩定捕捉拍照 (Auto-Capture)**：
  - 演算法監控四角點位移量 $\Delta \le 0.02$ 持續 500ms 自動擊發快門，並帶有綠色環狀進度條動畫。
- **QR Code / 條碼自動解析**：
  - Apple Vision 實時條碼辨識，頂部彈簧動畫滑出懸浮智慧膠囊，一鍵複製內容或跳轉 Safari 開啟網址。
- **25×25 自由曲面 GPU 離屏展平 (Metal Dewarping)**：
  - 依據橫向 25 條微弧線微分積分自適應計算物理展開尺寸，透過 GPU 離屏著色器撫平書頁裝訂波浪彎曲。
- **雙頁書本中縫自動分割 (Two-Page Auto Split)**：
  - 自動分析中央光度極小值鎖定書脊中縫，智慧切割為獨立左右兩頁，並剔除裝訂線陰影，支援 LTR/RTL 閱讀順序。
- **6 大專用文件增強濾鏡**：
  - 原圖、智慧自動平衡、去暗角增亮、黑白灰階、高反差清晰二值、白板去雜訊模式，支援單頁檢視即時切換。
- **多頁 PDF 打包與壓縮匯出**：
  - 原生 `PDFKit` 支援連拍批次合成為單一 PDF，提供 A4 / Letter / 自適應版面與 4 種壓縮等級，支援 iOS 原生 Share Sheet 分享。
- **放大鏡手動角點微調 (Loupe Crop)**：
  - 拖曳四角點時即時浮現 2.2x 圓形放大鏡與十字準心，徹底消除手指遮擋。
- **GitHub Actions 雲端自動打包 CI/CD**：
  - 每次 Push 自動在雲端 macOS Sequoia 環境完成編譯並生成未簽名之 `vFlat.ipa`。
  - 提供本地一鍵自動下載腳本，免手動至網頁下載。

---

## 系統需求

- **iOS 裝置**：iPhone（需支援 iOS 16.0 或以上版本）。
- **側載安裝工具**：Windows / macOS 版 [Sideloadly](https://sideloadly.io/) 或 AltStore。
- **原始碼編譯環境（選用）**：
  - macOS 14.0+
  - Xcode 15.0+ (Swift 5.9+)
  - `xcodegen` (`brew install xcodegen`)

---

## 一鍵取得最新 IPA 與安裝指南

### 步驟 1：下載最新 `vFlat.ipa`
本專案已配置一鍵自動下載工具：
- 執行專案根目錄的 `download_ipa.bat`（或在終端機執行 `python download_ipa.py`）。
- 腳本會透過 GitHub API 自動抓取最新成功構建的 Actions Artifacts，並在本地根目錄產生 `vFlat.ipa`。

### 步驟 2：使用 Sideloadly 側載至 iPhone
1. 開啟 Sideloadly 並以傳輸線連接 iPhone。
2. 將專案根目錄的 `vFlat.ipa` 拖入 Sideloadly 視窗。
3. 輸入個人 Apple ID，點擊 **Start** 進行簽名與安裝。
4. 安裝完成後，在 iPhone「設定」>「一般」>「VPN 與裝置管理」信任個人開發者證書即可開啟。

---

## 專案目錄結構

```
vflat/
├── ios/                             # iPhone 原生完整應用程式代碼
│   ├── Package.swift                # Swift 5.9 SPM 套件定義
│   ├── Info.plist                   # 系統權限宣告 (Camera, Photo Library)
│   ├── Sources/
│   │   ├── Core/                    # 核心底層 (Camera, Motion, Dewarp, Metal, Export)
│   │   ├── UI/                      # 現代 SwiftUI 介面與 ViewModel
│   │   └── vFlatApp/                # App 進入點
│   └── Tests/                       # 幾何數學單元測試
├── apks/                            # 逆向工程 Android 提取資產與二進位庫
│   └── extracted_arm64/
│       ├── assets/models/           # 原廠 AI 模型 (freeform_v3_2.dat, optp_v3_3.dat)
│       └── lib/arm64-v8a/           # 原廠 C++ 核心 (libnative-scan.so 等)
├── .github/workflows/               # GitHub Actions CI/CD 自動構建腳本
├── AGENT_HANDOVER.md                # AI Agent 深度技術交接手冊
├── VERSION                          # 專案語意化版本號宣告檔
├── download_ipa.bat                 # Windows 純 ASCII 一鍵下載 IPA 批次檔
└── download_ipa.py                  # Python GitHub Actions IPA 下載器
```

---

## 逆向工程核心突破摘要

1. **`libnative-scan.so` 原生 C++ 向量運算**：
   - `Scan.btf`（`0x1a9b0`）：ARM NEON SIMD 向量化指令快速將相機像素轉為 `[0.0..1.0]` 浮點張量。
   - `freeform::model::deobfuscate`（`0x1c1a8`）：破譯 1250 個浮點數索引置換表，還原 $25 \times 25$ 自由曲面拓撲。
   - `calcRQDecomp3x3`（`0x1cabc`）：Eigen C++ RQ 矩陣分解，自單應性矩陣中分離出相機視角與傾斜角度。
2. **`optp_v3_3.dat` 模型混淆解碼**：
   - 破譯 FlatBuffers vtable 空偏移之 `0x80000000` 最高位元旗標，施加 `vdiff &= 0x7FFFFFFF` 遮罩即可修復解析崩潰。

---

## 開發與協作規範

本專案遵循嚴格的工程規範：
- 每次代碼修改**必須推進 `VERSION` 版本號**。
- Git Commit 一律以**繁體中文**清晰描述變更內容。
- 一鍵啟動腳本（`.bat` / `.sh`）**嚴禁包含任何中文字元**，維持純 ASCII 格式。
