import Foundation
import SwiftUI
import CoreVideo
import MetalKit

/// 掃描模式：單頁展平 或 雙頁跨頁掃描
public enum ScanMode: String, CaseIterable {
    case single = "單頁"
    case doublePage = "雙頁"
}

/// 負責統籌相機硬體、Metal 渲染管線與 UI 狀態的主協調器
@MainActor
public final class ScannerViewModel: ObservableObject {
    @Published public var scanMode: ScanMode = .single
    @Published public var isDewarpEnabled: Bool = true
    @Published public var simulatedCurvature: Float = 0.15 // 供 POC 測試用之彎曲強度
    @Published public var capturedPageCount: Int = 0
    @Published public var isAutoCaptureEnabled: Bool = false

    public let cameraManager = CameraManager()
    public let motionSensor = MotionSensor()
    public var metalRenderer: MetalDewarpRenderer?

    public init() {
        setupBindings()
    }

    private func setupBindings() {
        // 相機影格直通 Metal 渲染器
        cameraManager.onFrameCaptured = { [weak self] pixelBuffer in
            guard let self = self else { return }
            self.metalRenderer?.feedFrame(pixelBuffer)
        }
    }

    /// 當 MetalView 建立並掛載渲染器時進行初始化設定
    public func attachRenderer(_ renderer: MetalDewarpRenderer) {
        self.metalRenderer = renderer
        applyCurvatureMesh()
    }

    /// 更新曲面展平之模擬網格
    public func applyCurvatureMesh() {
        if isDewarpEnabled {
            let curved = DewarpGeometry.makeCurvedGrid(curvature: simulatedCurvature)
            metalRenderer?.updateMesh(with: curved)
            metalRenderer?.setDewarpStrength(1.0, mode: 1)
        } else {
            let flat = DewarpGeometry.makeFlatGrid()
            metalRenderer?.updateMesh(with: flat)
            metalRenderer?.setDewarpStrength(0.0, mode: 0)
        }
    }

    /// 切換展平開關
    public func toggleDewarp() {
        isDewarpEnabled.toggle()
        applyCurvatureMesh()
    }

    /// 觸發拍照掃描
    public func triggerCapture() {
        capturedPageCount += (scanMode == .single ? 1 : 2)
        // 觸發觸覺震動回饋
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }

    /// 啟動掃描工作流程
    public func startScanning() async {
        let authorized = await cameraManager.checkPermissions()
        if authorized {
            cameraManager.setupSession()
            cameraManager.startSession()
            motionSensor.startUpdates()
        }
    }

    /// 暫停掃描
    public func stopScanning() {
        cameraManager.stopSession()
        motionSensor.stopUpdates()
    }
}
