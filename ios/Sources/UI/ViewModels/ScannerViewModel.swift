import Foundation
import SwiftUI
import CoreVideo
import MetalKit
import QuartzCore
import AudioToolbox
import Combine
import UIKit

/// 掃描模式：單頁展平 或 雙頁跨頁掃描
public enum ScanMode: String, CaseIterable, Identifiable {
    case single = "1 頁"
    case doublePage = "2 頁"

    public var id: String { rawValue }
}

/// 相簿批次匯入時可調整的處理選項
public struct ImportOptions {
    public var autoCrop: Bool
    public var colorEnhance: Bool
    public var darkenText: Bool

    public init(autoCrop: Bool = true, colorEnhance: Bool = true, darkenText: Bool = true) {
        self.autoCrop = autoCrop
        self.colorEnhance = colorEnhance
        self.darkenText = darkenText
    }
}

/// 負責統籌相機硬體、Metal 渲染管線、影像後處理與 UI 狀態的主協調器
@MainActor
public final class ScannerViewModel: ObservableObject {
    // MARK: - 掃描狀態

    @Published public var scanMode: ScanMode = .single
    @Published public var detectedDocument: DetectedDocument? = nil
    @Published public var isDocumentDetected: Bool = false
    @Published public var detectedBarcode: DetectedBarcode? = nil
    @Published public var isAutoCaptureEnabled: Bool = false
    @Published public var autoCaptureProgress: Double = 0.0
    @Published public var currentFolder: String = "Scan"

    /// 拍照後的背景後處理是否仍在進行（期間禁用快門）
    @Published public private(set) var isProcessingCapture: Bool = false
    /// 定時拍照倒數（nil 表示沒有倒數）
    @Published public private(set) var captureCountdown: Int? = nil
    /// 顯示給使用者的錯誤訊息（會自動消失）
    @Published public private(set) var errorMessage: String? = nil
    /// 相機權限遭拒
    @Published public private(set) var cameraPermissionDenied: Bool = false

    // MARK: - 頁面與縮圖

    public let pageStore: ScanPageStore
    @Published public private(set) var lastThumbnail: UIImage? = nil
    @Published public private(set) var lastPreviewImage: UIImage? = nil
    @Published public private(set) var lastRawPageImage: UIImage? = nil
    @Published public private(set) var lastPageID: UUID? = nil
    @Published public private(set) var lastOCRText: String? = nil
    @Published public private(set) var isRecognizingText: Bool = false

    public var pages: [ScanPage] { pageStore.pages }
    public var pageCount: Int { pageStore.count }
    /// 舊介面相容別名（僅供讀取，勿再直接修改）
    public var capturedPageCount: Int { pageStore.count }

    // MARK: - 視圖跳轉

    @Published public var showingDocumentDetail: Bool = false
    @Published public var showingPhotoPicker: Bool = false
    @Published public var showingSettings: Bool = false
    @Published public var showingPDFExportSheet: Bool = false

    // MARK: - 濾鏡

    @Published public var selectedFilterMode: DocumentFilterMode = .auto

    // MARK: - 使用者偏好設定（皆有實際消費端）

    @Published public var useScanGuide: Bool = true
    @Published public var autofocusBeforeScan: Bool = true
    @Published public var touchToScan: Bool = false
    @Published public var disableShutterSound: Bool = false
    @Published public var hapticFeedback: Bool = true
    @Published public var cameraTimerSeconds: Int = 0
    @Published public var twoPagesOrderLTR: Bool = true
    @Published public var presetAutoCrop: Bool = true
    /// 曲面展平需要真實模型網格；預設關閉，避免任何合成假曲面破壞輸出
    @Published public var presetCurveCorrection: Bool = false
    @Published public var presetColorEnhance: Bool = true
    @Published public var presetTextDarken: Bool = true
    @Published public var autoSaveToGallery: Bool = false

    @Published public var scanResolution: ScanResolution = .ultraHD4K {
        didSet {
            guard oldValue != scanResolution else { return }
            cameraManager.setResolution(scanResolution)
        }
    }

