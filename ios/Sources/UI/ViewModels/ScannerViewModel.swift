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
    @Published public var isDewarpEnabled: Bool = false // 預設關閉人為模擬彎曲，保持物品 1:1 真實比例不變形
    @Published public var detectedDocument: DetectedDocument? = nil
    @Published public var isDocumentDetected: Bool = false
    @Published public var detectedBarcode: DetectedBarcode? = nil // 即時 QR Code / 條碼偵測結果
    @Published public var capturedPageCount: Int = 182 // 對齊圖一計數狀態
    @Published public var isAutoCaptureEnabled: Bool = false
    @Published public var autoCaptureProgress: Double = 0.0 // 自動穩定捕捉進度 0.0 ~ 1.0
    @Published public var currentFolder: String = "涓建築"
    @Published public var isFlashlightOn: Bool = false

    // 視圖跳轉控制
    @Published public var showingDocumentDetail: Bool = false
    @Published public var showingPhotoPicker: Bool = false
    @Published public var showingSettings: Bool = false
    @Published public var showingPDFExportSheet: Bool = false

    // 濾鏡狀態
    #if canImport(UIKit)
    @Published public var selectedFilterMode: DocumentFilterMode = .auto
    @Published public var lastRawCapturedImage: UIImage? = nil
    @Published public var lastCapturedImage: UIImage? = nil
    @Published public var capturedImages: [UIImage] = []
    #endif

    // REA 逆向成果配置項 (Settings Preferences)
    @Published public var useScanGuide: Bool = true
    @Published public var autofocusBeforeScan: Bool = true
    @Published public var touchToScan: Bool = false
    @Published public var disableShutterSound: Bool = false
    @Published public var hapticFeedback: Bool = true
    @Published public var cameraTimerSeconds: Int = 0
    @Published public var twoPagesOrderLTR: Bool = true // true: 左到右, false: 右到左
    @Published public var presetAutoCrop: Bool = true
    @Published public var presetCurveCorrection: Bool = true
    @Published public var presetColorEnhance: Bool = true
    @Published public var presetFingerRemoval: Bool = false
    @Published public var presetTextDarken: Bool = true
    @Published public var autoSaveToGallery: Bool = false
    @Published public var scanResolution: String = "4K"

    @Published public var isShutterFlashing: Bool = false

    public let cameraManager = CameraManager()
    public let motionSensor = MotionSensor()
    public let documentDetector = DocumentDetector()
    public let autoCaptureDetector = AutoCaptureDetector()
    public var metalRenderer: MetalDewarpRenderer?

    public init() {
        setupDetector()
    }

    private var lastAutoCaptureTime: TimeInterval = 0

    private func setupDetector() {
        documentDetector.onDocumentDetected = { [weak self] doc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.detectedDocument = doc
                self.isDocumentDetected = (doc != nil)

                // 對齊 OpenScan 之 Auto-Capture 自動穩定快門偵測
                if self.isAutoCaptureEnabled {
                    let now = Date().timeIntervalSince1970
                    let shouldTrigger = self.autoCaptureDetector.processFrame(document: doc, at: now)
                    self.autoCaptureProgress = self.autoCaptureDetector.stabilityProgress

                    // 避免連續短時間連擊 (至少間隔 1.8 秒)
                    if shouldTrigger && (now - self.lastAutoCaptureTime) > 1.8 {
                        self.lastAutoCaptureTime = now
                        self.triggerCapture()
                    }
                } else {
                    self.autoCaptureDetector.reset()
                    self.autoCaptureProgress = 0.0
                }
            }
        }

        // 對齊 OSS-DocumentScanner 之 QR Code / 條碼自動解析回呼
        documentDetector.onBarcodeDetected = { [weak self] barcode in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.detectedBarcode = barcode
            }
        }
    }

    /// 當 MetalView 建立並掛載渲染器時進行初始化設定
    public func attachRenderer(_ renderer: MetalDewarpRenderer) {
        self.metalRenderer = renderer
        applyCurvatureMesh()

        // 相機高頻影格（60fps）串接 Metal 渲染器與 Vision 文件偵測
        cameraManager.onFrameCaptured = { [weak self, weak renderer] pixelBuffer in
            renderer?.feedFrame(pixelBuffer)
            self?.documentDetector.processFrame(pixelBuffer)
        }
    }

    /// 更新曲面展平網格 (預設平坦 1:1，確保真實物品畫面平整完全不變形)
    public func applyCurvatureMesh() {
        let flat = DewarpGeometry.makeFlatGrid()
        metalRenderer?.updateMesh(with: flat)
        metalRenderer?.setDewarpStrength(0.0, mode: 0)
    }

    /// 切換展平開關
    public func toggleDewarp() {
        isDewarpEnabled.toggle()
        applyCurvatureMesh()
    }

    /// 觸發拍照掃描 (具備原生相機快門閃爍動畫、真實影格擷取、自動透視校正、縮圖更新與相簿儲存)
    public func triggerCapture() {
        #if canImport(UIKit)
        if hapticFeedback {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }

        // 1. 觸發原生快門全螢幕白光閃爍視覺回饋
        withAnimation(.easeOut(duration: 0.08)) {
            self.isShutterFlashing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.12)) {
                self.isShutterFlashing = false
            }
        }

        // 2. 從相機串流零延遲擷取當前最新畫面，並自動套用 vFlat 校正管線 (透視拉正 + 6大文件濾鏡增強)
        if let rawPhoto = cameraManager.captureCurrentFrame() {
            self.lastRawCapturedImage = rawPhoto

            let rectifiedPhoto = DocumentRectifier.shared.autoProcessCapture(
                image: rawPhoto,
                document: self.detectedDocument,
                autoCrop: self.presetAutoCrop,
                filterMode: self.selectedFilterMode
            )

            self.lastCapturedImage = rectifiedPhoto
            self.capturedImages.append(rectifiedPhoto)

            if autoSaveToGallery {
                UIImageWriteToSavedPhotosAlbum(rectifiedPhoto, nil, nil, nil)
            }
        }
        #endif

        capturedPageCount += (scanMode == .single ? 1 : 2)
    }

    #if canImport(UIKit)
    /// 手動更換文件濾鏡模式
    public func updateFilterMode(_ mode: DocumentFilterMode) {
        self.selectedFilterMode = mode
        if let raw = lastRawCapturedImage {
            let updated = DocumentRectifier.shared.autoProcessCapture(
                image: raw,
                document: self.detectedDocument,
                autoCrop: self.presetAutoCrop,
                filterMode: mode
            )
            self.lastCapturedImage = updated
        }
    }
    #endif

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
