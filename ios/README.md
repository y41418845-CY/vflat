# vFlat-iOS 專案 (iPhone 書本平整掃描器)

本專案為依照 Android 版 vFlat Scan 逆向工程獲得之 25x25 自由曲面幾何展平數學模型與架構設計，使用 Apple 原生現代技術（SwiftUI + AVFoundation + Metal + Accelerate + Vision）完全重新構建的 iOS 應用程式。

## 核心特性
1. **AVFoundation 零延遲相機採集**：支援 4K / 60fps 影像串流、連續自動對焦、補光燈與實際幀率量測。
2. **Metal 25x25 網格 GPU 紋理重採樣**：透過自訂 Metal Shaders 與 `CVMetalTextureCache` 實現零拷貝高幀率展平預覽；`MetalLibraryProvider` 會在 `default.metallib` 缺失時以執行期原始碼編譯後備。
3. **CoreMotion 水平傾角監控**：即時感測手機俯拍偏角，提供視訊對齊引導。
4. **Swift 向量微分弧長積分**：原生實現 `DewarpGeometry.calculateOutputSize`，計算書本真實物理展開寬度與輸出解析度。
5. **頁面落盤儲存**：`ScanPageStore` 以 JPEG + `index.json` 管理掃描頁，記憶體只保留縮圖，避免大量頁面造成 OOM。
6. **繁中離線 OCR**：`OCRService` 使用 `VNRecognizeTextRequest`（zh-Hant / zh-Hans / en-US）。

## 專案結構
```
ios/
├── Package.swift                    # Swift Package Manager 配置（本機除錯用）
├── Sources/
│   ├── Core/                        # 核心演算法與底層驅動
│   │   ├── Camera/                  # AVCaptureSession 相機採集
│   │   ├── Motion/                  # CMMotionManager 姿態感測
│   │   ├── Dewarp/                  # 25x25 幾何弧長展開、邊界偵測、透視校正
│   │   ├── Metal/                   # Metal 著色器、即時與離屏渲染器
│   │   ├── Storage/                 # ScanPageStore（JPEG 落盤、索引、縮圖快取）
│   │   ├── OCR/                     # Vision 文字辨識
│   │   └── Export/                  # PDF 匯出與檔名規則
│   ├── UI/                          # 現代 SwiftUI 介面
│   │   ├── Views/                   # 相機主畫面、引導層、控制列、設定、匯入、匯出
│   │   └── ViewModels/              # 狀態管理協調器
│   └── vFlatApp/                    # 應用程式主進入點
└── Tests/
    └── DewarpTests/                 # 幾何、反混淆、條碼、自動快門單元測試
```

## 開發與執行說明
1. **建議路徑：XcodeGen（與 CI 完全一致）**
   ```bash
   brew install xcodegen
   xcodegen generate          # 於專案根目錄執行
   open vFlat.xcodeproj
   ```
   選擇目標裝置（iPhone 實體機或 iOS Simulator）後按 `Cmd + R`。
2. **替代路徑：Swift Package Manager（僅供快速除錯）**
   - 在 Xcode 中 `File -> Open` 選取 `ios` 目錄即可開啟 `Package.swift`。
3. **執行單元測試**
   ```bash
   xcodebuild test -project vFlat.xcodeproj -scheme vFlat \
     -destination "platform=iOS Simulator,name=iPhone 16" \
     CODE_SIGNING_ALLOWED=NO
   ```
   或在 Xcode 按 `Cmd + U`。

## 版本與權限
- 版本號：`1.2.1`（Build `121`），由 `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 注入。
- Info.plist 需包含：`NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription`、`NSPhotoLibraryAddUsageDescription`。
  **請以 `project.yml` 為唯一來源**，`xcodegen generate` 會覆寫 `ios/Info.plist`。