    /// 相機鏡頭設定 (超廣角推薦 vs 一般廣角)
    @Published public var cameraLens: CameraLens = .ultraWide {
        didSet {
            guard oldValue != cameraLens else { return }
            cameraManager.setLens(cameraLens)
        }
    }

    @Published public var isFlashlightOn: Bool = false {
        didSet {
            guard oldValue != isFlashlightOn else { return }
            cameraManager.setTorch(on: isFlashlightOn)
        }
    }

    @Published public var isShutterFlashing: Bool = false

    // MARK: - 硬體服務

    public let cameraManager = CameraManager()
    public let motionSensor = MotionSensor()
    public let documentDetector = DocumentDetector()
    public let autoCaptureDetector = AutoCaptureDetector()
    public var metalRenderer: MetalDewarpRenderer?

    // MARK: - 私有狀態

    private var lastAutoCaptureTime: TimeInterval = 0
    private var countdownTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public convenience init() {
        self.init(pageStore: ScanPageStore())
    }

    public init(pageStore: ScanPageStore) {
        self.pageStore = pageStore
        setupDetector()
        bindPageStore()
        bindHardware()
        restoreLastPage()
    }

    // MARK: - 初始化輔助

    private func bindPageStore() {
        // 巢狀 ObservableObject 不會自動把 objectWillChange 往外傳，
        // 這裡明確轉發，否則頁數／縮圖變動時 SwiftUI 不會重繪。
        pageStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// `CameraManager` 與 `MotionSensor` 同樣是巢狀 ObservableObject。
    /// 沒有轉發時，補光燈可用性、實際幀率、解析度與水平姿態都不會反映到 UI。
    private func bindHardware() {
        cameraManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        motionSensor.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func restoreLastPage() {
        guard let page = pageStore.lastPage else { return }
        lastPageID = page.id
        lastThumbnail = pageStore.thumbnail(for: page)
        lastPreviewImage = pageStore.image(for: page)
        lastRawPageImage = pageStore.rawImage(for: page)
        lastOCRText = page.ocrText
    }

    private func setupDetector() {
        documentDetector.onDocumentDetected = { [weak self] doc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.detectedDocument = doc
                self.isDocumentDetected = (doc != nil)

                guard self.isAutoCaptureEnabled else {
                    self.autoCaptureDetector.reset()
                    self.autoCaptureProgress = 0
                    return
                }

                let now = CACurrentMediaTime()
                let shouldTrigger = self.autoCaptureDetector.processFrame(document: doc, at: now)
                self.autoCaptureProgress = self.autoCaptureDetector.stabilityProgress

                // 避免連續短時間連擊
                if shouldTrigger, now - self.lastAutoCaptureTime > 1.8 {
                    self.lastAutoCaptureTime = now
                    self.triggerCapture()
                }
            }
        }

        documentDetector.onBarcodeDetected = { [weak self] barcode in
            DispatchQueue.main.async {
                self?.detectedBarcode = barcode
            }
        }
    }

    // MARK: - 相機與渲染器

    public func attachRenderer(_ renderer: MetalDewarpRenderer) {
        self.metalRenderer = renderer
        applyCurvatureMesh()

        let detector = documentDetector
        cameraManager.onFrameCaptured = { [weak renderer] pixelBuffer in
            renderer?.feedFrame(pixelBuffer)
            detector.processFrame(pixelBuffer)
        }
    }

    /// 預覽維持 1:1 真實比例（平坦網格 + 強度 0），不套用任何合成曲面
    public func applyCurvatureMesh() {
        let flat = DewarpGeometry.makeFlatGrid()
        metalRenderer?.updateMesh(with: flat)
        metalRenderer?.setDewarpStrength(0.0, mode: 0)
    }

    public func startScanning() async {
        let authorized = await cameraManager.checkPermissions()
        guard authorized else {
            cameraPermissionDenied = true
            showError("相機權限未開啟，請至「設定」允許 vFlat 使用相機")
            return
        }

        cameraPermissionDenied = false
        cameraManager.setupSession(resolution: scanResolution, lens: cameraLens)
        cameraLens = cameraManager.lens
        cameraManager.startSession()
        motionSensor.startUpdates()
        pageStore.load()
        restoreLastPage()
    }

    public func stopScanning() {
        cancelCountdown()
        cameraManager.stopSession()
        motionSensor.stopUpdates()
        if isFlashlightOn {
            isFlashlightOn = false
        }
    }

    // MARK: - 拍照

    /// 快門入口：有設定定時器時先倒數，否則立即拍攝
    public func triggerCapture() {
        guard !isProcessingCapture else { return }

        if captureCountdown != nil {
            cancelCountdown()
            return
        }

        if cameraTimerSeconds > 0 {
            startCountdown(seconds: cameraTimerSeconds)
        } else {
            performCapture()
        }
    }

    public func performCapture() {
        guard !isProcessingCapture else { return }

        if autofocusBeforeScan {
            cameraManager.focusAndExposeCenterIfNeeded()
        }
        if hapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if !disableShutterSound {
            // 1108 = 系統快門音；影片串流不會自動發聲，需手動補上
            AudioServicesPlaySystemSound(1108)
        }
        flashShutter()

        guard let buffer = cameraManager.latestPixelBufferSnapshot() else {
            showError("尚未取得相機畫面，請稍候再試")
            return
        }

        // 拍照當下用同一個影格重新偵測，避免 EMA 平滑與 350ms 滯後造成裁切錯位
        let frameDocument = DocumentDetector.detectOnce(in: buffer)
            ?? (presetAutoCrop ? detectedDocument : nil)

        guard let rawImage = CameraManager.makeImage(from: buffer) else {
            showError("無法擷取相機影像")
            return
        }

        isProcessingCapture = true
        lastOCRText = nil

        let autoCrop = presetAutoCrop
        let mode = selectedFilterMode
        let enhanceColor = presetColorEnhance
        let darkenText = presetTextDarken
        let splitDoublePage = (scanMode == .doublePage)
        let leftToRight = twoPagesOrderLTR

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = ScannerViewModel.processCapture(
                rawImage: rawImage,
                document: autoCrop ? frameDocument : nil,
                autoCrop: autoCrop,
                mode: mode,
                enhanceColor: enhanceColor,
                darkenText: darkenText,
                splitDoublePage: splitDoublePage,
                leftToRight: leftToRight
            )
            guard let self = self else { return }
            await self.finishCapture(result, document: frameDocument)
        }
    }

