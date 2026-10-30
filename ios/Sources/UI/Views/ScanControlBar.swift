import SwiftUI

/// 完整 1:1 復刻 iPhone 版 vFlat 底部控制列
/// 包含：頁面模式滑塊 (1頁/2頁/自動)、資料夾選擇按鈕、歷史縮圖卡片、快門鈕、相簿圖示
public struct ScanControlBar: View {
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    /// 快門是否可按下：後處理中或倒數中都不可再觸發
    private var isShutterDisabled: Bool {
        viewModel.isProcessingCapture || viewModel.captureCountdown != nil
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 1. 頁數切換滑塊 (1頁 / 2頁 / 自動)
            HStack(spacing: 0) {
                Button(action: { viewModel.scanMode = .single }) {
                    Text("1 頁")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(viewModel.scanMode == .single ? Color(red: 0.98, green: 0.82, blue: 0.35) : .white.opacity(0.6))
                        .frame(minWidth: 64, minHeight: 32)
                        .background(
                            viewModel.scanMode == .single ? Color.white.opacity(0.18) : Color.clear
                        )
                        .clipShape(Capsule())
                }

                Button(action: { viewModel.scanMode = .doublePage }) {
                    Text("2 頁")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(viewModel.scanMode == .doublePage ? Color(red: 0.98, green: 0.82, blue: 0.35) : .white.opacity(0.6))
                        .frame(minWidth: 64, minHeight: 32)
                        .background(
                            viewModel.scanMode == .doublePage ? Color.white.opacity(0.18) : Color.clear
                        )
                        .clipShape(Capsule())
                }

                Button(action: { viewModel.isAutoCaptureEnabled.toggle() }) {
                    Text("自動")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(viewModel.isAutoCaptureEnabled ? Color(red: 0.98, green: 0.82, blue: 0.35) : .white.opacity(0.6))
                        .frame(minWidth: 64, minHeight: 32)
                        .background(
                            viewModel.isAutoCaptureEnabled ? Color.white.opacity(0.18) : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())

            // 2. 當前資料夾選擇膠囊（點擊可直接改名，PDF 檔名會沿用）
            Button(action: { viewModel.showingSettings = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                    Text(viewModel.currentFolder)
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
            }
            .padding(.bottom, 4)

            // 3. 底部主快門列 (左：掃描縮圖、中：雙環快門鍵、右：相簿按鈕)
            HStack {
                // 左側：最新一頁縮圖（點擊開啟文件檢視頁）
                Button(action: {
                    viewModel.showingDocumentDetail = true
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 48, height: 60)
                            .background(Color.black.opacity(0.3))

                        if let img = viewModel.lastThumbnail {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 56)
                                .clipped()
                                .cornerRadius(4)
                        } else if viewModel.pageCount > 0 {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        // 頁數角標
                        if viewModel.pageCount > 0 {
                            Text("\(viewModel.pageCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(red: 0.98, green: 0.82, blue: 0.35))
                                .clipShape(Capsule())
                                .offset(x: 18, y: 26)
                        }
                    }
                }
                .disabled(viewModel.pageCount == 0)
                .padding(.leading, 32)

                Spacer()

                // 中間：大圓形白色雙環快門按鈕
                Button(action: {
                    viewModel.triggerCapture()
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(isShutterDisabled ? 0.45 : 1.0), lineWidth: 4.5)
                            .frame(width: 76, height: 76)

                        Circle()
                            .fill(Color.white.opacity(isShutterDisabled ? 0.45 : 1.0))
                            .frame(width: 62, height: 62)

                        // 後處理中顯示進度圈，倒數中顯示秒數
                        if viewModel.isProcessingCapture {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else if let countdown = viewModel.captureCountdown {
                            Text("\(countdown)")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                        }
                    }
                }
                .disabled(isShutterDisabled)
                .accessibilityLabel(viewModel.isProcessingCapture ? "影像處理中" : "拍照")

                Spacer()

                // 右側：相簿匯入按鈕
                Button(action: {
                    viewModel.showingPhotoPicker = true
                }) {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                }
                .padding(.trailing, 32)
            }
            .padding(.bottom, 24)
        }
    }
}
