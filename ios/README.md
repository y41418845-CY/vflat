# vFlat-iOS 專案 (iPhone 書本平整掃描器)

本專案為依照 Android 版 vFlat Scan 逆向工程獲得之 25x25 自由曲面幾何展平數學模型與架構設計，使用 Apple 原生現代技術（SwiftUI + AVFoundation + Metal + Accelerate）完全重新構建的 iOS 應用程式。

## 核心特性
1. **AVFoundation 零延遲相機採集**：支援 4K / 60fps 影像串流與連續自動對焦。
2. **Metal 25x25 網格 GPU 紋理重採樣**：透過自訂 Metal Shaders 與 `CVMetalTextureCache` 實現零拷貝高幀率展平預覽。
3. **CoreMotion 水平傾角監控**：即時感測手機俯拍偏角，提供視訊對齊引導。
4. **Swift 向量微分弧長積分**：原生實現 `DewarpGeometry.calculateOutputSize`，計算書本真實物理展開寬度與輸出解析度。

## 專案結構
```
ios/
├── Package.swift                    # Swift Package Manager 配置
├── Sources/
│   ├── Core/                        # 核心演算法與底層驅動
│   │   ├── Camera/                  # AVCaptureSession 相機採集
│   │   ├── Motion/                  # CMMotionManager 姿態感測
│   │   ├── Dewarp/                  # 25x25 幾何弧長展開運算
│   │   └── Metal/                   # Metal 著色器與即時渲染器
│   ├── UI/                          # 現代 SwiftUI 介面
│   │   ├── Views/                   # 相機主畫面、引導層、控制列
│   │   └── ViewModels/              # 狀態管理協調器
│   └── vFlatApp/                    # 應用程式主進入點
└── Tests/
    └── DewarpTests/                 # 幾何數學單元測試
```

## 開發與執行說明
1. **在 macOS Xcode 中開啟**：
   - 雙擊開啟 `Package.swift` 或在 Xcode 中選擇 `File -> Open` 選取 `ios` 目錄。
   - 選擇目標裝置（iPhone 實體機或 iOS Simulator）並按下 `Cmd + R` 即可執行。
2. **執行單元測試**：
   - 在 Xcode 中按下 `Cmd + U`，即可自動執行 `DewarpGeometryTests` 驗證弧長展開數學運算。