    private struct CaptureResult {
        let geometricPages: [UIImage]
        let processedPages: [UIImage]
        let document: DetectedDocument?
    }

    /// 影像後處理（在背景執行）：透視裁切 → 雙頁分割 → 套濾鏡
    nonisolated private static func processCapture(
        rawImage: UIImage,
        document: DetectedDocument?,
        autoCrop: Bool,
        mode: DocumentFilterMode,
        enhanceColor: Bool,
        darkenText: Bool,
        splitDoublePage: Bool,
        leftToRight: Bool
    ) -> CaptureResult? {
        let rectifier = DocumentRectifier.shared
        let geometric = rectifier.geometryCorrected(image: rawImage, document: document, autoCrop: autoCrop)

        var geometricPages: [UIImage] = [geometric]
        if splitDoublePage {
            let spineRatio = BookPageSplitter.shared.detectSpineRatio(image: geometric)
            if let split = BookPageSplitter.shared.splitPage(image: geometric, splitRatio: spineRatio) {
                geometricPages = split.orderedPages(leftToRight: leftToRight)
            }
        }

        let processedPages = geometricPages.map {
            rectifier.applyFilter(mode, to: $0, enhanceColor: enhanceColor, darkenText: darkenText)
        }
        guard !processedPages.isEmpty else { return nil }
        return CaptureResult(geometricPages: geometricPages, processedPages: processedPages, document: document)
    }

