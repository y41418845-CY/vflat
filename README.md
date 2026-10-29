# vFlat 逆向工程與架構分析專案 (REA)

- **版本**：v0.3.0
- **目標應用**：vFlat Scan - PDF Scanner (`com.voyagerx.scanner`)
- **分析樣本**：`vFlat Scan.xapk` (v1.16.8.260930.6c4b190386)
- **衍生原生 iOS 實作**：`ios/` (vFlat-iOS iPhone 專案)

## 專案說明
本專案存放針對 vFlat Android 版本的逆向工程（REA）分析記錄、原生 C++ 函式庫分析、AI 模型清單與 25x25 自由曲面展平演算法逆向成果，並包含使用 Swift + Metal + AVFoundation 重新構建之全新 iPhone 專案 (`ios/`)。

## 分析成果重點
1. **核心函式庫**：
   - `libnative-scan.so`：包含 `freeform::model`（反混淆、弧長積分輸出尺寸運算）與 `freeform::remap`（UV 緩衝區）。
   - `libnative-crop.so` / `libnative-cleanup.so` / `libnative-edgecut.so`。
2. **AI 模型資產 (`assets/models/`)**：
   - `freeform_v3_2.dat`：25x25 控制點（625 個節點）曲面重建 TFLite 模型。
   - `finger_mask_v1_1.dat` / `inpainter_v1_0_0.dat`：手指偵測與影像消除修復。
   - `deblur_v1.1.dat`：手震文字去模糊神經網路。
3. **iPhone 原生專案 (`ios/`)**：
   - `Core/Camera`：AVCaptureSession 4K/60fps 採集。
   - `Core/Motion`：CoreMotion 陀螺儀水平感測。
   - `Core/Dewarp`：Swift 25x25 幾何弧長積分引擎。
   - `Core/Metal`：Metal MSL 著色器即時紋理拉平渲染器。
   - `UI`：現代 SwiftUI 掃描視圖、中縫引導線與底部控制列。
