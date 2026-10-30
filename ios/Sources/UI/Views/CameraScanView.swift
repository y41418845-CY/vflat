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
/// 完整對齊原版 iPhone vFlat UI (圖一、圖二) 並整合 OpenScan 5 大核心功能
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
            ScanGuideOverlay(viewModel: viewModel)
                .ignoresSafeArea()

            // 3. 自動穩定捕捉環狀進度指示器 (對齊 OpenScan 視覺提示)
            if viewModel.isAutoCaptureEnabled && viewModel.autoCaptureProgress > 0.05 {
                VStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 4)
                            .frame(width: 54, height: 54)

                        Circle()
                            .trim(from: 0.0, to: CGFloat(viewModel.autoCaptureProgress))
                            .stroke(Color(red: 0.22, green: 0.85, blue: 0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 54, height: 54)

                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 160)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.autoCaptureProgress)
            }

            // 4. QR Code / 條碼懸浮智慧膠囊通知 (對齊 OSS-DocumentScanner，點擊複製或開啟網址)
            if let barcode = viewModel.detectedBarcode {
                VStack {
                    Button(action: {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = barcode.payloadString
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        if barcode.isURL, let url = URL(string: barcode.payloadString) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: barcode.iconName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(red: 0.98, green: 0.82, blue: 0.35))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(barcode.isURL ? "開啟連結 (點擊開啟/已複製)" : "條碼內容 (點擊已複製)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))

                                Text(barcode.payloadString)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Image(systemName: barcode.isURL ? "arrow.up.right.square" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.98, green: 0.82, blue: 0.35).opacity(0.6), lineWidth: 1.2)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 100)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: barcode.payloadString)

                    Spacer()
                }
            }

            // 5. 頂部工具列與底部控制層
            VStack(spacing: 0) {
                // 頂部主導航列 (資料庫、Upgrade、設定) - 對齊圖一最上方
                HStack(spacing: 12) {
                    // 左：資料庫 / PDF 匯出按鈕
                    Button(action: {
                        viewModel.showingPDFExportSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("匯出 PDF")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
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

                // 次頂部功能列 (閃光燈、定時器、Auto Scan 開關、濾鏡模式) - 對齊圖一
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

                    Button(action: {
                        viewModel.isAutoCaptureEnabled.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isAutoCaptureEnabled ? "checkmark.circle.fill" : "camera.metering.matrix")
                                .font(.system(size: 12))
                                .foregroundColor(viewModel.isAutoCaptureEnabled ? Color(red: 0.22, green: 0.85, blue: 0.45) : .white)
                            Text("AUTO\nSCAN")
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(2)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewModel.isAutoCaptureEnabled ? Color.white.opacity(0.25) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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

            // 5. 原生相機快門閃爍白光視覺回饋 (Shutter Flash Animation)
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
        .sheet(isPresented: $viewModel.showingPDFExportSheet) {
            #if canImport(UIKit)
            PDFExportSheet(images: viewModel.capturedImages, defaultPrefix: viewModel.currentFolder)
            #endif
        }
        .task {
            await viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
}
