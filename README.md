# vFlat 逆向工程與 iOS 原生重構專案 (vFlat-iOS)

![Version](https://img.shields.io/badge/version-v1.5.7-blue.svg)
![Platform](https://img.shields.io/badge/platform-iOS%2016.0%2B-black.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Metal](https://img.shields.io/badge/Metal-60fps-red.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

專為擺脫原廠商業訂閱綁架、高額付費牆、廣告干擾與雲端外洩風險而打造。  
基於現代 Apple 原生技術棧（SwiftUI + AVFoundation + Metal + Vision + PDFKit），達到與原廠旗鼓相當甚至超越的書本拉平與掃描清晰度，且具備 **100% 離線隱私、零廣告、終身完全免費**！

詳細技術交接手冊與底層二進位逆向細節請參閱：[`AGENT_HANDOVER.md`](AGENT_HANDOVER.md)

---

## 核心亮點與特色

### 1. 0.5× 超廣角取景視野（對齊原廠真實距離感）
- **相機三鏡頭切換**：
  - **超廣角相機**（推薦 0.5x，開闊視野，徹底解決近距離對焦模糊與框線亂跳問題）
  - **一般相機**（標準 1x 廣角）
  - **長焦相機**（2x / 3x 光學望遠變焦）
- 支援相機輔助引導格線、拍照前自動對焦、靜音快門與觸控螢幕拍照。

### 2. 真·動態 25×25 自由曲面展平 (Freeform Dewarping)
- 透過 `DynamicDewarpPredictor` 自動分析書籍邊界曲率梯度，結合中縫高斯衰減拋物線與三次樣條表面重構。
- 動態預測 $25 \times 25$ 共 625 個控制點向量，直接驅動 Metal GPU 離屏著色器進行物理弧長微分展開，完美拉直彎曲變形的書頁！

### 3. AI 魔法修復旗艦工具庫
- 🌟 **極致全開 (Ultra Scan)**：一鍵連鎖自動執行【25×25 展平 + 消陰影 + 消手指 + 去模糊文字銳化】全套旗艦流水線！
- ☀️ **手機陰影消除 (Shadow Removal)**：採用 Retinex 反射率重構技術，將由上往下拍時手機投下的黑灰色陰影無痕平滑提亮至純白底色。
- 🔍 **文字清晰去模糊 (Deblur)**：亮度通道分離與雙尺度非銳化遮罩，文字筆畫邊緣超解析加深。
- 🖐️ **邊緣手指抹除 (Finger Removal)**：周邊 12% 邊界 YCbCr 膚色空間檢測，採樣紙張底色進行泊松平滑補全。
- ✍️ **手寫筆跡消除 (Handwriting Removal)**：高動態飽和度過濾，留黑字、消除藍/紅手寫原子筆與彩色筆記。

### 4. 多重格式匯出：儲存成 .jpg 檔與高畫質 PDF
- 🖼️ **儲存成 .jpg 檔**：
  - 單頁一鍵儲存至 iPhone 相簿
  - 實體 `.jpg` 檔案分享（可透過 AirDrop、LINE、Email 傳送）
  - 批次將整份文件全部頁面一次性存為 `.jpg` 至相簿！
- 📄 **專業 PDF 匯出**：
  - 支援 A4 標準、美規 Letter、適應寬度與原圖自適應四種尺寸。
  - 支援自動方向、直向 (Portrait) 與橫向 (Landscape)。
  - 支援彩色與黑白灰階 (Grayscale) 印刷模式。
  - 支援設定 PDF 開啟密碼保護。
  - **可搜尋 PDF (Searchable PDF)**：自動將離線 OCR 辨識字元以透明文字圖層嵌入，可用滑鼠直接反白、複製或搜尋！

### 5. 雙頁中縫分割與 30 天垃圾桶 (最近刪除)
- 📖 **雙頁中縫智慧切割**：取樣中央 42%～58% 垂直光度極小值鎖定書脊中縫，支援由左至右 (LTR) 或由右至左 (RTL) 翻頁排版。
- 🗑️ **30 天垃圾桶 (最近刪除)**：刪除頁面安全移入垃圾桶保留 30 天，提供單頁即時還原、批次全部復原與徹底清空。

---

## 系統需求

- **iOS 裝置**：iPhone（需支援 iOS 16.0 或以上版本）。
- **側載安裝工具**：Windows / macOS 版 [Sideloadly](https://sideloadly.io/)、AltStore、SideStore 或 TrollStore。
- **原始碼編譯環境（選用）**：
  - macOS 15.0+
  - Xcode 16.0+
  - `xcodegen` (`brew install xcodegen`)

---

## 一鍵取得最新 IPA 與安裝指南

### 步驟 1：下載最新 `vFlat.ipa`
本專案已配置一鍵自動下載工具：
- 執行專案根目錄的 `download_ipa.bat`（或在終端機執行 `python download_ipa.py`）。
- 腳本會透過 GitHub API 自動抓取最新成功構建的 Actions Artifacts，並在本地根目錄產生 `vFlat.ipa`。

### 步驟 2：側載安裝至 iPhone
1. **使用 AltStore / SideStore（推薦，每週自動 Wi-Fi 續簽）**：
   - 將 `vFlat.ipa` 傳至手機，直接用 AltStore 開啟即可安裝。
2. **使用 Sideloadly（Windows / Mac）**：
   - 開啟 Sideloadly 並以傳輸線連接 iPhone。
   - 將 `vFlat.ipa` 拖入 Sideloadly 視窗，輸入個人 Apple ID 點擊 **Start** 簽名安裝。
3. **使用 TrollStore（巨魔商店，iOS 14.0~16.6.1 / 17.0）**：
   - 點擊 IPA 直接永久安裝，免越獄且永不過期。

---

## 專案設定選項總覽

進入 App 內的「設定中心」，已全面對齊原廠 4 大項目：

1. **相機與硬體拍攝設定**：超廣角/一般/長焦鏡頭、4K/1080p 解析度、定時器 (2/3/5/7秒)、自動掃描、靜音快門、觸控拍照、輔助格線、自動對焦。
2. **掃描與書籍後處理設定**：雙頁翻頁順序 (LTR/RTL)、自動裁剪、25×25 曲面展開、色彩增強、文字加深、**AI 儲存方式 (覆蓋 vs 另存為新頁)**。
3. **PDF 與檔案匯出設定**：自動備份新掃描至相簿、PDF 預設尺寸/方向/色彩/壓縮品質、密碼加密、可搜尋 PDF 文字層。
4. **系統偏好與頁面管理**：**用...啟動應用 (相機取景 vs 資料庫首頁)**、**垃圾桶 (最近刪除)**。