    private func finishCapture(_ result: CaptureResult?, document: DetectedDocument?) async {
        defer { isProcessingCapture = false }

        guard let result = result, !result.processedPages.isEmpty else {
            showError("影像後處理失敗，請重試")
            return
        }

        var lastPage: ScanPage? = nil
        for index in result.processedPages.indices {
            let processed = result.processedPages[index]
            let raw = result.geometricPages.indices.contains(index) ? result.geometricPages[index] : nil
            if let page = await pageStore.append(
                processed: processed,
                raw: raw,
                filterMode: selectedFilterMode,
                document: document
            ) {
                lastPage = page
                if autoSaveToGallery {
                    UIImageWriteToSavedPhotosAlbum(processed, nil, nil, nil)
                }
            }
        }

        guard let page = lastPage else {
            showError("儲存掃描頁面失敗，請確認裝置儲存空間")
            return
        }

        lastPageID = page.id
        lastPreviewImage = pageStore.image(for: page)
        lastRawPageImage = result.geometricPages.last
        lastThumbnail = pageStore.thumbnail(for: page)
    }

    // MARK: - 定時器

    public func cycleCaptureTimer() {
        switch cameraTimerSeconds {
        case 0: cameraTimerSeconds = 3
        case 3: cameraTimerSeconds = 5
        case 5: cameraTimerSeconds = 7
        default: cameraTimerSeconds = 0
        }
    }

