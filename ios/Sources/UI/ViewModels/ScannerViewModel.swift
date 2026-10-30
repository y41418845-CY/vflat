import Foundation
import SwiftUI
import UIKit
import Combine
import AVFoundation
import Photos

enum ScanMode { case single, doublePage }

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var scanMode: ScanMode = .single
    @Published var selectedFilterMode: DocumentFilterMode = .auto
    @Published var isAutoCaptureEnabled: Bool = false
    @Published var autoCaptureProgress: Double = 0
    @Published var detectedDocument: DetectedDocument?
    @Published var detectedBarcode: DetectedBarcode?
    @Published var isProcessingCapture: Bool = false
    @Published var captureCountdown: Int?
    @Published var lastThumbnail: UIImage?
    @Published var lastPreviewImage: UIImage?
    @Published var lastRawPageImage: UIImage?
    @Published var lastOCRText: String?
    @Published var isRecognizingText: Bool = false
    @Published var errorMessage: String?

    let cameraManager = CameraManager()
    let motionSensor = MotionSensor()
    let documentDetector = DocumentDetector()
    let autoCaptureDetector = AutoCaptureDetector()
    let pageStore: ScanPageStore
    let ocrService = OCRService()
    let barcodeScanner = BarcodeScannerService()

    private var cancellables = Set<AnyCancellable>()
    private var frameTimer: Timer?

    init() {
        pageStore = ScanPageStore()
        // forward nested objectWillChange
        cameraManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        motionSensor.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        pageStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        // settings
        isAutoCaptureEnabled = UserDefaults.standard.bool(forKey: "vflat_auto_capture")

        cameraManager.setFrameCallback { [weak self] buffer, time in
            Task { @MainActor in self?.handleFrame(buffer: buffer, time: time) }
        }
    }

    func start() {
        let resRaw = UserDefaults.standard.string(forKey: "vflat_scan_resolution") ?? ScanResolution.ultraHD4K.rawValue
        let lensRaw = UserDefaults.standard.string(forKey: "vflat_camera_lens") ?? CameraLens.ultraWide.rawValue
        let res = ScanResolution(rawValue: resRaw) ?? .ultraHD4K
        let lens = CameraLens(rawValue: lensRaw) ?? .ultraWide
        cameraManager.setupSession(resolution: res, lens: lens)
        cameraManager.startSession()
        motionSensor.start()
    }

    func stop() {
        cameraManager.stopSession()
        motionSensor.stop()
    }

    private func handleFrame(buffer: CVPixelBuffer, time: CMTime) {
        if let doc = documentDetector.detect(in: buffer) {
            detectedDocument = doc
        }
        if let bc = barcodeScanner.detect(in: buffer) {
            detectedBarcode = bc
        } else {
            // keep last? clear if none
        }
        if isAutoCaptureEnabled {
            let triggered = autoCaptureDetector.processFrame(document: detectedDocument, at: CACurrentMediaTime())
            autoCaptureProgress = autoCaptureDetector.stabilityProgress
            if triggered {
                Task { await capture() }
            }
        }
    }

    func capture() async {
        guard !isProcessingCapture else { return }
        isProcessingCapture = true
        defer { isProcessingCapture = false }
        // countdown timer
        let timerSec = UserDefaults.standard.integer(forKey: "vflat_camera_timer")
        if timerSec > 0 {
            for i in stride(from: timerSec, through: 1, by: -1) {
                captureCountdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            captureCountdown = nil
        }
        guard let buffer = cameraManager.latestPixelBufferSnapshot() else { return }
        guard let image = CameraManager.makeImage(from: buffer) else { return }
        lastRawPageImage = image
        // document detect once
        let doc = DocumentDetector.detectOnce(in: buffer)
        let autoCrop = UserDefaults.standard.bool(forKey: "vflat_preset_auto_crop") // default true? handle default
        // default true if not set
        let autoCropVal = UserDefaults.standard.object(forKey: "vflat_preset_auto_crop") == nil ? true : UserDefaults.standard.bool(forKey: "vflat_preset_auto_crop")
        let rectifier = DocumentRectifier()
        var corrected = rectifier.geometryCorrected(image: image, document: doc, autoCrop: autoCropVal)
        let enhance = UserDefaults.standard.object(forKey: "vflat_preset_color_enhance") == nil ? true : UserDefaults.standard.bool(forKey: "vflat_preset_color_enhance")
        let darken = UserDefaults.standard.object(forKey: "vflat_preset_text_darken") == nil ? true : UserDefaults.standard.bool(forKey: "vflat_preset_text_darken")
        corrected = rectifier.applyFilter(selectedFilterMode, to: corrected, enhanceColor: enhance, darkenText: darken)
        lastPreviewImage = corrected
        let thumb = corrected.resized(to: CGSize(width: 48, height: 60))
        lastThumbnail = thumb
        // store
        let page = await pageStore.append(processed: corrected, raw: image, filterMode: selectedFilterMode, document: doc)
        if UserDefaults.standard.bool(forKey: "vflat_auto_save_to_gallery") {
            if let img = corrected as UIImage? {
                saveToGallery(img)
            }
        }
        // haptic
        if UserDefaults.standard.object(forKey: "vflat_haptic_feedback") == nil || UserDefaults.standard.bool(forKey: "vflat_haptic_feedback") {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
        }
        _ = page
        // shutter flash handled in view
    }

    func applyCrop(document newDoc: DetectedDocument) {
        // re-process not implemented; placeholder
    }

    func importImages(_ images: [UIImage], options: ImportOptions) async {
        for img in images {
            var corrected = img
            if options.autoCrop {
                if let doc = DocumentDetector.detectOnce(in: img) {
                    corrected = DocumentRectifier().geometryCorrected(image: img, document: doc, autoCrop: true)
                }
            }
            if options.colorEnhance {
                corrected = DocumentRectifier().applyFilter(.auto, to: corrected, enhanceColor: true, darkenText: options.darkenText)
            }
            lastPreviewImage = corrected
            await pageStore.append(processed: corrected, raw: img, filterMode: selectedFilterMode, document: nil)
        }
    }

    func recognizeTextForCurrentPage() async {
        guard let img = lastPreviewImage else { return }
        isRecognizingText = true
        defer { isRecognizingText = false }
        if let text = await ocrService.recognizeText(in: img) {
            lastOCRText = text
            if let page = pageStore.lastPage {
                pageStore.updateOCR(id: page.id, text: text)
            }
        }
    }

    func runAI(_ kind: AIKind) async {
        guard let img = lastPreviewImage else { return }
        isProcessingCapture = true
        defer { isProcessingCapture = false }
        let out: UIImage
        switch kind {
        case .ultra: 
            let s = ShadowRemovalProcessor().process(img) ?? img
            let d = DeblurProcessor().process(s)
            out = d
        case .dewarp:
            out = img // placeholder
        case .shadow:
            out = ShadowRemovalProcessor().process(img) ?? img
        case .deblur:
            out = DeblurProcessor().process(img)
        case .finger:
            out = FingerRemovalProcessor().process(img)
        case .handwriting:
            out = HandwritingRemovalProcessor().process(img)
        }
        lastPreviewImage = out
        if let page = pageStore.lastPage {
            await pageStore.updateProcessed(id: page.id, image: out, filterMode: selectedFilterMode)
        }
    }

    private func saveToGallery(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { _, _ in }
    }
}

enum AIKind { case ultra, dewarp, shadow, deblur, finger, handwriting }

struct ImportOptions {
    var autoCrop: Bool
    var colorEnhance: Bool
    var darkenText: Bool
}
