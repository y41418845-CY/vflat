import SwiftUI
import MetalKit

#if canImport(UIKit)
import UIKit

/// 將 MetalKit 的 MTKView 包裝給 SwiftUI 使用之 Representable
public struct MetalDewarpViewRepresentable: UIViewRepresentable {
    public typealias UIViewType = MTKView
    @ObservedObject var viewModel: ScannerViewModel

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        if let renderer = MetalDewarpRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
            viewModel.attachRenderer(renderer)
        }
        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        // 由 MTKView 自行調度繪製
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator {
        var renderer: MetalDewarpRenderer?
    }
}
#endif

/// 主掃描相機畫面 (SwiftUI)
/// 1:1 完美對齊原廠圖一：
/// 1. 上半部 4:3 真實比例相機取景窗 (浮動資料庫、設定、快捷項與 1頁/2頁/自動滑塊)
/// 2. 下半部純黑控制區 (無相機預覽畫面，含資料夾膠囊、最新縮圖卡片、原廠雙環快門鈕、相簿圖示)
public struct CameraScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ScannerViewModel()
    @State private var showingFolderSwitchSheet: Bool = false
    @State private var toastMessage: String? = nil

    public init() {}

    private var isShutterDisabled: Bool {
        viewModel.isProcessingCapture || viewModel.captureCountdown != nil
    }

    public var body: some View {
        ZStack {
            // 底層純黑背板
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 上半部：4:3 比例標準相機取景窗 (嚴格對齊圖一)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = w * 4.0 / 3.0 // 4:3 比例 (高:寬 = 4:3)

                    ZStack(alignment: .bottom) {
                        // (1) Metal 相機預覽畫面 (限制在 4:3 內，不延伸到下半部)
                        #if canImport(UIKit)
                        MetalDewarpViewRepresentable(viewModel: viewModel)
                            .frame(width: w, height: h)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if viewModel.touchToScan {
                                    viewModel.triggerCapture()
                                }
                            }
                        #else
                        Color.black.frame(width: w, height: h)
                        #endif

                        // (2) 綠色文件邊界引導框
                        ScanGuideOverlay(viewModel: viewModel)
                            .frame(width: w, height: h)
                            .allowsHitTesting(false)

                        // (3) 取景窗頂部浮動工具列
                        VStack(spacing: 10) {
                            topNavigationBar
                            topQuickControls
                            Spacer()

                            // (4) 取景窗底緣浮動切換列 (1頁 / 2頁 / 自動)
                            pageModeSelector
                                .padding(.bottom, 12)
                        }
                        .frame(width: w, height: h)

                        // (5) 定時拍照倒數浮層
                        if let countdown = viewModel.captureCountdown {
                            Text("\(countdown)")
                                .font(.system(size: 110, weight: .thin, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.6), radius: 12)
                                .transition(.scale.combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.2), value: countdown)
                                .allowsHitTesting(false)
                                .padding(.bottom, 60)
                        }

                        // (6) 自動掃描進度環
                        if viewModel.isAutoCaptureEnabled && viewModel.autoCaptureProgress > 0.05 {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                                    .frame(width: 50, height: 50)
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(viewModel.autoCaptureProgress))
                                    .stroke(Color(red: 0.22, green: 0.85, blue: 0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.bottom, 70)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: w, height: h)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

                // 2. 下半部：純黑控制區 (原廠圖一 1:1，完全無相機畫面！)
                bottomPureBlackArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }

            // 快門閃爍白光視覺回饋
            if viewModel.isShutterFlashing {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Toast 提示膠囊
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(24)
                        .padding(.bottom, 120)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeInOut(duration: 0.25), value: toastMessage)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showingDocumentDetail) {
            PageSwipeDetailView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showingPhotoPicker) {
            PhotoImportPickerView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingFolderSwitchSheet) {
            MoveFolderSheet(viewModel: viewModel, pageIds: [])
        }
        .task {
            await viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
        .onChange(of: viewModel.showingSettings) { isPresented in
            if isPresented {
                viewModel.stopScanning()
            } else {
                Task {
                    await viewModel.startScanning()
                }
            }
        }
        .onChange(of: viewModel.showingPhotoPicker) { isPresented in
            if isPresented {
                viewModel.stopScanning()
            } else {
                Task {
                    await viewModel.startScanning()
                }
            }
        }
        .onChange(of: viewModel.showingDocumentDetail) { isPresented in
            if isPresented {
                viewModel.stopScanning()
            } else {
                Task {
                    await viewModel.startScanning()
                }
            }
        }
    }

    // MARK: - 頂部導航列 (1:1 對齊圖一：📁 資料庫 | ⚙️)

    private var topNavigationBar: some View {
        HStack {
            // 資料庫返回膠囊
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                    Text("資料庫")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
            }

            Spacer()

            // 👑 Upgrade 尊榮 VIP 特權膠囊 (1:1 對齊原廠圖四)
            Button(action: {
                showToast("👑 VIP 旗艦永久授權已生效，全功能無限暢享！")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.25))
                    Text("Upgrade")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(red: 0.98, green: 0.78, blue: 0.25), lineWidth: 1.5)
                )
            }

            Spacer()

            // 設定齒輪按鈕
            Button(action: { viewModel.showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 46) // 避開動態島/安全區域
    }

    // MARK: - 頂部第二行快捷按鈕列 (閃光燈、定時器、AUTO SCAN、濾鏡)

    private var topQuickControls: some View {
        HStack {
            // 1. 閃光燈
            Button(action: { viewModel.toggleTorch() }) {
                Image(systemName: viewModel.isFlashlightOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 18))
                    .foregroundColor(viewModel.isFlashlightOn ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }

            Spacer()

            // 2. 定時器
            Button(action: { viewModel.cycleCaptureTimer() }) {
                ZStack {
                    Image(systemName: "timer")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                    if viewModel.cameraTimerSeconds > 0 {
                        Text("\(viewModel.cameraTimerSeconds)s")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.98, green: 0.82, blue: 0.35))
                            .offset(y: 13)
                    }
                }
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
            }

            Spacer()

            // 3. AUTO SCAN (1:1 帶金色皇冠)
            Button(action: { viewModel.isAutoCaptureEnabled.toggle() }) {
                VStack(spacing: 2) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.25))
                    Text("AUTO\nSCAN")
                        .font(.system(size: 8, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                        .foregroundColor(.white)
                }
                .frame(width: 44, height: 36)
                .background(viewModel.isAutoCaptureEnabled ? Color.white.opacity(0.25) : Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            // 4. 色彩濾鏡 (1:1 帶右上角紅點提示)
            Button(action: { viewModel.cycleFilterMode() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(Color(red: 0.98, green: 0.82, blue: 0.35))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())

                    // 原廠紅色小圓點
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - 取景窗底緣浮動模式膠囊 (1頁 / 2頁 / 自動)

    private var pageModeSelector: some View {
        HStack(spacing: 16) {
            // 1 頁 (選中狀態)
            Button(action: {
                viewModel.scanMode = .single
            }) {
                Text("1 頁")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(viewModel.scanMode == .single ? Color(red: 0.98, green: 0.85, blue: 0.42) : .white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(viewModel.scanMode == .single ? Color.black.opacity(0.65) : Color.clear)
                    .clipShape(Capsule())
            }

            // 2 頁
            Button(action: {
                viewModel.scanMode = .doublePage
            }) {
                Text("2 頁")
                    .font(.system(size: 17, weight: viewModel.scanMode == .doublePage ? .bold : .medium))
                    .foregroundColor(viewModel.scanMode == .doublePage ? Color(red: 0.98, green: 0.85, blue: 0.42) : .white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(viewModel.scanMode == .doublePage ? Color.black.opacity(0.65) : Color.clear)
                    .clipShape(Capsule())
            }

            // 自動
            Button(action: {
                viewModel.isAutoCaptureEnabled.toggle()
            }) {
                Text("自動")
                    .font(.system(size: 17, weight: viewModel.isAutoCaptureEnabled ? .bold : .medium))
                    .foregroundColor(viewModel.isAutoCaptureEnabled ? Color(red: 0.98, green: 0.85, blue: 0.42) : .white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(viewModel.isAutoCaptureEnabled ? Color.black.opacity(0.65) : Color.clear)
                    .clipShape(Capsule())
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    // MARK: - 下半部純黑控制區 (1:1 對齊圖一：資料夾膠囊 + 縮圖 + 雙環快門 + 相簿)

    private var bottomPureBlackArea: some View {
        VStack(spacing: 0) {
            Spacer()

            // 1. 當前資料夾選擇膠囊 (📁 涓建築 ⌵)
            Button(action: {
                showingFolderSwitchSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 15))
                    Text(viewModel.pageStore.currentFolderName)
                        .font(.system(size: 17, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(white: 0.16))
                .clipShape(Capsule())
            }
            .padding(.bottom, 24)

            // 2. 快門控制列 (左：最新縮圖、中：白色雙環快門、右：相簿)
            HStack(alignment: .center) {
                // 左側：最新掃描頁縮圖卡片
                Button(action: {
                    viewModel.showingDocumentDetail = true
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.2))
                            .frame(width: 48, height: 64)

                        if let thumb = viewModel.lastThumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 64)
                                .clipped()
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                .frame(width: 48, height: 64)
                        }
                    }
                }
                .frame(width: 64)

                Spacer()

                // 中央：原廠經典白色快門雙環大圓鈕
                Button(action: {
                    viewModel.triggerCapture()
                }) {
                    ZStack {
                        // 外圈白環
                        Circle()
                            .stroke(Color.white, lineWidth: 3.5)
                            .frame(width: 76, height: 76)

                        // 內圈純白實心大圓
                        Circle()
                            .fill(Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(isShutterDisabled)
                .opacity(isShutterDisabled ? 0.6 : 1.0)

                Spacer()

                // 右側：相簿圖示按鈕
                Button(action: {
                    viewModel.showingPhotoPicker = true
                }) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                }
                .frame(width: 64)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 40)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }
}
