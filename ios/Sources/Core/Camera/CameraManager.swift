import Foundation
import AVFoundation
import CoreVideo
import CoreImage

#if canImport(UIKit)
import UIKit
#endif

/// 掃描解析度選項 (對應 vFlat 設定頁之畫質切換)
public enum ScanResolution: String, CaseIterable, Identifiable, Sendable {
    case ultraHD4K = "4K"
    case fullHD1080p = "1080p"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ultraHD4K: return "超高畫質 4K (2160p)"
        case .fullHD1080p: return "標準高畫質 (1080p)"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .ultraHD4K: return .hd4K3840x2160
        case .fullHD1080p: return .hd1920x1080
        }
    }
}

/// 負責驅動 iPhone 原生相機硬體之影格採集管理器
public final class CameraManager: NSObject, ObservableObject {
    public enum CameraError: Error {
        case deviceUnavailable
        case cannotAddInput
        case cannotAddOutput
        case permissionDenied
    }

    /// 目標預覽／串流幀率 (若裝置與格式支援則啟用)
    public static let targetFrameRate: Double = 60.0

    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.vflat.ios.camera.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "com.vflat.ios.camera.videoOutput", qos: .userInteractive)

    /// 每一影格產出時之回呼常數 (傳送 CVPixelBuffer)
    public var onFrameCaptured: ((CVPixelBuffer) -> Void)?

    private let bufferLock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    /// CIContext 為執行緒安全，可同時供相機輸出佇列與拍照後製使用
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var currentResolution: ScanResolution = .ultraHD4K

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isAuthorized: Bool = false
    /// 實際生效之串流幀率 (0 表示尚未量測)
    @Published public private(set) var activeFrameRate: Double = 0
    @Published public private(set) var isTorchAvailable: Bool = false
    @Published public private(set) var isTorchOn: Bool = false
    @Published public private(set) var resolution: ScanResolution = .ultraHD4K

    public override init() {
        super.init()
    }

    // MARK: - 權限

    /// 檢查並請求相機使用權限
    public func checkPermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await MainActor.run { self.isAuthorized = true }
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { self.isAuthorized = granted }
            return granted
        default:
            await MainActor.run { self.isAuthorized = false }
            return false
        }
    }

    // MARK: - 工作階段設定

    /// 初始化相機採集管線 (預設 4K，支援時自動啟用 60fps)
    public func setupSession(resolution: ScanResolution = .ultraHD4K) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.configureSession(resolution: resolution, restartIfNeeded: false)
        }
    }

    /// 切換掃描解析度 (重設工作階段設定，不中斷既有預覽之外的狀態)
    public func setResolution(_ newResolution: ScanResolution, completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard newResolution != self.currentResolution else {
                DispatchQueue.main.async { completion?() }
                return
            }
            self.configureSession(resolution: newResolution, restartIfNeeded: true)
            DispatchQueue.main.async { completion?() }
        }
    }

    /// 於 sessionQueue 上執行的實際設定流程
    private func configureSession(resolution: ScanResolution, restartIfNeeded: Bool) {
        let wasRunning = captureSession.isRunning
        if wasRunning && restartIfNeeded {
            captureSession.stopRunning()
        }

        captureSession.beginConfiguration()

        // 1. 設定工作階段預設規格 (嚴禁使用 .photo，會導致 videoOutput 掉到 10~15fps)
        if captureSession.canSetSessionPreset(resolution.sessionPreset) {
            captureSession.sessionPreset = resolution.sessionPreset
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }
        self.currentResolution = resolution
        DispatchQueue.main.async { self.resolution = resolution }

        // 2. 選取廣角主相機
        if videoInput == nil {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("[CameraManager] 無法取得後置廣角鏡頭")
                captureSession.commitConfiguration()
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                    self.videoInput = input
                    self.videoDevice = camera
                }
            } catch {
                print("[CameraManager] 建立相機輸入失敗: \(error)")
            }
        }

        // 3. 相機硬體參數 (自動對焦／曝光／幀率)
        if let camera = videoDevice {
            do {
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.continuousAutoFocus) {
                    camera.focusMode = .continuousAutoFocus
                }
                if camera.isExposureModeSupported(.continuousAutoExposure) {
                    camera.exposureMode = .continuousAutoExposure
                }
                if camera.isSmoothAutoFocusSupported {
                    camera.isSmoothAutoFocusEnabled = true
                }
                // 依實際 activeFormat 能力啟用 60fps，避免設定失敗拋出例外
                if let range = camera.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= CameraManager.targetFrameRate }) {
                    let fps = min(CameraManager.targetFrameRate, range.maxFrameRate)
                    let duration = CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
                    camera.activeVideoMinFrameDuration = duration
                    camera.activeVideoMaxFrameDuration = duration
                    DispatchQueue.main.async { self.activeFrameRate = fps }
                } else {
                    let fallback = camera.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
                    DispatchQueue.main.async { self.activeFrameRate = fallback }
                }
                camera.unlockForConfiguration()
            } catch {
                print("[CameraManager] 相機硬體設定失敗: \(error)")
            }
            let torchAvailable = camera.hasTorch && camera.isTorchModeSupported(.on)
            DispatchQueue.main.async { self.isTorchAvailable = torchAvailable }
        }

        // 4. 配置視訊影格輸出
        if !captureSession.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
        }

        // 5. 影像方向固定為縱向
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90.0) {
                    connection.videoRotationAngle = 90.0
                }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }

        captureSession.commitConfiguration()

        if wasRunning && restartIfNeeded {
            captureSession.startRunning()
        }
    }

    // MARK: - 串流控制

    /// 啟動相機串流
    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.captureSession.isRunning
            }
        }
    }

    /// 停止相機串流
    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    // MARK: - 硬體控制 (手電筒／對焦)

    /// 開啟或關閉補光燈
    public func setTorch(on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let camera = self.videoDevice, camera.hasTorch else { return }
            guard camera.isTorchModeSupported(on ? .on : .off) else { return }
            do {
                try camera.lockForConfiguration()
                if on {
                    try? camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    camera.torchMode = .off
                }
                camera.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isTorchOn = on
                    self.isTorchAvailable = true
                }
            } catch {
                print("[CameraManager] 手電筒切換失敗: \(error)")
                DispatchQueue.main.async { self.isTorchOn = false }
            }
        }
    }

    /// 掃描前主動對焦至畫面中央 (對齊「掃描前自動對焦」設定)
    public func focusAndExposeCenterIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self = self, let camera = self.videoDevice else { return }
            do {
                try camera.lockForConfiguration()
                let center = CGPoint(x: 0.5, y: 0.5)
                if camera.isFocusPointOfInterestSupported {
                    camera.focusPointOfInterest = center
                    camera.focusMode = .autoFocus
                }
                if camera.isExposurePointOfInterestSupported {
                    camera.exposurePointOfInterest = center
                    camera.exposureMode = .autoExpose
                }
                camera.unlockForConfiguration()
            } catch {
                print("[CameraManager] 對焦設定失敗: \(error)")
            }
        }
    }

    // MARK: - 影格取得

    /// 取得最新影格之強參照快照 (供拍照後製使用，避免與串流回收池競爭)
    public func latestPixelBufferSnapshot() -> CVPixelBuffer? {
        bufferLock.lock()
        let buffer = latestPixelBuffer
        bufferLock.unlock()
        return buffer
    }

    /// 將 CVPixelBuffer 轉為 UIImage (方向已由連線旋轉為正向)
    public static func makeImage(from pixelBuffer: CVPixelBuffer, context: CIContext? = nil) -> UIImage? {
        #if canImport(UIKit)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = context ?? CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        #else
        return nil
        #endif
    }

    /// 零延遲從最新視訊串流影格擷取高品質靜態照片
    public func captureCurrentFrame() -> UIImage? {
        guard let buffer = latestPixelBufferSnapshot() else { return nil }
        return CameraManager.makeImage(from: buffer, context: ciContext)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestPixelBuffer = pixelBuffer
        bufferLock.unlock()
        onFrameCaptured?(pixelBuffer)
    }
}
