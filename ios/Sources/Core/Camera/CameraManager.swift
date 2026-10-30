import SwiftUI
import AVFoundation
import Combine

enum CameraLens: String, CaseIterable, Identifiable {
    case ultraWide = "超廣角 0.5x (推薦)"
    case wide      = "廣角 1x"
    case telephoto = "長焦 2x~3x"
    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum ScanResolution: String, CaseIterable, Identifiable {
    case ultraHD4K  = "4K 超高清"
    case fullHD1080 = "1080p 高清"
    case hd720      = "720p 標準"
    var id: String { rawValue }
    var displayName: String { rawValue }
}

import Foundation

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var isTorchAvailable: Bool = false
    @Published var isTorchOn: Bool = false
    @Published var activeFrameRate: Double = 0

    private let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var currentInput: AVCaptureDeviceInput?
    private var latestBuffer: CVPixelBuffer?
    private let bufferLock = NSLock()
    private var frameCallback: ((CVPixelBuffer, CMTime) -> Void)?

    var captureSession: AVCaptureSession { session }

    func setFrameCallback(_ cb: @escaping (CVPixelBuffer, CMTime) -> Void) {
        frameCallback = cb
    }

    func setupSession(resolution: ScanResolution, lens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = self.preset(for: resolution)
            // remove existing input
            if let input = self.currentInput {
                self.session.removeInput(input)
                self.currentInput = nil
            }
            let device = self.device(for: lens)
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
            } catch {
                print("Camera input error: \(error)")
            }
            // video output
            if self.session.outputs.isEmpty {
                self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frames"))
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
            }
            self.session.commitConfiguration()
            self.updateTorchAvailability()
        }
    }

    private func preset(for resolution: ScanResolution) -> AVCaptureSession.Preset {
        switch resolution {
        case .ultraHD4K: return .hd4K3840x2160
        case .fullHD1080: return .hd1920x1080
        case .hd720: return .hd1280x720
        }
    }

    private func device(for lens: CameraLens) -> AVCaptureDevice {
        let preferred: AVCaptureDevice.DeviceType
        switch lens {
        case .ultraWide: preferred = .builtInUltraWideCamera
        case .wide: preferred = .builtInWideAngleCamera
        case .telephoto: preferred = .builtInTelephotoCamera
        }
        if let d = AVCaptureDevice.default(preferred, for: .video, position: .back) {
            return d
        }
        // fallback
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.activeFrameRate = Double(self.currentInput?.device.activeVideoMinFrameDuration.timescale ?? 30)
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func latestPixelBufferSnapshot() -> CVPixelBuffer? {
        bufferLock.lock(); defer { bufferLock.unlock() }
        return latestBuffer
    }

    func setTorch(on: Bool) {
        guard let device = currentInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.isTorchOn = on }
        } catch {}
    }

    func focusAndExposeCenterIfNeeded() {
        guard let device = currentInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {}
    }

    func setResolution(_ resolution: ScanResolution) {
        setupSession(resolution: resolution, lens: currentLens())
    }

    func setLens(_ lens: CameraLens) {
        setupSession(resolution: currentResolution(), lens: lens)
    }

    private func currentLens() -> CameraLens {
        // best-effort from defaults
        let raw = UserDefaults.standard.string(forKey: "vflat_camera_lens") ?? CameraLens.ultraWide.rawValue
        return CameraLens(rawValue: raw) ?? .ultraWide
    }

    private func currentResolution() -> ScanResolution {
        let raw = UserDefaults.standard.string(forKey: "vflat_scan_resolution") ?? ScanResolution.ultraHD4K.rawValue
        return ScanResolution(rawValue: raw) ?? .ultraHD4K
    }

    private func updateTorchAvailability() {
        let avail = currentInput?.device.hasTorch ?? false
        DispatchQueue.main.async { self.isTorchAvailable = avail }
    }

    static func makeImage(from buffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestBuffer = buffer
        bufferLock.unlock()
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameCallback?(buffer, time)
    }
}
