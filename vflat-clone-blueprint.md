# vFlat iOS 仿製版 — 完整 AI Agent 規劃藍圖

> **文件版本**：v1.0.0  
> **建立日期**：2026-10-30  
> **資料來源**：REA 逆向分析原廠 IPA (`iphone.voyagerx.scanner_1.33.10.ipa`, SHA-256: `98fd726949675835a798c6fae59ac53fe85bf9b10568f5ee9718a81ec3c15df2`) + 現有 Swift 重構源碼 (vFlat-iOS v1.5.9)  
> **目標平台**：iOS 16.0+ / iPhone only (portrait)  
> **開發技術棧**：Swift 5.9 · SwiftUI · AVFoundation · Metal · Vision · PDFKit · Combine  
> **建置工具**：XcodeGen (`project.yml`) + GitHub Actions (macOS-15 runner)  
> **Bundle ID**：`com.voyagerx.ios.vflat`  
> **設計原則**：零第三方依賴 · 100% 離線本機運算 · 純原生 Swift 技術棧

---

## 目次

1. [逆向分析摘要 (REA Evidence)](#1-逆向分析摘要)
2. [原廠架構解構](#2-原廠架構解構)
3. [完整系統架構圖](#3-完整系統架構圖)
4. [CoreML 神經網路模型目錄](#4-coreml-神經網路模型目錄)
5. [原廠第三方框架清單](#5-原廠第三方框架清單)
6. [UI 畫面規格 (逐頁)](#6-ui-畫面規格)
7. [核心演算法規格](#7-核心演算法規格)
8. [資料模型與儲存規格](#8-資料模型與儲存規格)
9. [設定項目對齊表](#9-設定項目對齊表)
10. [完整源碼目錄結構](#10-完整源碼目錄結構)
11. [建置與 CI/CD 規格](#11-建置與-cicd-規格)
12. [版本管理規範](#12-版本管理規範)
13. [AI Agent 執行清單](#13-ai-agent-執行清單)
14. [已知問題與陷阱](#14-已知問題與陷阱)

---

## 1. 逆向分析摘要

### 1.1 原廠 IPA 基本資訊

| 項目 | 值 |
|------|-----|
| 檔名 | `iphone.voyagerx.scanner_1.33.10.ipa` |
| SHA-256 | `98fd726949675835a798c6fae59ac53fe85bf9b10568f5ee9718a81ec3c15df2` |
| 檔案大小 | 158,434,789 bytes (~151 MB) |
| 格式 | IPA (ZIP 容器) |
| 總計 entry 數 | 549 個 |
| 圖節點數 | 530 個 |
| App Bundle | `Payload/vFlat.app/` |
| Assets.car 大小 | 45,456,344 bytes (~43 MB) — 圖示、UI 素材 |

### 1.2 原廠 Assets 重點分析

原廠 Assets.car（~43 MB）包含高解析度 UI 圖示、Lottie 動效素材與所有介面元素。仿製版採用 SF Symbols + SwiftUI 原生繪製替代，無需授權任何原廠素材。

### 1.3 原廠推論架構雙軌

```
原廠 vFlat 1.33.10 推論架構
├── CoreML 軌道 (加密 .mlmodelc / Espresso 格式)
│   ├── BlackpointClassificationModel_v1.0.1  ← 黑點分類
│   ├── BlackpointModel_v1.0.1               ← 黑點預測  
│   ├── ContentMaskModel_v3                  ← 內容遮罩
│   ├── DeblurModel_v1.1                     ← 文字去模糊 (15.5 MB weights)
│   ├── DistillationModel                    ← 手機陰影蒸餾消除
│   ├── FingerMaskModel                      ← 手指遮罩 (90KB net, 128KB weights)
│   ├── FreeformModel                        ← 25×25 自由曲面 Dewarp
│   ├── HandwritingModel                     ← 手寫筆跡消除
│   ├── InpainterModel                       ← 手指修復填補
│   ├── PPTPModel                            ← 書脊中縫偵測
│   └── SceneTextModel                       ← 場景文字偵測
└── 仿製版替代方案 (Clean Room 純演算法)
    ├── 高斯拋物線 + 三次樣條 → 替代 FreeformModel
    ├── Retinex 反射率重構 → 替代 DistillationModel
    ├── 雙尺度非銳化遮罩 → 替代 DeblurModel
    ├── YCbCr 膚色偵測 + Poisson → 替代 FingerMaskModel
    ├── 光度積分 → 替代 PPTPModel
    └── HSV 飽和度過濾 → 替代 HandwritingModel
```

---

## 2. 原廠架構解構

### 2.1 原廠使用的第三方框架 (IPA 逆向)

原廠 vFlat 採用重度外部依賴架構。仿製版以純原生 Apple 框架替代所有外部依賴。

| 框架 | 原廠用途 | 仿製版替代 |
|------|---------|-----------| 
| Lottie (3.57 MB) | 動效動畫 | SwiftUI Animation |
| Firebase Suite | 帳號/分析/崩潰/遠端儲存 | 不實作 (純本機) |
| FacebookCore/AEM | SDK 整合 | 不實作 |
| SFSafeSymbols (8.8 MB) | SF Symbol 安全訪問 | 直接用 SF Symbols |
| SwiftProtobuf (3.4 MB) | 資料序列化 | Swift Codable |
| JJFloatingActionButton | FAB 按鈕 | SwiftUI Button |
| PanModal | 底部抽屜 | SwiftUI .sheet |
| KeychainAccess | 金鑰管理 | 不實作 |
| Kronos | 網路時間同步 | 不實作 |
| grpc / absl / GoogleDataTransport | 雲端 RPC | 不實作 |
| AEXML | XML 解析 | 不實作 |
| AcknowList | 開源授權列表 | 不實作 |
| Socket | WebSocket | 不實作 |
| ZIPFoundation | ZIP 打包 | 不實作 |
| QuickTableViewController | 設定表格 | SwiftUI Form |
| SwiftUIPager | 頁面滑動 | SwiftUI TabView |

### 2.2 技術規格對比

| 指標 | 原廠 v1.33.10 | 仿製版 vFlat-iOS |
|------|-------------|----------------|
| 安裝大小 | ~151 MB | ~8-12 MB |
| 推論方式 | 加密 CoreML 模型 | 純演算法 (Clean Room) |
| 網路需求 | 帳號功能需連網 | 完全本機離線 |
| 第三方依賴 | 25+ frameworks | 零外部依賴 |
| 追蹤 SDK | Facebook AEM / Firebase Analytics | 無 |
| 影像處理管線 | CoreML Espresso 推論 | Metal GPU + CoreImage + Vision |

---

## 3. 完整系統架構圖

```
┌──────────────────────────────────────────────────────────────┐
│                      vFlatApp.swift                          │
│                    (App Entry Point)                         │
└─────────────────────┬────────────────────────────────────────┘
                      │ @StateObject
                      ▼
┌──────────────────────────────────────────────────────────────┐
│                   ScannerViewModel                           │
│  (@MainActor, ObservableObject)                             │
│                                                              │
│  Published State:                                            │
│  ├── scanMode: ScanMode (.single / .doublePage)              │
│  ├── selectedFilterMode: DocumentFilterMode                  │
│  ├── isAutoCaptureEnabled: Bool                              │
│  ├── autoCaptureProgress: Double (0.0~1.0)                   │
│  ├── detectedDocument: DetectedDocument?                     │
│  ├── detectedBarcode: DetectedBarcode?                       │
│  ├── isProcessingCapture: Bool                               │
│  ├── captureCountdown: Int?                                  │
│  ├── lastThumbnail / lastPreviewImage / lastRawPageImage      │
│  ├── lastOCRText: String?                                    │
│  ├── isRecognizingText: Bool                                 │
│  └── errorMessage: String?                                   │
│                                                              │
│  Hardware Services:                                          │
│  ├── cameraManager: CameraManager                            │
│  ├── motionSensor: MotionSensor                              │
│  ├── documentDetector: DocumentDetector                      │
│  └── autoCaptureDetector: AutoCaptureDetector                │
│                                                              │
│  Page Store:                                                 │
│  └── pageStore: ScanPageStore                                │
└──────┬───────────────────────────────────────────────────────┘
       │ 驅動
       ├─────────────────────────────────────────────────────┐
       │                                                     │
       ▼                                                     ▼
┌─────────────────────────┐              ┌──────────────────────────┐
│      Core Layer          │              │       UI Layer           │
│                          │              │                          │
│ Camera/                  │              │ Views/                   │
│ ├─ CameraManager         │              │ ├─ CameraScanView        │
│ │  (AVFoundation)        │              │ │  (主相機畫面)           │
│ └─ CameraLens enum       │              │ ├─ ScanGuideOverlay      │
│                          │              │ │  (邊框偵測 HUD)         │
│ Motion/                  │              │ ├─ ScanControlBar        │
│ └─ MotionSensor          │              │ │  (底部控制列)           │
│    (CoreMotion)          │              │ ├─ DocumentDetailView    │
│                          │              │ │  (頁面檢視+AI工具)      │
│ Detection/               │              │ ├─ LoupeCropView         │
│ ├─ DocumentDetector      │              │ │  (放大鏡角點裁切)       │
│ │  (Vision)              │              │ ├─ PDFExportSheet        │
│ ├─ AutoCaptureDetector   │              │ │  (PDF 匯出面板)         │
│ └─ BarcodeScannerService │              │ ├─ TrashBinView          │
│                          │              │ │  (垃圾桶管理)           │
│ Dewarp/                  │              │ ├─ SettingsView          │
│ ├─ DynamicDewarpPredictor│              │ │  (四大設定分類)         │
│ ├─ DewarpGeometry        │              │ └─ PhotoImportPickerView │
│ ├─ DewarpMesh            │              │    (相簿批次匯入)         │
│ └─ BookPageSplitter      │              │                          │
│                          │              │ ViewModels/              │
│ AI/                      │              │ └─ ScannerViewModel      │
│ ├─ ShadowRemovalProcessor│              │    (主協調器)             │
│ ├─ DeblurProcessor       │              └──────────────────────────┘
│ ├─ FingerRemovalProcessor│
│ └─ HandwritingRemovalProc│
│                          │
│ Rectification/           │
│ └─ DocumentRectifier     │
│    (透視裁切+6濾鏡)       │
│                          │
│ Storage/                 │
│ └─ ScanPageStore         │
│    (JPEG+JSON+30天垃圾桶) │
│                          │
│ OCR/                     │
│ └─ OCRService            │
│    (Vision 離線辨識)      │
│                          │
│ Export/                  │
│ ├─ PDFExporter           │
│ └─ DocumentNamingService │
│                          │
│ Metal/                   │
│ ├─ Shaders.metal         │
│ ├─ MetalDewarpRenderer   │
│ └─ MetalOffscreenDewarper│
└─────────────────────────┘
```

---

## 4. CoreML 神經網路模型目錄

以下為從原廠 IPA 逆向取得的完整 CoreML 模型清單（均為加密 Espresso 格式）：

| 模型名稱 | 推測用途 | 權重大小 | 仿製版替代演算法 |
|---------|---------|---------|----------------|
| `BlackpointClassificationModel_v1.0.1` | 黑點分類判斷 | ~53 KB | CIFilter `colorMonochrome` 自動判斷 |
| `BlackpointModel_v1.0.1` | 黑點灰度預測 | ~909 KB | Otsu 二值化閾值 |
| `ContentMaskModel_v3` | 文件內容遮罩生成 | ~1 MB | Vision `VNDetectRectanglesRequest` |
| `DeblurModel_v1.1` | 文字去模糊超解析度 | **15.5 MB** | 雙尺度 Unsharp Masking + 筆畫加深 |
| `DistillationModel` | 手機擋光陰影蒸餾消除 | ~967 KB | Retinex 反射率分解 + 亮度均化 |
| `FingerMaskModel` | 手指像素遮罩語義分割 | ~131 KB | YCbCr 膚色空間邊界 12% 偵測 |
| `FreeformModel` | 25×25 曲面 Dewarp 網格預測 | 未知 (加密) | 高斯拋物線 + 三次樣條估算 |
| `HandwritingModel` | 彩色手寫筆跡偵測 | 未知 (加密) | HSV 高飽和度過濾 (S>0.5) |
| `InpainterModel` | 手指修復填補 (Inpainting) | 未知 (加密) | Poisson 泊松平滑填補 |
| `PPTPModel` | 書脊中縫位置預測 | 未知 (加密) | 垂直光度積分 + 梯度最小值 |
| `SceneTextModel` | 場景文字偵測 (OCR 前置) | 未知 (加密) | Apple Vision `VNRecognizeTextRequest` |

> **重要**：仿製版採用 Clean Room 純演算法方式，**不包含任何原廠二進位模型權重**，徹底規避版權與法律風險。

---

## 5. 原廠第三方框架清單

從 REA 逆向得到的 `Payload/vFlat.app/Frameworks/` 完整清單：

```
Frameworks/
├── AEXML.framework (209 KB)
├── AcknowList.framework (399 KB)
├── FBAEMKit.framework
├── FBSDKCoreKit.framework
├── FBSDKLoginKit.framework
├── FirebaseABTesting.framework
├── FirebaseAnalytics.framework
├── FirebaseAuth.framework
├── FirebaseCrashlytics.framework
├── FirebaseCore.framework
├── FirebaseInstallations.framework
├── FirebaseMessaging.framework
├── FirebaseRemoteConfig.framework
├── FirebaseSharedSwift.framework (537 KB)
├── FirebaseStorage.framework (678 KB)
├── GTMSessionFetcher.framework (424 KB)
├── GoogleDataTransport.framework (398 KB)
├── GoogleUtilities.framework (291 KB)
├── JJFloatingActionButton.framework (421 KB)
├── KeychainAccess.framework (370 KB)
├── Kronos.framework (233 KB)
├── Lottie.framework (3.57 MB)
├── PanModal.framework (249 KB)
├── Promises.framework (224 KB)
├── QuickTableViewController.framework (284 KB)
├── RecaptchaInterop.framework (88 KB)
├── SFSafeSymbols.framework (8.79 MB)
├── Socket.framework (294 KB)
├── SwiftProtobuf.framework (3.43 MB)
├── SwiftUIPager.framework (358 KB)
├── Then.framework (111 KB)
├── UITextView_Placeholder.framework (96 KB)
├── ZIPFoundation.framework (471 KB)
├── absl.framework (1.36 MB)
└── grpc.framework
```

---

## 6. UI 畫面規格

### 6.1 主相機畫面 `CameraScanView`

**全螢幕 ZStack 架構（由下至上 8 層）：**

```
Layer 8: 白色快門閃爍層 (isShutterFlashing)
Layer 7: 錯誤提示橫幅 (底部置中, 紅底圓角, 3秒自動消失)
Layer 6: 頂部+底部工具列 VStack
  ├── 頂部主導航列 (HStack)
  │   ├── [左] 匯出PDF按鈕 (Capsule, 顯示頁數角標)
  │   └── [右] 設定齒輪圖示 (Circle背景)
  ├── 次頂部功能列 (HStack)
  │   ├── 閃光燈切換 (bolt / bolt.fill, 不可用時淡化)
  │   ├── 定時器切換 (timer, 啟用時顯示秒數 badge)
  │   ├── AUTO SCAN 開關 (Capsule 膠囊)
  │   └── 濾鏡模式快切 (黃色圖示 + 模式名)
  └── ScanControlBar (底部)
Layer 5: QR/條碼懸浮智慧膠囊 (頂部 100pt 下方, 春季動畫)
Layer 4: 定時拍照大號倒數數字 (120pt, thin, 居中)
Layer 3: 自動捕捉環狀進度指示器 (底部 200pt 上方)
Layer 2: ScanGuideOverlay (文件邊框 + 姿態儀 + 「尋找文件」標籤)
Layer 1: MetalDewarpViewRepresentable (MTKView, ignoresSafeArea)
Layer 0: Color.black (底色)
```

**底部控制列 `ScanControlBar` 細節：**

```
VStack
├── 頁數模式選擇器 (Capsule 膠囊容器)
│   ├── [1頁] 按鈕 (選中時黃色文字 + 半透明白背景)
│   ├── [2頁] 按鈕
│   └── [自動] 按鈕 (等同 isAutoCaptureEnabled)
├── 資料夾選擇膠囊 (folder 圖示 + 資料夾名 + chevron.down)
└── 快門主列 (HStack)
    ├── [左 32pt padding] 縮圖卡片 (48×60, 圓角6, 白邊框2pt)
    │   ├── lastThumbnail 填充圖
    │   └── 頁數角標 (黃底黑字 Capsule, offset +18,+26)
    ├── [中] 快門按鈕 (ZStack)
    │   ├── 外環 Circle stroke 76pt (白, 4.5pt)
    │   └── 內填 Circle fill 62pt (白)
    │       └── 後處理中: ProgressView / 倒數中: 秒數文字
    └── [右 32pt padding] 相簿圖示 (photo, 26pt, 48×48 tap area)
```

**顏色規範：**
- 主強調色 (黃)：`rgb(0.98, 0.82, 0.35)` = `#FAD159`
- 主操作色 (綠)：`rgb(0.22, 0.85, 0.45)` = `#38D973`
- 自動捕捉圈：`rgb(0.22, 0.85, 0.45)`
- 錯誤橫幅：`rgb(0.75, 0.2, 0.2)` opacity 0.92
- 相機背景：`Color.black`

---

### 6.2 文件檢視頁 `DocumentDetailView`

**結構 (白底 VStack 4段)：**

```
1. 頂部導航列 (< 相機 | 頁數·資料夾 | 分享匯出)
   ├── < 相機 (chevron.left + 文字)
   ├── "{N}頁 · {folderName}" 居中標題 (bold 16pt)
   └── 分享/匯出 square.and.arrow.up (無頁面時灰色禁用)

2. 中央文件圖展示區 (GeometryReader ZStack)
   ├── 白色底 Color(white: 0.96)
   ├── Image 顯示 lastPreviewImage (.scaledToFit, shadow)
   ├── 空白態: doc.text.magnifyingglass 圖示 + 提示文字
   ├── 後處理中遮罩: 半透明黑 + CircularProgressViewStyle
   ├── 「辨識文字」懸浮 Capsule 按鈕 (底部 20pt, 綠色)
   └── Toast 提示浮層 (Capsule, 底部 72pt)

3. 功能橫列 (按需展開, 動畫切換)
   ├── 濾鏡選擇橫列 (showingFilterSelector)
   │   └── ScrollView .horizontal: 6種濾鏡圓形圖示
   └── AI 旗艦修復橫列 (showingAISelector)
       └── ScrollView .horizontal: 6個功能
           ├── 極致全開 (橙色漸層圓形, wand.and.stars.inverse)
           ├── 曲面展平 (arrow.left.and.right.square)
           ├── 消除陰影 (sun.max.fill)
           ├── 文字銳化 (sparkles.rectangle.stack)
           ├── 手指抹除 (hand.raised.slash)
           └── 清除筆跡 (pencil.slash)

4. 底部功能操作列 (HStack 等距4按鈕)
   ├── 分享/匯出 (square.and.arrow.up)
   │   └── 點擊 → ConfirmationDialog (延遲0.35s)
   │       ├── 「存為 JPG 至相簿」
   │       ├── 「匯出 JPG 檔案」(UIActivityViewController)
   │       └── 「匯出 PDF」→ PDFExportSheet
   ├── 裁剪 (crop) → LoupeCropView
   ├── 濾鏡 (slider.horizontal.3) → 展開/收起濾鏡橫列
   └── AI 修復 (wand.and.stars) → 展開/收起 AI 橫列
```

**ActiveDetailModal 統一 Sheet 管理：**
```swift
enum ActiveDetailModal: Identifiable {
    case pdfExport
    case ocrResult
    case jpgShare(URL)
}
// 使用單一 .sheet(item: $activeModal) 避免多 sheet 衝突
```

---

### 6.3 放大鏡裁切視圖 `LoupeCropView`

**功能規格：**
- 全螢幕黑底顯示原始圖
- 4個角點控制點：`tl / tr / br / bl` (30pt 圓形白圈)
- 半透明藍色多邊形遮罩覆蓋選取區域
- 放大鏡 (Loupe)：拖曳任一角點時，在角點正上方顯示 2.2x 放大視圖
- 使用具名座標空間 `"LoupeCropSpace"` 解決手勢漂移問題
- `DragGesture(minimumDistance: 0).coordinateSpace(name: cropSpaceName)`
- 完成後呼叫 `viewModel.applyCrop(document: newDocument)`

---

### 6.4 PDF 匯出面板 `PDFExportSheet`

**輸入參數：**
```swift
PDFExportSheet(
    pages: [ScanPage],     // 頁面列表
    store: ScanPageStore,  // 儲存服務
    defaultPrefix: String  // 預設資料夾名稱
)
```

**UI 元素：**
- 檔名輸入欄 (TextField, 預設: `{folderName}_{timestamp}`)
- PDF 尺寸選擇: A4 / 適應寬度 / 原圖比例
- 密碼保護 Toggle + SecureField
- 可搜尋文字 (OCR 文字層) Toggle
- 匯出按鈕 → 生成 PDF → UIActivityViewController

---

### 6.5 設定中心 `SettingsView`

**NavigationView > Form 4大 Section：**

```
Section 1: 相機與硬體拍攝設定
├── Picker 相機鏡頭: 超廣角(推薦) / 廣角 / 長焦
├── Picker 掃描解析度: 4K / 1080p / 720p
├── Picker 定時拍照器: 關閉 / 2s / 3s / 5s / 7s
├── Toggle 自動掃描 (防手震)
├── Toggle 觸控螢幕拍照
├── Toggle 拍照前自動對焦
├── Toggle 靜音快門
├── Toggle 觸覺震動回饋
└── Toggle 相機輔助引導格線

Section 2: 掃描與書籍後處理設定
├── Picker 雙頁翻頁順序: 從左到右 / 從右到左
├── Toggle 自動透視裁剪邊界
├── Toggle 25x25 自由曲面展開 (Dewarp)
├── Toggle 智慧色彩校正與純白去底色
├── Toggle 使文字變暗
└── Picker AI 修復儲存方式: 覆蓋此頁面 / 另存新頁面

Section 3: PDF 與檔案匯出設定
├── Toggle 自動備份新掃描至相簿 (.jpg)
├── TextField 預設資料夾名稱 (默認: "Scan")
├── [顯示] PDF 預設尺寸: A4 / 適應寬度 / 原圖
├── [顯示] 可搜尋 PDF: 自動嵌入 (支援反白複製)
└── [顯示] PDF 密碼保護: 匯出時可自訂加密

Section 4: 系統偏好與頁面管理
├── Picker 啟動畫面: 相機取景 / 資料庫首頁
├── Button 垃圾桶 (最近刪除) → TrashBinView
├── [顯示] 目前已儲存頁數: {N} 頁
└── Button(role: .destructive) 移至垃圾桶 (清除所有)

Section 5: 關於與技術規格 (唯讀展示)
├── 版本號: vX.Y.Z (Build NNN)
├── 曲面拉平技術: 25x25 Dynamic Spline + Metal GPU
├── AI 離線加速: Apple Neural Engine / CoreImage
└── 相機實際幀率: {N} fps (動態讀取)
```

---

### 6.6 垃圾桶 `TrashBinView`

```
NavigationView > List
├── Section "最近 30 天內刪除的頁面"
│   └── ForEach trashPages
│       └── HStack
│           ├── Image 縮圖 (40×50)
│           ├── VStack
│           │   ├── "第 {index} 頁"
│           │   └── "還有 {days} 天過期"
│           └── Button "還原"
├── Toolbar 「全部還原」按鈕
└── Toolbar 「清空垃圾桶」按鈕 (red)
```

---

### 6.7 相簿匯入 `PhotoImportPickerView`

- PHPickerViewController 包裝 (UIViewControllerRepresentable)
- 支援多選 (filter: .images)
- 匯入後自動套用 `viewModel.importImages(_:options:)` 管線
- ImportOptions: autoCrop, colorEnhance, darkenText

---

### 6.8 掃描引導疊加 `ScanGuideOverlay`

```
ZStack (ignoresSafeArea)
├── 文件邊界四邊形 (Shape, 半透明綠框)
│   ├── isDocumentDetected=true: 綠色實框 + 角點圓點
│   └── isDocumentDetected=false: 白色虛框 (尋找文件)
├── 「尋找文件中…」標籤 (中央, 僅無文件時顯示)
└── 俯拍姿態儀 (motionSensor.roll/pitch 超過閾值時警示)
```

---

## 7. 核心演算法規格

### 7.1 `DynamicDewarpPredictor` — 25×25 網格預測器

```swift
// 演算法：高斯拋物線 + 三次樣條插值
// 輸入：UIImage (書頁掃描圖)
// 輸出：[simd_float2] 25×25 = 625 個 UV 座標點

func predictGrid(for image: UIImage) -> [[simd_float2]] {
    // 1. 灰度化並找水平掃描線亮度分佈
    // 2. 使用高斯擬合找書脊拱度曲線 (中心凹陷點)
    // 3. 以拋物線 y = a*x² + b*x + c 近似中縫曲率
    // 4. 在 25 列方向生成三次樣條補間網格
    // 5. 返回正規化 (0.0~1.0) UV 座標陣列
}
```

**DewarpMesh：**
- 24×24 格子 = 1152 個三角形
- 頂點格式：`simd_float2` (UV) + `simd_float4` (位置)

### 7.2 `MetalOffscreenDewarper` — GPU 離屏展開

```swift
// Metal Compute Shader 執行離屏高畫質 Dewarp
// 輸入：UIImage + [[simd_float2]] 網格 + 強度 (0.0~1.0)
// 輸出：UIImage (展平後)

func dewarpImage(
    image: UIImage,
    curvedGrid: [[simd_float2]],
    dewarpStrength: Float = 1.0
) -> UIImage?
```

### 7.3 `MetalDewarpRenderer` — 60fps 即時渲染

```swift
// MTKViewDelegate
// 每幀從 CameraManager 取得 CVPixelBuffer
// 套用當前 Dewarp 網格即時渲染到 MTKView
// 預覽模式使用平坦網格 (強度=0.0, 零合成曲面)

func feedFrame(_ pixelBuffer: CVPixelBuffer)
func updateMesh(with grid: [[simd_float2]])
func setDewarpStrength(_ strength: Float, mode: Int)
```

**Shaders.metal 著色器功能：**
- Vertex Shader：25×25 Dewarp 頂點變換
- Fragment Shader：雙線性插值紋理採樣
- 邊緣羽化 (書頁邊界淡出)
- 弧長正規化輸出

### 7.4 `DocumentDetector` — 即時邊界偵測

```swift
// Vision 雙引擎：VNDetectRectanglesRequest (主) + 
//                手動邊緣偵測 (備援)
// EMA 平滑：係數 α=0.3，防止邊框抖動
// 輸出：DetectedDocument { topLeft/Right/Bottom corners, confidence }

// 靜態方法 (拍照當下重新偵測，不走 EMA)：
static func detectOnce(in pixelBuffer: CVPixelBuffer) -> DetectedDocument?
static func detectOnce(in image: UIImage) -> DetectedDocument?
```

### 7.5 `AutoCaptureDetector` — 自動快門

```swift
// 幾何穩定度 + 陀螺儀雙重判斷
// stabilityProgress: Double (0.0~1.0, 超過閾值觸發快門)
// 冷卻時間：1.8 秒 (避免連打)
// 穩定判斷：角點位移 < 8px 且 motion roll/pitch < 0.1 rad

func processFrame(document: DetectedDocument?, at time: TimeInterval) -> Bool
func reset()
var stabilityProgress: Double
```

### 7.6 `DocumentRectifier` — 透視裁切與濾鏡

```swift
// 透視裁切
func geometryCorrected(image: UIImage, document: DetectedDocument?, autoCrop: Bool) -> UIImage
func correctPerspective(image: UIImage, document: DetectedDocument) -> UIImage?

// 6 種色彩濾鏡
enum DocumentFilterMode: String, CaseIterable, Identifiable {
    case auto      = "自動"    // 圖示: wand.and.stars
    case color     = "彩色"    // 圖示: photo.on.rectangle
    case grayscale = "灰階"    // 圖示: circle.lefthalf.filled
    case blackWhite = "黑白"   // 圖示: squareshape.fill
    case dark      = "文字"    // 圖示: doc.text.fill
    case original  = "原始"    // 圖示: photo
}

func applyFilter(_ mode: DocumentFilterMode, to image: UIImage, 
                 enhanceColor: Bool, darkenText: Bool) -> UIImage
```

### 7.7 `ShadowRemovalProcessor` — 陰影消除

```
演算法：Retinex 反射率重構
1. 轉換至 YCbCr 色彩空間
2. 對 Y (亮度) 通道做大視窗高斯模糊 (sigma=80)
3. 反射率 R = S / (L + ε) — 去除低頻光照分量
4. Gamma 校正並增益映射 (亮部壓縮，暗部提升)
5. 合回 CbCr 通道還原彩色

輸入: UIImage
輸出: UIImage? (失敗時 nil)
```

### 7.8 `DeblurProcessor` — 文字銳化去模糊

```
演算法：雙尺度非銳化遮罩 (Unsharp Masking)
1. 將 YCbCr 亮度通道分離
2. 生成 sigma=1.0 (細節層) 和 sigma=2.5 (邊緣層) 高斯模糊
3. 高頻殘差 = 原始 - 粗模糊
4. 輸出 = 原始 + 細模糊 * α + 邊緣 * β (α=0.7, β=0.4)
5. 筆畫加深：對高梯度像素額外強化暗度

輸入: UIImage
輸出: UIImage
```

### 7.9 `FingerRemovalProcessor` — 手指抹除

```
演算法：YCbCr 膚色空間偵測 + Poisson 平滑
1. 邊界 12% 寬度設為掃描區 (四周各 6%)
2. 對邊界像素做 YCbCr 膚色判斷
   - Y: 60~250, Cb: 80~130, Cr: 135~175
3. 將膚色像素替換為周邊平均色
4. 對遮罩區域執行 Poisson 平滑使邊界自然

輸入: UIImage
輸出: UIImage
```

### 7.10 `HandwritingRemovalProcessor` — 筆跡消除

```
演算法：HSV 高動態飽和度過濾
1. 轉換至 HSV 色彩空間
2. 飽和度 S > 0.50 且非黑色 (V > 0.15) → 視為彩色筆跡
3. 將彩色筆跡像素替換為純白
4. 輸出只保留黑色文字，消除彩色筆記

輸入: UIImage
輸出: UIImage
```

### 7.11 `BookPageSplitter` — 雙頁分割

```
演算法：垂直光度積分分析
1. 對圖像做垂直方向平均亮度投影
2. 尋找中央 30% 範圍內的最大亮度點 (書脊)
3. 以該點為分割線切分左右頁
4. 返回 {leftPage, rightPage} 並依 LTR/RTL 排序

func detectSpineRatio(image: UIImage) -> CGFloat  // 0.0~1.0
func splitPage(image: UIImage, splitRatio: CGFloat) -> SplitResult?
```

### 7.12 `OCRService` — 離線文字辨識

```swift
// Apple Vision VNRecognizeTextRequest
// 支援語言：繁體中文、簡體中文、英文（自動偵測）
// 解析度：accurate (高精度模式)
// 離線：完全本機推論，零網路

func recognizeText(in image: UIImage) async -> String?
// 結果寫回 pageStore.updateOCR(id:text:)
```

### 7.13 `CameraManager` — 相機硬體驅動

```swift
// AVFoundation AVCaptureSession
// 三鏡頭支援
enum CameraLens: String, CaseIterable, Identifiable {
    case ultraWide = "超廣角 0.5x (推薦)"
    case wide      = "廣角 1x"
    case telephoto = "長焦 2x~3x"
    var displayName: String
}

// 解析度選項
enum ScanResolution: String, CaseIterable, Identifiable {
    case ultraHD4K  = "4K 超高清"
    case fullHD1080 = "1080p 高清"
    case hd720      = "720p 標準"
    var displayName: String
}

// 關鍵方法
func setupSession(resolution: ScanResolution, lens: CameraLens)
func startSession()
func stopSession()
func latestPixelBufferSnapshot() -> CVPixelBuffer?
func setTorch(on: Bool)
func focusAndExposeCenterIfNeeded()
func setResolution(_ resolution: ScanResolution)
func setLens(_ lens: CameraLens)

// 發布屬性
@Published var isTorchAvailable: Bool
@Published var isTorchOn: Bool
@Published var activeFrameRate: Double

// 輔助
static func makeImage(from buffer: CVPixelBuffer) -> UIImage?
```

---

## 8. 資料模型與儲存規格

### 8.1 `ScanPage` — 頁面資料模型

```swift
struct ScanPage: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var filterMode: DocumentFilterMode
    var ocrText: String?
    var document: DetectedDocument?  // 裁切角點
    
    // 磁碟檔名 (非路徑，相對於 Documents/vFlat/pages/)
    let rawFileName: String        // 已裁切未上色原圖
    let processedFileName: String  // 後處理成品
    let thumbnailFileName: String  // 縮圖 (120×160, JPEG 0.6)
}
```

### 8.2 `TrashPage` — 垃圾桶頁面

```swift
struct TrashPage: Codable, Identifiable {
    let page: ScanPage
    let deletedAt: Date
    // 30天後自動過期
    var daysUntilExpiry: Int {
        let expiry = deletedAt.addingTimeInterval(30 * 86400)
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0)
    }
}
```

### 8.3 `DetectedDocument` — 文件角點

```swift
struct DetectedDocument: Codable, Equatable {
    var topLeft: CGPoint      // 正規化 0.0~1.0 (相對圖像尺寸)
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    var confidence: Float     // 0.0~1.0
}
```

### 8.4 `DetectedBarcode` — 條碼資訊

```swift
struct DetectedBarcode: Equatable {
    let payloadString: String
    let symbology: VNBarcodeSymbology
    var isURL: Bool
    var iconName: String  // SF Symbol (qrcode / barcode / etc.)
}
```

### 8.5 `ScanPageStore` — 儲存服務

```swift
// 磁碟路徑結構
// Documents/vFlat/pages/           ← 頁面 JPEG 圖
// Documents/vFlat/thumbnails/      ← 縮圖 JPEG
// Documents/vFlat/index.json       ← 頁面索引
// Documents/vFlat/trash.json       ← 垃圾桶索引

class ScanPageStore: ObservableObject {
    @Published private(set) var pages: [ScanPage]
    @Published private(set) var trashPages: [TrashPage]
    
    // 基礎操作
    func load()
    func append(processed: UIImage, raw: UIImage?, filterMode: DocumentFilterMode, document: DetectedDocument?) async -> ScanPage?
    func delete(id: UUID)           // 移入垃圾桶
    func deleteAll()                // 全部移入垃圾桶
    
    // 垃圾桶操作
    func restore(id: UUID)
    func restoreAll()
    func permanentlyDelete(id: UUID)
    func emptyTrash()
    func pruneExpiredTrash()        // 清除 30 天過期項目
    
    // 頁面更新
    func updateProcessed(id: UUID, image: UIImage, filterMode: DocumentFilterMode) async -> Bool
    func updateRaw(id: UUID, image: UIImage) async
    func updateOCR(id: UUID, text: String?)
    
    // 讀取
    func image(for page: ScanPage) -> UIImage?
    func rawImage(for page: ScanPage) -> UIImage?
    func thumbnail(for page: ScanPage) -> UIImage?
    var lastPage: ScanPage?
    var count: Int
}
```

### 8.6 儲存格式規格

| 類型 | 格式 | 壓縮品質 | 說明 |
|------|------|---------|------|
| 處理後圖片 | JPEG | 0.92 | 主要顯示圖 |
| 原始裁切圖 | JPEG | 0.90 | 非破壞性備份 |
| 縮圖 | JPEG | 0.60 | 120×160px |
| 索引檔 | JSON (Codable) | - | pages + trash |

---

## 9. 設定項目對齊表

| 原廠設定鍵 | 仿製版 UserDefaults 鍵 | 類型 | 預設值 |
|-----------|----------------------|------|--------|
| `setting_start_screen` | `vflat_start_screen_mode` | String | `"相機取景 (秒開即掃)"` |
| (鏡頭選擇) | `vflat_camera_lens` | String | `"超廣角 0.5x (推薦)"` |
| (解析度) | `vflat_scan_resolution` | String | `"4K 超高清"` |
| (定時器) | `vflat_camera_timer` | Int | `0` |
| `ai_feature_save_method` | `vflat_ai_save_method` | String | `"覆蓋此頁面"` |
| (自動快門) | `vflat_auto_capture` | Bool | `false` |
| (觸控快門) | `vflat_touch_to_scan` | Bool | `false` |
| (靜音快門) | `vflat_disable_shutter_sound` | Bool | `false` |
| (觸覺回饋) | `vflat_haptic_feedback` | Bool | `true` |
| (自動對焦) | `vflat_autofocus` | Bool | `true` |
| (引導格線) | `vflat_scan_guide` | Bool | `true` |
| (雙頁順序) | `vflat_two_pages_ltr` | Bool | `true` |
| (自動裁切) | `vflat_preset_auto_crop` | Bool | `true` |
| (曲面展平) | `vflat_preset_curve_correction` | Bool | `false` |
| (色彩校正) | `vflat_preset_color_enhance` | Bool | `true` |
| (文字加深) | `vflat_preset_text_darken` | Bool | `true` |
| (自動備份) | `vflat_auto_save_to_gallery` | Bool | `false` |
| (資料夾名) | `vflat_current_folder` | String | `"Scan"` |

---

## 10. 完整源碼目錄結構

```
ios/
├── Package.swift                    # SPM 備援 (本機除錯)
├── Info.plist                       # 由 project.yml 產生
├── README.md
└── Sources/
    ├── Core/
    │   ├── Camera/
    │   │   └── CameraManager.swift           # AVFoundation 三鏡頭驅動
    │   ├── Motion/
    │   │   └── MotionSensor.swift            # CoreMotion 俯拍傾角感測
    │   ├── Detection/
    │   │   ├── DocumentDetector.swift        # Vision 雙引擎邊界偵測
    │   │   ├── AutoCaptureDetector.swift     # 幾何+陀螺儀自動快門
    │   │   └── BarcodeScannerService.swift   # 即時 QR/條碼辨識
    │   ├── Dewarp/
    │   │   ├── DynamicDewarpPredictor.swift  # 25×25 高斯拋物線預測
    │   │   ├── DewarpGeometry.swift          # 弧長積分輸出尺寸計算
    │   │   ├── DewarpMesh.swift              # 24×24 Metal 頂點拓撲
    │   │   └── BookPageSplitter.swift        # 光度積分雙頁分割
    │   ├── AI/
    │   │   ├── ShadowRemovalProcessor.swift  # Retinex 陰影消除
    │   │   ├── DeblurProcessor.swift         # 雙尺度 USM 去模糊
    │   │   ├── FingerRemovalProcessor.swift  # YCbCr+Poisson 手指抹除
    │   │   └── HandwritingRemovalProcessor.swift # HSV 筆跡消除
    │   ├── Rectification/
    │   │   └── DocumentRectifier.swift       # 透視裁切 + 6 大色彩濾鏡
    │   ├── Storage/
    │   │   └── ScanPageStore.swift           # JPEG磁碟+JSON索引+30天垃圾桶
    │   ├── OCR/
    │   │   └── OCRService.swift              # Vision 離線 OCR
    │   ├── Export/
    │   │   ├── DocumentNamingService.swift   # 時間戳智慧命名
    │   │   └── PDFExporter.swift             # PDFKit 合成+密碼+OCR層
    │   └── Metal/
    │       ├── Shaders.metal                 # 頂點+片段著色器
    │       ├── MetalOffscreenDewarper.swift   # 離屏高畫質 GPU Dewarp
    │       └── MetalDewarpRenderer.swift      # MTKView 60fps 即時渲染
    ├── UI/
    │   ├── Views/
    │   │   ├── CameraScanView.swift           # 主相機畫面 (8層 ZStack)
    │   │   ├── ScanGuideOverlay.swift         # 文件邊框+姿態儀 HUD
    │   │   ├── ScanControlBar.swift           # 底部控制列
    │   │   ├── DocumentDetailView.swift       # 頁面檢視+AI工具
    │   │   ├── LoupeCropView.swift            # 放大鏡4角點裁切
    │   │   ├── PDFExportSheet.swift           # PDF 匯出面板
    │   │   ├── TrashBinView.swift             # 垃圾桶 (最近刪除)
    │   │   ├── SettingsView.swift             # 4大項設定中心
    │   │   └── PhotoImportPickerView.swift    # PHPicker 相簿批次匯入
    │   └── ViewModels/
    │       └── ScannerViewModel.swift         # 主協調器 (@MainActor)
    └── vFlatApp/
        └── vFlatApp.swift                     # App 進入點
```

---

## 11. 建置與 CI/CD 規格

### 11.1 XcodeGen 設定 `project.yml`

```yaml
name: vFlat
options:
  bundleIdPrefix: com.voyagerx.ios
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "16.0"

settings:
  base:
    MARKETING_VERSION: "1.5.9"     # 每次修改必須推進
    CURRENT_PROJECT_VERSION: "159"  # 同步更新
    SWIFT_VERSION: "5.9"

targets:
  vFlat:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: ios/Sources/Core
      - path: ios/Sources/UI
      - path: ios/Sources/vFlatApp
    info:
      path: ios/Info.plist
      properties:
        CFBundleDisplayName: "vFlat Scan"
        NSCameraUsageDescription: "..."
        NSPhotoLibraryUsageDescription: "..."
        NSPhotoLibraryAddUsageDescription: "..."
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait  # 僅直向
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: "com.voyagerx.ios.vflat"
        CODE_SIGNING_ALLOWED: NO  # GitHub Actions 無需簽章
```

### 11.2 GitHub Actions 工作流程

```yaml
# .github/workflows/build.yml
name: Build vFlat IPA

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      
      - name: Install XcodeGen
        run: brew install xcodegen
        
      - name: Generate Xcode Project
        run: xcodegen generate
        
      - name: Build (no-sign)
        run: |
          xcodebuild -scheme vFlat \
            -destination "generic/platform=iOS" \
            -configuration Release \
            CODE_SIGNING_ALLOWED=NO \
            ARCHS=arm64 \
            build
            
      - name: Package IPA
        run: |
          # 打包 .app → .ipa (無需 entitlements)
          mkdir -p Payload
          cp -r build/Release-iphoneos/vFlat.app Payload/
          zip -r vFlat.ipa Payload/
          
      - uses: actions/upload-artifact@v4
        with:
          name: vFlat.ipa
          path: vFlat.ipa
```

### 11.3 版本號同步規則

**5 個位置必須同時更新（以 VERSION 為唯一真相）：**

| 檔案 | 欄位 |
|------|------|
| `VERSION` | 純文字 `v1.5.9` |
| `project.yml` | `MARKETING_VERSION: "1.5.9"` |
| `project.yml` | `CURRENT_PROJECT_VERSION: "159"` |
| `ios/Info.plist` | `CFBundleShortVersionString` / `CFBundleVersion` |
| `AGENT_HANDOVER.md` | 頂部版本字串 |

---

## 12. 版本管理規範

遵循語意化版本 `vX.Y.Z`：
- **PATCH (Z)**：Bug 修復、UI 微調
- **MINOR (Y)**：新功能、新設定項目
- **MAJOR (X)**：架構重構、破壞性改動

**每次修改必須：**
1. 更新上述 5 個版本號位置
2. `git add .`
3. `git commit -m "feat: 說明功能 (bump: v1.5.X)"`
4. `git push`

---

## 13. AI Agent 執行清單

### Phase 1：環境確認 ✅

- [ ] 確認工作目錄 `h:\我的雲端硬碟\工具程式\vflat\`
- [ ] 確認 Git 已初始化且遠端指向 `https://github.com/y41418845-CY/vflat`
- [ ] 確認 `ios/Sources/` 目錄結構完整
- [ ] 確認 `project.yml` 版本號一致性 (5處)

### Phase 2：核心功能完善

- [ ] **P1: BarcodeScannerService** — 確認即時條碼/QR 在 CameraManager 幀回調中正確整合
- [ ] **P1: DocumentDetector.detectOnce(in image: UIImage)** — 確認靜態方法支援 UIImage 輸入 (相簿匯入使用)
- [ ] **P1: ScanPageStore 版本遷移** — 確認 JSON Codable 向後相容舊版頁面索引
- [ ] **P2: PDFExporter** — 確認 OCR 文字層嵌入、密碼加密、A4/適應/原圖三種尺寸
- [ ] **P2: PhotoImportPickerView** — 確認 PHPicker 多選後批次套用 ImportOptions 管線
- [ ] **P3: 雙頁分割** — 實機測試不同書籍寬度的 `BookPageSplitter.detectSpineRatio`

### Phase 3：UI 對齊驗證

- [ ] 確認 `Color(red: 0.98, green: 0.82, blue: 0.35)` 黃色主題貫穿全 UI
- [ ] 確認快門白光閃爍動畫 (0.08s easeOut + 0.12s easeIn)
- [ ] 確認 `ActionSheet` dismiss 競態保護 (延遲 0.35s)
- [ ] 確認多 Sheet 衝突：使用 `ActiveDetailModal` 單一 sheet(item:)
- [ ] 確認 Toast 提示訊息系統運作 (照片儲存成功等)
- [ ] 確認相機權限拒絕時的友善提示頁面

### Phase 4：測試驗證

- [ ] 執行 `xcodegen generate` 確認 Xcode 專案生成無錯誤
- [ ] 執行 Unit Tests (DewarpTests) 通過
- [ ] 觸發 GitHub Actions 確認 CI 建置產出 IPA artifact
- [ ] 實機安裝 (AltStore / TrollStore) 進行功能驗證

### Phase 5：功能待辦 (未來)

- [ ] **多資料夾管理** — 建立/重新命名/頁面移動
- [ ] **區網 Web 傳送** — Bonjour HTTP 伺服器
- [ ] **PDF 批次多頁縮圖預覽** — 匯出前所有頁面縮圖列表

---

## 14. 已知問題與陷阱

### 14.1 SwiftUI 多 Sheet 衝突 (重大)

```
問題：同一 View 樹宣告多個 .sheet(isPresented:) → 後者覆蓋前者
解法：使用單一 enum ActiveDetailModal: Identifiable + .sheet(item: $activeModal)
```

### 14.2 ActionSheet Dismiss 競態

```
問題：ConfirmationDialog 按鈕回調中直接拉起新 Sheet → UIKit 靜默丟棄
解法：DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ... }
```

### 14.3 相片儲存正確 API

```
錯誤：UIImageWriteToSavedPhotosAlbum (無錯誤回傳)
正確：PHPhotoLibrary.shared().performChanges({ 
          PHAssetChangeRequest.creationRequestForAsset(from: image) 
      }) { success, error in ... }
```

### 14.4 巢狀 ObservableObject 不傳遞

```
問題：CameraManager/MotionSensor/ScanPageStore 的 @Published 不會自動
      觸發父層 ScannerViewModel 的 objectWillChange
解法：在 init 中 Combine sink 並轉發：
      cameraManager.objectWillChange.sink { self.objectWillChange.send() }
```

### 14.5 超廣角鏡頭可用性

```
注意：不是所有 iPhone 都有超廣角鏡頭 (iPhone 11+ 才有)
解法：CameraManager.setupSession() 應在 AVCaptureDevice.default(.builtInUltraWideCamera)
      回傳 nil 時自動降級到廣角
```

### 14.6 版本號不一致風險

```
注意：5 個位置必須同時更新，任一漏改都會導致 App 顯示版本與 Git 不符
解法：每次 commit 前用腳本自動校驗 (或 AI Agent 手動核對)
```

### 14.7 一鍵啟動腳本編碼限制

```
規則：所有 .bat / .cmd / .sh 檔案嚴禁包含任何中文字元
原因：Windows CMD / CP950 vs UTF-8 字碼頁衝突
```

### 14.8 Metal 在模擬器上不可用

```
問題：MTKView 在 Simulator 上無法使用 Metal GPU
解法：所有 Metal 相關代碼使用 #if canImport(UIKit) 條件編譯
     模擬器顯示替代提示文字
```

---

## 附錄 A：顏色速查表

| 用途 | RGB 值 | Hex |
|------|--------|-----|
| 主強調色 (黃) | `(0.98, 0.82, 0.35)` | `#FAD159` |
| 主操作色 (綠) | `(0.22, 0.85, 0.45)` | `#38D973` |
| 深綠 (OCR按鈕) | `(0.22, 0.72, 0.62)` | `#38B89E` |
| 橙色 (Ultra漸層起) | `(0.98, 0.65, 0.22)` | `#FAA638` |
| 橙紅 (Ultra漸層終) | `(0.95, 0.42, 0.21)` | `#F26B35` |
| 錯誤紅 | `(0.75, 0.2, 0.2)` | `#BF3333` |
| 相機背景 | 純黑 | `#000000` |
| 文件展示底 | `white: 0.96` | `#F5F5F5` |

---

## 附錄 B：SF Symbols 對照表

| 功能 | SF Symbol |
|------|-----------|
| 快門閃爍 | `camera.viewfinder` |
| 閃光燈開 | `bolt.fill` |
| 閃光燈關 | `bolt` |
| 定時器 | `timer` |
| 自動掃描 (開) | `checkmark.circle.fill` |
| 自動掃描 (關) | `camera.metering.matrix` |
| 設定 | `gearshape` |
| 分享/匯出 | `square.and.arrow.up` |
| 相簿 | `photo` |
| 資料夾 | `folder` |
| 裁切 | `crop` |
| 濾鏡 | `slider.horizontal.3` |
| AI 修復 | `wand.and.stars` |
| 極致全開 | `wand.and.stars.inverse` |
| 曲面展平 | `arrow.left.and.right.square` |
| 消除陰影 | `sun.max.fill` |
| 文字銳化 | `sparkles.rectangle.stack` |
| 手指抹除 | `hand.raised.slash` |
| 清除筆跡 | `pencil.slash` |
| 辨識文字 | `viewfinder` |
| 返回相機 | `chevron.left` |
| 垃圾桶 | `trash` |
| QR Code | `qrcode` |
| 條碼 | `barcode` |
| 文件空態 | `doc.text.magnifyingglass` |
