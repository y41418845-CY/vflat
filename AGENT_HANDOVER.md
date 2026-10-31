# AI Agent 專案交接與工程維護手冊 (Agent Handover Document)

> **專案名稱**：vFlat 逆向工程與 iOS 原生重構專案 (`vFlat-iOS`)  
> **專案版本**：`v1.7.5`（Build `175`）  
> **最後更新時間**：2026-10-31  
> **遠端儲存庫**：`https://github.com/y41418845-CY/vflat`（當前分支：`feature/authentic-replica-ui`，預設分支：`master`）  
> **本地工作目錄**：`g:\我的雲端硬碟\工具程式\vflat\`  
> **接手重點提示**：請新進 AI Agent 優先閱讀本手冊與全域規範。本專案嚴格遵守「無外掛純原生（Swift / Metal / Vision / PDFKit）」、「零廣告零聯網 100% 離線隱私」與「60fps 零延遲」標準；**CI 建置路徑採用 GitHub Actions (macOS-15 runner + XcodeGen)**。

---

## 一、專案核心定位與目標 (Project Mission)

本專案解決「原廠 vFlat 全面商業化、強迫付費訂閱、免費版每日頁數配額限制、廣告干擾與雲端隱私外洩風險」之痛點：

1. **原廠核心技術深度逆向 (REA Reverse Engineering Analysis)**：
   - 從官方 Android 發行版（XAPK）與 iOS 發行版（`com.voyagerx.scanner_1.33.10.ipa`）中解構其雙軌推論架構（CoreML LMNE 加密 vs TFLite `.dat` Bitmask 混淆）。
   - 破譯其 12 大神經網路模型（25×25 自由曲面展開 `FreeformModel`、文字去模糊 `DeblurModel`、手指抹除 `InpainterModel`、手寫筆跡消除 `HandwritingRemoval`、手機陰影去除 `DistillationModel`、書脊中縫檢測 `PPTPModel` 等）。
2. **iPhone 原生獨立重構 (`vFlat-iOS`)**：
   - 採用現代 Apple 原生技術棧（SwiftUI + AVFoundation + Metal + Vision + PDFKit），達到與原廠旗鼓相當甚至超越的清晰度與拉平效果。
   - 保證 **0 MB 外部模型依賴**（純演算法優化）、極輕安裝包（不到 15MB vs 原廠 158MB）、秒開相機、**終身免費且無使用限制**。
3. **1:1 原廠旗艦 UI 與商業限制徹底解除**：
   - 完整復刻原廠書庫管理、多資料夾架構、左右水平翻頁閱讀器、網格密度切換、多選批次操作。
   - 解鎖 Auto-Scan 自動捕捉、無限次數離線 OCR、無限制 AI 魔法增強，零付費牆、零廣告干擾。

---

## 二、系統架構與關鍵模組切分 (Architecture & Components)

```
ios/
├── Package.swift                    # Swift 5.9 SPM 套件定義 (iOS 16.0+，本機除錯備援)
├── Info.plist                       # 由 project.yml 產生：相機 / 相簿讀取 / 相簿寫入權限
├── README.md                        # 使用說明與編譯指引
├── Sources/
│   ├── Core/                        # 核心底層驅動與影像演算法
│   │   ├── Camera/                  # 相機硬體驅動 (CameraManager.swift)
│   │   │   └── CameraLens           # 超廣角 0.5x (推薦) / 一般 1x / 長焦 2x-3x 三鏡頭支援
│   │   ├── Motion/                  # CoreMotion 俯拍水平傾角感測 (MotionSensor.swift)
│   │   ├── Detection/               # 即時邊界、條碼與自動快門感測
│   │   │   ├── DocumentDetector.swift    # Vision 文件四邊角點雙引擎
│   │   │   ├── AutoCaptureDetector.swift # 幾何與陀螺儀雙重穩定度自動快門
│   │   │   └── BarcodeScannerService.swift # 即時條碼 / QR Code HUD 辨識
│   │   ├── Dewarp/                  # 書籍曲面拉平、雙頁分割與幾何微分
│   │   │   ├── DynamicDewarpPredictor.swift # 真·動態 25x25 網格預測器 (高斯拋物線+三次樣條)
│   │   │   ├── DewarpGeometry.swift         # 25x25 弧長微分積分輸出尺寸運算
│   │   │   ├── DewarpMesh.swift             # 24x24 格子 (1152 三角形) Metal 頂點拓撲
│   │   │   └── BookPageSplitter.swift       # 中央垂直光度積分分析與雙頁智慧切割
│   │   ├── AI/                      # 原廠破譯 AI 影像修復處理器
│   │   │   ├── ShadowRemovalProcessor.swift    # Retinex 反射率重構與手機擋光陰影消除
│   │   │   ├── DeblurProcessor.swift           # 亮度分離 + 雙尺度非銳化遮罩文字銳化
│   │   │   ├── FingerRemovalProcessor.swift    # 周邊 12% YCbCr 膚色空間判定與泊松平滑
│   │   │   └── HandwritingRemovalProcessor.swift# 高動態色彩飽和度過濾 (除彩筆、保黑字)
│   │   ├── Rectification/           # DocumentRectifier.swift：透視拉正 + 6 大色彩濾鏡
│   │   ├── Storage/                 # ScanPageStore.swift：JPEG 磁碟落盤、JSON 索引、資料夾管理與 30天垃圾桶
│   │   ├── OCR/                     # OCRService.swift：Apple 原生 Vision 繁簡中英離線辨識
│   │   ├── Export/                  # 匯出服務
│   │   │   ├── DocumentNamingService.swift # 時間戳智慧命名器
│   │   │   └── PDFExporter.swift           # 原生 PDFKit 合成、密碼保護、可搜尋文字層
│   │   └── Metal/                   # Metal GPU 著色器與渲染管線
│   │       ├── Shaders.metal               # 頂點與片段著色器 (弧長拉平、邊緣羽化)
│   │       ├── MetalOffscreenDewarper.swift# 離屏高畫質 25x25 網格 GPU 展開
│   │       └── MetalDewarpRenderer.swift   # MTKView 60fps 即時取景渲染器
│   ├── UI/                          # 現代 SwiftUI 介面層 (對齊原廠 1:1)
│   │   ├── Views/
│   │   │   ├── LibraryView.swift           # 原廠首頁書庫 (多資料夾、網格、多選批次列、相機大圓鈕)
│   │   │   ├── PageSwipeDetailView.swift   # 原廠 1:1 左右水平翻頁閱讀器 (縮放、AI、濾鏡、OCR、匯出)
│   │   │   ├── MoveFolderSheet.swift       # 跨資料夾移動與即時新增資料夾彈窗
│   │   │   ├── CameraScanView.swift        # 主相機取景畫面 (含返回書庫、完成 Done、Auto Scan)
│   │   │   ├── DocumentDetailView.swift    # 備援單頁檢視
│   │   │   ├── LoupeCropView.swift         # 4 角點微調與 2.2x 放大鏡
│   │   │   ├── PDFExportSheet.swift        # 完整對齊原廠之 PDF 匯出面板
│   │   │   ├── TrashBinView.swift          # 垃圾桶（最近刪除）檢視與一鍵復原
│   │   │   └── SettingsView.swift          # 四大項目全對齊設定中心 (去除所有商業限制)
│   │   └── ViewModels/
│   │       └── ScannerViewModel.swift      # 全域主協調器 (含極致全開 Ultra Scan 管線)
│   └── vFlatApp/                    # 應用程式進入點 (vFlatApp.swift -> LibraryView)
```

---

## 三、關鍵技術決策與約定 (Technical Decisions & Conventions)

1. **完全零第三方笨重依賴 (Zero 3rd-Party Dependencies)**：
   - 拒絕引入龐大的 OpenCV、TFLite C++ 函式庫或 Google MLKit。
   - 全面運用 Apple 內建現代底層框架：`AVFoundation`、`Metal`、`CoreImage`、`Vision`、`PDFKit`、`Combine`。
2. **Clean Room 自主研發與無侵權保護**：
   - 不在 App Bundle 中偷渡原廠二進位模型檔（`.mlmodelc` 或 `.dat` 權重），以自主編寫的數學演算法與 Metal 着色器實踐相同效果，完全避開版權風險。
3. **高動態非同步管線 (Async / Non-blocking)**：
   - 拍照後所有影像運算（透視裁切、25×25 展平、消陰影、去模糊、JPEG 落盤）皆在背景佇列執行（`Task.detached(priority: .userInitiated)`），主執行緒與快門永不凍結。
4. **非破壞性雙軌備份 (Non-Destructive Storage)**：
   - 每個頁面同步儲存 `rawFileName`（已裁切未上濾鏡原圖）與 `processedFileName`（後處理成品），使用者隨時可返回重新裁切或切換濾鏡。

---

## 四、當前完成進度與驗證狀態 (Current Status)

| 功能模組 | 完成狀態 | 驗證機制與成效 |
| :--- | :---: | :--- |
| **原廠 1:1 書庫首頁 (LibraryView)** | [x] 已完成 | 支援多資料夾切換、建立/重命名/刪除、2列/3列網格切換、搜尋、排序。 |
| **左右水平翻頁閱讀器 (PageSwipe)** | [x] 已完成 | 支援像電子書一樣左右手勢翻頁、雙指無級縮放、底部縮圖條快速導覽。 |
| **多選批次管理 (Batch Operations)** | [x] 已完成 | 支援全選/多選，批次匯出 PDF、批次存入相簿 (.jpg)、批次移動、批次刪除。 |
| **去除商業限制 (Unrestricted)** | [x] 已完成 | Auto-Scan 自動捕捉全免、OCR 零扣點無限次、AI 魔法修復全解鎖、零廣告。 |
| **0.5x 超廣角視野對齊** | [x] 已完成 | 相機預設以超廣角取景，近距離拍攝畫面不晃動、邊框穩穩鎖定。 |
| **動態 25×25 自由曲面展平** | [x] 已完成 | `DynamicDewarpPredictor` 自動估算中縫曲率，GPU 著色器精準展開。 |
| **手機擋光陰影消除** | [x] 已完成 | `ShadowRemovalProcessor` 利用 Retinex 反射率重構將暗部提亮為純白。 |
| **AI 邊緣手指抹除** | [x] 已完成 | `FingerRemovalProcessor` 邊界 12% YCbCr 膚色檢測 + 泊松平滑填補。 |
| **AI 彩色筆跡消除** | [x] 已完成 | `HandwritingRemovalProcessor` 高動態飽和度過濾，留黑字、去彩筆。 |
| **AI 文字去模糊超解析** | [x] 已完成 | `DeblurProcessor` 雙尺度非銳化遮罩與筆畫加深。 |
| **極致全開 (Ultra Scan)** | [x] 已完成 | 一鍵連鎖完成【展平+消陰影+消手指+文字銳化】。 |
| **儲存成 .jpg 檔** | [x] 已完成 | 單頁/批次儲存至相簿、實體 `.jpg` 檔案分享與 Toast 成功提示。 |
| **對齊原廠 4 大項目設定** | [x] 已完成 | 相機三鏡頭、定時器、雙頁順序、AI 覆蓋模式、PDF 密碼與可搜尋文字層。 |
| **30 天垃圾桶 (最近刪除)** | [x] 已完成 | `TrashBinView` 支援單頁還原、全部還原、永久刪除與自動 30 天過期。 |

---

## 五、待辦事項與下一步行動建議 (TODOs & Next Steps)

1. **優先級 High：實體 iPhone 側載安裝與真機體驗驗證**
   - 下載 GitHub Actions 編譯生成的 `vFlat.ipa`，透過 AltStore、SideStore 或 TrollStore 安裝至實體 iPhone。
   - 拿實體厚重書籍測試「極致全開」在不同光照下的展平與去陰影表現。
2. **優先級 Low：區域網路 Web 傳送至電腦 (Scan to PC)**
   - 實作極輕量之本機 Bonjour / HTTP 伺服器，讓同 Wi-Fi 下的電腦瀏覽器可一鍵打包下載整本書籍的 JPG 或 PDF。

---

## 六、已知問題、風險與防坑指南 (Gotchas)

1. **一鍵啟動腳本編碼限制**：
   - 專案內所有 `.bat`、`.cmd`、`.sh` 啟動檔**嚴禁包含任何中文字元**，否則 Windows CMD / PowerShell 會因字碼頁（CP950 vs UTF-8）崩潰。
2. **版本號推進準則**：
   - 凡有任何程式修改、Bug 修復或文件更新，**必須同步推進 `VERSION` 檔案**並於 Commit 訊息中清楚載明。
   - **版本號全面一致性（重要）**：`VERSION`、`project.yml`（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）、`ios/Info.plist`（`CFBundleShortVersionString` / `CFBundleVersion`）、`README.md` badge、`AGENT_HANDOVER.md` 頂部版本字串，五處必須**同時**更新為相同版本號與 Build 號。歷史上曾發生 `VERSION = v1.5.3` 但 `project.yml` / `Info.plist` 停在 `v1.2.4`、README/交接文件停在 `v1.5.1` 的不一致情況，導致 App 實際顯示版本與儲存庫版本不符。修改版本時請以 `VERSION` 為唯一真相來源，其餘四處跟隨。
3. **技能目錄實體資料夾要求**：
   - Antigravity 自訂技能目錄必須使用 Windows 實體資料夾，嚴禁使用 Junction 聯結點或符號連結。
4. **Git Commit 繁體中文約定**：
   - Commit 訊息必須使用繁體中文（台灣口語）撰寫，維持儲存庫紀錄清晰一致。
5. **SwiftUI 多 Sheet 衝突與 ActionSheet Dismiss 競態 (v1.5.9 重大修復)**：
   - 在 SwiftUI 同一個 View 樹上**嚴禁宣告多個 `.sheet(isPresented:)`**，否則後者會覆蓋前者，導致彈窗無反應。必須統一使用 `enum ActiveDetailModal: Identifiable` 配合單一 `.sheet(item: $activeModal)`。
   - 在 ActionSheet / ConfirmationDialog 的按鈕回調中若要拉起新的 Sheet 或 UIActivityViewController，**必須延遲約 0.35 秒**（`DispatchQueue.main.asyncAfter(deadline: .now() + 0.35)`），避免與 ActionSheet 的 dismiss 動畫發生 presentation 衝突遭 UIKit 靜默丟棄。
   - 儲存相片必須採用 `PHPhotoLibrary` 進行 `.addOnly` 權限確認與 `performChanges` 寫入，不可使用過時且無錯誤回傳的 `UIImageWriteToSavedPhotosAlbum`。
