import Foundation
import AVFoundation
import CoreVideo

#if canImport(UIKit)
import UIKit
#endif

/// 負責驅動 iPhone 原生相機硬體之影格採集管理器
public final class CameraManager: NSObject, ObservableObject {
    public enum CameraError: Error {
        case deviceUnavailable
        case cannotAddInput
        case cannotAddOutput
        case permissionDenied
    }

    public let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.vflat.ios.camera.session", qos: .userInitiated)
    private let outputQueue = DispatchQueue(label: "com.vflat.ios.camera.videoOutput", qos: .userInteractive)

    /// 每一影格產出時之回呼常數 (傳送 CVPixelBuffer)
    public var onFrameCaptured: ((CVPixelBuffer) -> Void)?

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isAuthorized: Bool = false

    public override init() {
        super.init()
    }

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

    /// 初始化相機採集管線 (預設啟用 4K 或 1080p @ 60fps)
    public func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()

            // 優先設定高畫質相機預設規格
            if self.captureSession.canSetSessionPreset(.hd4K3840x2160) {
                self.captureSession.sessionPreset = .hd4K3840x2160
            } else if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                self.captureSession.sessionPreset = .hd1920x1080
            }

            // 選取廣角主相機
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("[CameraManager] 無法取得後置廣角鏡頭")
                self.captureSession.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }

                // 設定連續自動對焦與自動曝光
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.continuousAutoFocus) {
                    camera.focusMode = .continuousAutoFocus
                }
                if camera.isExposureModeSupported(.continuousAutoExposure) {
                    camera.exposureMode = .continuousAutoExposure
                }
                // 優先啟用平順自動對焦
                if camera.isSmoothAutoFocusSupported {
                    camera.isSmoothAutoFocusEnabled = true
                }
                camera.unlockForConfiguration()
            } catch {
                print("[CameraManager] 建立相機輸入失敗: \(error)")
            }

            // 配置視訊影格輸出
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.outputQueue)

            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            // 設定視訊連線方向為縱向 (Portrait)
            if let connection = self.videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90.0) {
                        connection.videoRotationAngle = 90.0
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = false
                }
            }

            self.captureSession.commitConfiguration()
        }
    }

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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrameCaptured?(pixelBuffer)
    }
}