    private func startCountdown(seconds: Int) {
        cancelCountdown()
        let total = max(1, seconds)
        captureCountdown = total

        countdownTask = Task { [weak self] in
            var remaining = total
            while remaining > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                remaining -= 1
                guard let self = self else { return }
                self.captureCountdown = remaining > 0 ? remaining : nil
            }
            guard let self = self, !Task.isCancelled else { return }
            self.captureCountdown = nil
            self.performCapture()
        }
    }

    public func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        if captureCountdown != nil {
            captureCountdown = nil
        }
    }

    // MARK: - 補光燈與濾鏡

    public func toggleTorch() {
        guard cameraManager.isTorchAvailable || cameraManager.isTorchOn else {
            showError("此鏡頭不支援補光燈")
            return
        }
        isFlashlightOn.toggle()
    }

    public func cycleFilterMode() {
        let all = DocumentFilterMode.allCases
        guard let index = all.firstIndex(of: selectedFilterMode) else {
            updateFilterMode(all[0])
            return
        }
        updateFilterMode(all[(index + 1) % all.count])
    }

    /// 切換濾鏡：以最後一頁「已裁切未上色」的原始檔重新套用，不需重拍
    public func updateFilterMode(_ mode: DocumentFilterMode) {
        selectedFilterMode = mode

        guard !isProcessingCapture,
              let page = pageStore.lastPage,
              let raw = pageStore.rawImage(for: page) ?? lastRawPageImage else {
            return
        }

        isProcessingCapture = true
        let enhanceColor = presetColorEnhance
        let darkenText = presetTextDarken
        let store = pageStore

        Task.detached(priority: .userInitiated) { [weak self] in
            let processed = DocumentRectifier.shared.applyFilter(
                mode,
                to: raw,
                enhanceColor: enhanceColor,
                darkenText: darkenText
            )
            guard let self = self else { return }
            let updated = await store.updateProcessed(id: page.id, image: processed, filterMode: mode)

            await MainActor.run {
                self.isProcessingCapture = false
                if updated {
                    self.lastPreviewImage = processed
                    self.lastThumbnail = store.thumbnail(for: page)
                } else {
                    self.showError("套用濾鏡失敗")
                }
            }
        }
    }

    /// 手動裁切後重新產生頁面（來源為最後一頁已裁切未上色的影像）
    public func applyCrop(document: DetectedDocument) {
        guard !isProcessingCapture,
              let page = pageStore.lastPage,
              let source = pageStore.rawImage(for: page) ?? lastRawPageImage else {
            return
        }

        isProcessingCapture = true
        let mode = selectedFilterMode
        let enhanceColor = presetColorEnhance
        let darkenText = presetTextDarken
        let store = pageStore

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let cropped = DocumentRectifier.shared.correctPerspective(image: source, document: document) else {
                await MainActor.run {
                    self?.isProcessingCapture = false
                    self?.showError("裁切失敗，請重新調整角點")
                }
                return
            }
            let processed = DocumentRectifier.shared.applyFilter(
                mode,
                to: cropped,
                enhanceColor: enhanceColor,
                darkenText: darkenText
            )

            guard let self = self else { return }
            await store.updateRaw(id: page.id, image: cropped)
            let updated = await store.updateProcessed(id: page.id, image: processed, filterMode: mode)

            await MainActor.run {
                self.isProcessingCapture = false
                if updated {
                    self.lastPreviewImage = processed
                    self.lastRawPageImage = cropped
                    self.lastThumbnail = store.thumbnail(for: page)
                } else {
                    self.showError("更新裁切結果失敗")
                }
            }
        }
    }

    // MARK: - 原廠 AI 核心功能 (Deblur / Finger Removal / Handwriting Removal)

    /// 對指定頁面（預設為最後一頁）執行 AI 模糊修復 (Deblur)
    public func applyDeblur(to targetPage: ScanPage? = nil) async {
        guard !isProcessingCapture,
              let page = targetPage ?? pageStore.lastPage,
              let currentImage = pageStore.image(for: page) ?? lastPreviewImage else {
            return
        }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let store = pageStore
        let pageId = page.id
        let filterMode = page.filterMode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            return DeblurProcessor.shared.deblur(image: currentImage)
        }.value

        guard let deblurred = result else {
            showError("AI 模糊修復失敗")
            return
        }

        let updated = await store.updateProcessed(id: pageId, image: deblurred, filterMode: filterMode)
        if updated {
            lastPreviewImage = deblurred
            lastThumbnail = store.thumbnail(for: page)
        } else {
            showError("儲存修復結果失敗")
        }
    }

    /// 對指定頁面（預設為最後一頁）執行 AI 手指抹除 (Finger Inpaint)
    public func applyFingerRemoval(to targetPage: ScanPage? = nil) async {
        guard !isProcessingCapture,
              let page = targetPage ?? pageStore.lastPage,
              let currentImage = pageStore.image(for: page) ?? lastPreviewImage else {
            return
        }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let store = pageStore
        let pageId = page.id
        let filterMode = page.filterMode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            return FingerRemovalProcessor.shared.removeFingers(image: currentImage)
        }.value

        guard let cleaned = result else {
            showError("AI 手指抹除失敗")
            return
        }

        let updated = await store.updateProcessed(id: pageId, image: cleaned, filterMode: filterMode)
        if updated {
            lastPreviewImage = cleaned
            lastThumbnail = store.thumbnail(for: page)
        } else {
            showError("儲存修補結果失敗")
        }
    }

    /// 對指定頁面（預設為最後一頁）執行 AI 手寫筆跡消除 (Handwriting Removal)
    public func applyHandwritingRemoval(to targetPage: ScanPage? = nil) async {
        guard !isProcessingCapture,
              let page = targetPage ?? pageStore.lastPage,
              let currentImage = pageStore.image(for: page) ?? lastPreviewImage else {
            return
        }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let store = pageStore
        let pageId = page.id
        let filterMode = page.filterMode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            return HandwritingRemovalProcessor.shared.removeHandwriting(image: currentImage)
        }.value

        guard let cleaned = result else {
            showError("手寫筆跡消除失敗")
            return
        }

        let updated = await store.updateProcessed(id: pageId, image: cleaned, filterMode: filterMode)
        if updated {
            lastPreviewImage = cleaned
            lastThumbnail = store.thumbnail(for: page)
        } else {
            showError("儲存清除結果失敗")
        }
    }

    /// 對指定頁面（預設為最後一頁）執行 AI 手機陰影消除 (Shadow Removal)
    public func applyShadowRemoval(to targetPage: ScanPage? = nil) async {
        guard !isProcessingCapture,
              let page = targetPage ?? pageStore.lastPage,
              let currentImage = pageStore.image(for: page) ?? lastPreviewImage else {
            return
        }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let store = pageStore
        let pageId = page.id
        let filterMode = page.filterMode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            return ShadowRemovalProcessor.shared.removeShadow(image: currentImage)
        }.value

        guard let cleaned = result else {
            showError("陰影消除失敗")
            return
        }

        let updated = await store.updateProcessed(id: pageId, image: cleaned, filterMode: filterMode)
        if updated {
            lastPreviewImage = cleaned
            lastThumbnail = store.thumbnail(for: page)
        } else {
            showError("儲存陰影消除結果失敗")
        }
    }

    /// 對指定頁面執行 25x25 自由曲面展平 (Metal GPU Dewarping)
    public func applyDewarp(to targetPage: ScanPage? = nil) async {
        guard !isProcessingCapture,
              let page = targetPage ?? pageStore.lastPage,
              let currentImage = pageStore.image(for: page) ?? lastPreviewImage else {
            return
        }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let store = pageStore
        let pageId = page.id
        let filterMode = page.filterMode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let dynamicGrid = DynamicDewarpPredictor.shared.predictGrid(for: currentImage)
            return MetalOffscreenDewarper.shared.dewarpImage(
                image: currentImage,
                curvedGrid: dynamicGrid,
                dewarpStrength: 1.0
            )
        }.value

        guard let dewarped = result else {
            showError("曲面展平失敗")
            return
        }

        let updated = await store.updateProcessed(id: pageId, image: dewarped, filterMode: filterMode)
        if updated {
            lastPreviewImage = dewarped
            lastThumbnail = store.thumbnail(for: page)
        } else {
            showError("儲存展平結果失敗")
        }
    }

    /// 一鍵極致旗艦修復 (Ultra Scan)：展平 + 消陰影 + 消手指 + 銳化去模糊流水線
    public func applyUltraScan(to targetPage: ScanPage? = nil) async {
        guard !isProcessingCapture,
              let page = targetPage ?? pageStore.lastPage,
              let sourceImage = pageStore.image(for: page) ?? lastPreviewImage else {
            return
        }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let store = pageStore
        let pageId = page.id
        let filterMode = page.filterMode

        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            var working = sourceImage

            // 1. 25x25 自由曲面 GPU 展平
            let grid = DynamicDewarpPredictor.shared.predictGrid(for: working)
            if let dewarped = MetalOffscreenDewarper.shared.dewarpImage(image: working, curvedGrid: grid) {
                working = dewarped
            }

            // 2. 手機陰影均勻化消除
            if let noShadow = ShadowRemovalProcessor.shared.removeShadow(image: working) {
                working = noShadow
            }

            // 3. 邊緣手指抹除
            if let noFingers = FingerRemovalProcessor.shared.removeFingers(image: working) {
                working = noFingers
            }

            // 4. 文字邊緣與去模糊超解析度增強
            if let deblurred = DeblurProcessor.shared.deblur(image: working) {
                working = deblurred
            }

            return working
        }.value

        guard let finalImage = result else {
            showError("極致掃描處理失敗")
            return
        }

        let updated = await store.updateProcessed(id: pageId, image: finalImage, filterMode: filterMode)
        if updated {
            lastPreviewImage = finalImage
            lastThumbnail = store.thumbnail(for: page)
        } else {
            showError("儲存極致修復結果失敗")
        }
    }

    // MARK: - JPG 匯出與儲存

    /// 將當前頁面儲存為 .jpg 檔案並寫入相簿或產生分享實體檔案路徑
    @discardableResult
    public func saveCurrentPageAsJPEG(saveToPhotos: Bool = true) async -> URL? {
        guard let page = pageStore.lastPage,
              let image = pageStore.image(for: page) ?? lastPreviewImage,
              let data = image.jpegData(compressionQuality: 0.95) else {
            showError("無法生成 JPG 影像資料")
            return nil
        }

        // 1. 若指定儲存至相簿
        if saveToPhotos {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        // 2. 寫入暫存目錄以取得實體 .jpg 檔案路徑（供分享或其他應用程式開啟）
        let fileName = "Scan_\(Int(Date().timeIntervalSince1970))_\(page.id.uuidString.prefix(6)).jpg"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            showError("儲存 JPG 檔案失敗：\(error.localizedDescription)")
            return nil
        }
    }

    /// 批次將所有掃描頁儲存至相簿為 .jpg 圖片
    @discardableResult
    public func saveAllPagesToPhotos() async -> Int {
        var count = 0
        for page in pages {
            if let image = pageStore.image(for: page) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                count += 1
            }
        }
        return count
    }

    // MARK: - 頁面管理

    public func deleteLastPage() {
        guard let page = pageStore.lastPage else { return }
        pageStore.delete(id: page.id)
        lastOCRText = nil

        if let newLast = pageStore.lastPage {
            lastPageID = newLast.id
            lastPreviewImage = pageStore.image(for: newLast)
            lastRawPageImage = pageStore.rawImage(for: newLast)
            lastThumbnail = pageStore.thumbnail(for: newLast)
            lastOCRText = newLast.ocrText
        } else {
            lastPageID = nil
            lastPreviewImage = nil
            lastRawPageImage = nil
            lastThumbnail = nil
            lastOCRText = nil
            detectedDocument = nil
        }
    }

    /// 清除全部掃描頁面（含索引與縮圖快取），並同步重設 UI 狀態
    public func clearAllPages() {
        pageStore.deleteAll()
        lastPageID = nil
        lastPreviewImage = nil
        lastRawPageImage = nil
        lastThumbnail = nil
        lastOCRText = nil
        detectedDocument = nil
    }

    // MARK: - OCR

    /// 對最後一頁執行離線文字辨識，結果會寫回頁面索引
    public func recognizeLastPageText() async {
        guard !isRecognizingText, let page = pageStore.lastPage else { return }
        isRecognizingText = true
        defer { isRecognizingText = false }

        guard let image = pageStore.image(for: page) else {
            showError("無法讀取頁面影像")
            return
        }

        if let text = await OCRService.shared.recognizeText(in: image), !text.isEmpty {
            lastOCRText = text
            pageStore.updateOCR(id: page.id, text: text)
        } else {
            lastOCRText = nil
            showError("未辨識到文字，請嘗試提高拍攝清晰度")
        }
    }

    // MARK: - 相簿匯入

    /// 批次匯入相簿影像，並套用指定選項後落盤為掃描頁
    @discardableResult
    public func importImages(_ images: [UIImage], options: ImportOptions) async -> Int {
        guard !images.isEmpty else { return 0 }

        isProcessingCapture = true
        defer { isProcessingCapture = false }

        let mode = selectedFilterMode
        var importedCount = 0

        for image in images {
            let document = options.autoCrop ? DocumentDetector.detectOnce(in: image) : nil

            let result = await Task.detached(priority: .userInitiated) { () -> (geometric: UIImage, processed: UIImage)? in
                let rectifier = DocumentRectifier.shared
                let geometric = rectifier.geometryCorrected(image: image, document: document, autoCrop: options.autoCrop)
                let processed = rectifier.applyFilter(
                    mode,
                    to: geometric,
                    enhanceColor: options.colorEnhance,
                    darkenText: options.darkenText
                )
                return (geometric, processed)
            }.value

            guard let result = result else { continue }
            guard let page = await pageStore.append(
                processed: result.processed,
                raw: result.geometric,
                filterMode: mode,
                document: document
            ) else { continue }

            importedCount += 1
            lastPageID = page.id
            lastPreviewImage = result.processed
            lastRawPageImage = result.geometric
            lastThumbnail = pageStore.thumbnail(for: page)
            lastOCRText = nil

            if autoSaveToGallery {
                UIImageWriteToSavedPhotosAlbum(result.processed, nil, nil, nil)
            }
        }

        if importedCount == 0 {
            showError("匯入失敗，請確認相簿權限")
        }
        return importedCount
    }

    // MARK: - 錯誤提示

    public func showError(_ message: String) {
        errorMessage = message
        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }

    public func clearError() {
        errorDismissTask?.cancel()
        errorMessage = nil
    }

    // MARK: - 快門閃光

    private func flashShutter() {
        withAnimation(.easeOut(duration: 0.08)) {
            isShutterFlashing = true
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self = self else { return }
            withAnimation(.easeIn(duration: 0.12)) {
                self.isShutterFlashing = false
            }
        }
    }
}
