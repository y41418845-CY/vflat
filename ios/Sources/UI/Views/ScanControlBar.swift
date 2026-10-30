import SwiftUI

/// 完整 1:1 復刻 iPhone 版 vFlat 底部控制列
/// 包含：頁面模式滑塊 (1頁/2頁/自動)、資料夾選擇按鈕、歷史縮圖卡片、快門鈕、相簿圖示
public struct ScanControlBar: View {
    @ObservedObject var viewModel: ScannerViewModel

    public var onDone: (() -> Void)? = nil

    public init(viewModel: ScannerViewModel, onDone: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onDone = onDone
    }

    /// 快門是否可按下：後處理中或倒數中都不可再觸發
    private var isShutterDisabled: Bool {
        viewModel.isProcessingCapture || viewModel.captureCountdown != nil
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 1. 頁數切換滑塊 (1頁 / 2頁) + AUTO SCAN (無商業限制)
            HStack(spacing: 0) {
                Button(action: { viewModel.scanMode = .single }) {
                    Text("1 頁")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(viewModel.scanMode == .single ? Color(red: 0.08, green: 0.78, blue: 0.44) : .white.opacity(0.6))
                        .frame(minWidth: 64, minHeight: 32)
                        .background(
                            viewModel.scanMode == .single ? Color.white.opacity(0.2) : Color.clear
                        )
                        .clipShape(Capsule())
                }

                Button(action: { viewModel.scanMode = .doublePage }) {
                    Text("2 頁")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(viewModel.scanMode == .doublePage ? Color(red: 0.08, green: 0.78, blue: 0.44) : .white.opacity(0.6))
                        .frame(minWidth: 64, minHeight: 32)
                        .background(
                            viewModel.scanMode == .doublePage ? Color.white.opacity(0.2) : Color.clear
                        )
                        .clipShape(Capsule())
                }

                Button(action: { viewModel.isAutoCaptureEnabled.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isAutoCaptureEnabled ? "bolt.badge.automatic.fill" : "bolt.badge.automatic")
                            .font(.system(size: 13))
                        Text(viewModel.isAutoCaptureEnabled ? "自動 ON" : "自動 OFF")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(viewModel.isAutoCaptureEnabled ? Color(red: 0.08, green: 0.78, blue: 0.44) : .white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(
                        viewModel.isAutoCaptureEnabled ? Color.white.opacity(0.2) : Color.clear
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())

            // 2. 當前資料夾選擇膠囊
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.08, green: 0.78, blue: 0.44))
                Text(viewModel.pageStore.currentFolderName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            .padding(.bottom, 2)

            // 3. 底部主快門列 (左：掃描縮圖、中：雙環快門鍵、右：相簿與完成按鈕)
            HStack(spacing: 0) {
                // 左側：最新一頁縮圖卡片（點擊開啟全功能左右翻頁檢視）
                Button(action: {
                    viewModel.showingDocumentDetail = true
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            .frame(width: 50, height: 64)
                            .background(Color.black.opacity(0.4))

                        if let img = viewModel.lastThumbnail {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 46, height: 60)
                                .clipped()
                                .cornerRadius(6)
                        } else if viewModel.pageCount > 0 {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        // 頁數角標 (原廠綠底白字)
                        if viewModel.pageCount > 0 {
                            Text("\(viewModel.pageCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.08, green: 0.78, blue: 0.44))
                                .clipShape(Capsule())
                                .offset(x: 18, y: 24)
                        }
                    }
                }
                .disabled(viewModel.pageCount == 0)
                .frame(width: 80)

                Spacer()

                // 中間：大圓形白色雙環快門按鈕
                Button(action: {
                    viewModel.triggerCapture()
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(isShutterDisabled ? 0.45 : 1.0), lineWidth: 5)
                            .frame(width: 78, height: 78)

                        Circle()
                            .fill(Color.white.opacity(isShutterDisabled ? 0.45 : 1.0))
                            .frame(width: 64, height: 64)

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

                // 右側：完成 (Done) 按鈕 或 相簿按鈕
                HStack(spacing: 8) {
                    Button(action: {
                        viewModel.showingPhotoPicker = true
                    }) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }

                    if let onDone = onDone {
                        Button(action: onDone) {
                            Text("完成")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(red: 0.08, green: 0.78, blue: 0.44))
                                .cornerRadius(16)
                        }
                    }
                }
                .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
