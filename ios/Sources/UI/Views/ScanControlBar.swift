import SwiftUI

/// 相機底部掃描控制列 (單雙頁切換、快門鍵、展平開關)
public struct ScanControlBar: View {
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // 上層：模式選擇與展平切換
            HStack {
                // 單頁 / 雙頁切換
                Picker("掃描模式", selection: $viewModel.scanMode) {
                    ForEach(ScanMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                // 即時展平開關按鈕
                Button(action: {
                    viewModel.toggleDewarp()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.isDewarpEnabled ? "sparkles" : "camera.viewfinder")
                        Text(viewModel.isDewarpEnabled ? "展平: 開啟" : "展平: 原圖")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(viewModel.isDewarpEnabled ? Color.blue.opacity(0.8) : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)

            // 下層：快門鍵與頁數預覽
            HStack(spacing: 36) {
                // 已掃描頁數檢視按鈕
                ZStack(alignment: .topTrailing) {
                    Button(action: {}) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    if viewModel.capturedPageCount > 0 {
                        Text("\(viewModel.capturedPageCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }

                // 快門按鈕 (Shutter Button)
                Button(action: {
                    viewModel.triggerCapture()
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 76, height: 76)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                    }
                }

                // 自動掃描開關
                Button(action: {
                    viewModel.isAutoCaptureEnabled.toggle()
                }) {
                    Image(systemName: viewModel.isAutoCaptureEnabled ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 24))
                        .foregroundColor(viewModel.isAutoCaptureEnabled ? .yellow : .white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.bottom, 20)
        }
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
