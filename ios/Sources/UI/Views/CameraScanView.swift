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
public struct CameraScanView: View {
    @StateObject private var viewModel = ScannerViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            // 底層：黑底背板
            Color.black.ignoresSafeArea()

            // 1. Metal 即時相機與展平渲染視圖
            #if canImport(UIKit)
            MetalDewarpViewRepresentable(viewModel: viewModel)
                .ignoresSafeArea()
            #else
            Text("Metal 渲染器需在 iOS 實體設備或模擬器環境下運作")
                .foregroundColor(.white)
            #endif

            // 2. 輔助導引層 (中縫線、水平儀、對焦提示)
            ScanGuideOverlay(viewModel: viewModel)

            // 3. 頂部工具列 (閃光燈、設定)
            VStack {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.blue)
                    Text("vFlat-iOS")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // 4. 底部控制列
                ScanControlBar(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
}
