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
        // 當狀態或尺寸更新時由 MTKView 自行調度
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
/// 完整對齊原版 iPhone vFlat UI (圖一、圖二)
public struct CameraScanView: View {
    @StateObject private var viewModel = ScannerViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            // 底層：黑底背板
            Color.black.ignoresSafeArea()

            // 1. Metal 即時相機渲染視圖 (1:1 原生平坦真實比例)
            #if canImport(UIKit)
            MetalDewarpViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            #else
            Text("Metal 渲染器需在 iOS 實體設備或模擬器環境下運作")
                .foregroundColor(.white)
            #endif

            // 2. 輔助導引層 (自動文件邊界框選、中央「尋找文件」標籤、十字姿態儀)
            // 必須設定 ignoresSafeArea()，使 GeometryReader 取得全螢幕滿版畫布 (393x852)，與底層相機紋理 100% 像素對齊
            ScanGuideOverlay(viewModel: viewModel)
                .ignoresSafeArea()

            // 3. 頂部工具列與底部控制層
            VStack(spacing: 0) {
                // 頂部主導航列 (資料庫、Upgrade、設定) - 對齊圖一最上方
                HStack(spacing: 12) {
                    // 左：資料庫按鈕
                    Button(action: {}) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 14, weight: .semibold))
                            Text("資料庫")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    // 右：設定齒輪按鈕
                    Button(action: {
                        viewModel.showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 44) // 避開安全區域與動態島

                // 次頂部功能列 (閃光燈、定時器、Auto Scan 徽章、濾鏡) - 對齊圖一
                HStack {
                    Button(action: {
                        viewModel.isFlashlightOn.toggle()
                    }) {
                        Image(systemName: viewModel.isFlashlightOn ? "bolt.fill" : "bolt")
                            .font(.system(size: 18))
                            .foregroundColor(viewModel.isFlashlightOn ? .yellow : .white)
                    }

                    Spacer()

                    Button(action: {}) {
                        Image(systemName: "timer")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text("AUTO\nSCAN")
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(2)
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    Button(action: {}) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "rays")
                                .font(.system(size: 20))
                                .foregroundColor(Color(red: 0.98, green: 0.82, blue: 0.35))

                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)

                Spacer()

                // 底部控制列
                ScanControlBar(viewModel: viewModel)
            }

            // 4. 原生相機快門閃爍白光視覺回饋 (Shutter Flash Animation)
            if viewModel.isShutterFlashing {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showingDocumentDetail) {
            DocumentDetailView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showingPhotoPicker) {
            PhotoImportPickerView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $viewModel.showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .task {
            await viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
}
