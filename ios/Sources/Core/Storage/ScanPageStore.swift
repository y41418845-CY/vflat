import Foundation
import UIKit
import ImageIO

/// 一頁掃描結果的持久化描述。
///
/// 影像本體以 JPEG 落盤（Documents/Scans），記憶體只保留縮圖，
/// 解決舊版將所有頁面以全解析度 `[UIImage]` 保存在記憶體造成的 OOM 風險。
public struct ScanPage: Identifiable, Codable, Equatable {
    public let id: UUID
    public var createdAt: Date
    /// 已上濾鏡、可直接顯示／匯出的 JPEG 檔名
    public var processedFileName: String
    /// 已裁切但**未上濾鏡**的 JPEG 檔名，供切換濾鏡或重新裁切時重用
    public var rawFileName: String?
    public var filterModeRaw: String
    /// 四個角點的正規化座標 [tl.x, tl.y, tr.x, tr.y, br.x, br.y, bl.x, bl.y]
    public var corners: [Double]?
    public var ocrText: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        processedFileName: String,
        rawFileName: String? = nil,
        filterModeRaw: String = DocumentFilterMode.auto.rawValue,
        corners: [Double]? = nil,
        ocrText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.processedFileName = processedFileName
        self.rawFileName = rawFileName
        self.filterModeRaw = filterModeRaw
        self.corners = corners
        self.ocrText = ocrText
    }

    public var filterMode: DocumentFilterMode {
        DocumentFilterMode(rawValue: filterModeRaw) ?? .auto
    }

    public var document: DetectedDocument? {
        guard let corners = corners, corners.count == 8 else { return nil }
        return DetectedDocument(
            topLeft: CGPoint(x: corners[0], y: corners[1]),
            topRight: CGPoint(x: corners[2], y: corners[3]),
            bottomRight: CGPoint(x: corners[4], y: corners[5]),
            bottomLeft: CGPoint(x: corners[6], y: corners[7]),
            confidence: 1.0
        )
    }

    public static func cornersArray(from document: DetectedDocument?) -> [Double]? {
        guard let document = document else { return nil }
        return [
            Double(document.topLeft.x), Double(document.topLeft.y),
            Double(document.topRight.x), Double(document.topRight.y),
            Double(document.bottomRight.x), Double(document.bottomRight.y),
            Double(document.bottomLeft.x), Double(document.bottomLeft.y)
        ]
    }
}

/// 垃圾桶（最近刪除）暫存項目，保留 30 天，提供復原與徹底清除
public struct TrashPage: Identifiable, Codable, Equatable {
    public var id: UUID { page.id }
    public let page: ScanPage
    public let deletedAt: Date

    public init(page: ScanPage, deletedAt: Date = Date()) {
        self.page = page
        self.deletedAt = deletedAt
    }

    /// 剩餘保留天數 (30 天自動清除)
    public var daysRemaining: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }
}

/// 掃描頁面儲存庫：負責 JPEG 落盤、`index.json` 索引、縮圖快取與刪除。
///
/// 所有 UI 狀態變更都在 MainActor；檔案編碼與寫入則丟到背景佇列，
/// 避免 4K JPEG 壓縮阻塞主執行緒（P1-1）。
@MainActor
public final class ScanPageStore: ObservableObject {
    @Published public private(set) var pages: [ScanPage] = []
    @Published public private(set) var trashPages: [TrashPage] = []

    public let rootURL: URL
    private var thumbnailCache: [UUID: UIImage] = [:]
    private let indexFileName = "index.json"
    private let trashIndexFileName = "trash_index.json"

    public init(directoryName: String = "Scans") {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.rootURL = base.appendingPathComponent(directoryName, isDirectory: true)
        load()
    }

    public var lastPage: ScanPage? { pages.last }
    public var count: Int { pages.count }

    // MARK: - 載入 / 索引

    private var indexURL: URL {
        rootURL.appendingPathComponent(indexFileName)
    }

    private var trashIndexURL: URL {
        rootURL.appendingPathComponent(trashIndexFileName)
    }

    private func fileURL(_ fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    /// 從磁碟載入索引與垃圾桶紀錄，並自動過期清除超過 30 天的垃圾檔案
    public func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ScanPage].self, from: data) {
            pages = decoded.filter { FileManager.default.fileExists(atPath: fileURL($0.processedFileName).path) }
        } else {
            pages = []
        }

        // 載入垃圾桶
        if let trashData = try? Data(contentsOf: trashIndexURL),
           let decodedTrash = try? JSONDecoder().decode([TrashPage].self, from: trashData) {
            var validTrash: [TrashPage] = []
            var expiredTrash: [TrashPage] = []

            for item in decodedTrash {
                if item.daysRemaining > 0, FileManager.default.fileExists(atPath: fileURL(item.page.processedFileName).path) {
                    validTrash.append(item)
                } else {
                    expiredTrash.append(item)
                }
            }
            trashPages = validTrash

            // 物理清除過期檔案
            if !expiredTrash.isEmpty {
                let directory = rootURL
                Task.detached(priority: .utility) {
                    for item in expiredTrash {
                        for name in [item.page.processedFileName, item.page.rawFileName].compactMap({ $0 }) {
                            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                        }
                    }
                }
                persistTrashIndex()
            }
        } else {
            trashPages = []
        }
    }

    private func persistIndex() {
        let snapshot = pages
        let url = indexURL
        let directory = rootURL
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[ScanPageStore] 索引寫入失敗: \(error)")
            }
        }
    }

    private func persistTrashIndex() {
        let snapshot = trashPages
        let url = trashIndexURL
        let directory = rootURL
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("[ScanPageStore] 垃圾桶索引寫入失敗: \(error)")
            }
        }
    }

    // MARK: - 新增 / 更新 / 刪除

    /// 新增一頁（JPEG 壓縮與寫檔皆在背景執行）
    /// - Parameters:
    ///   - processed: 已套用濾鏡、可直接顯示的影像
    ///   - raw: 已裁切但未上濾鏡的影像，供日後切換濾鏡／重新裁切
    @discardableResult
    public func append(
        processed: UIImage,
        raw: UIImage?,
        filterMode: DocumentFilterMode,
        document: DetectedDocument?
    ) async -> ScanPage? {
        let id = UUID()
        let processedName = "\(id.uuidString)_p.jpg"
        let rawName = raw == nil ? nil : "\(id.uuidString)_r.jpg"
        let directory = rootURL
        let createdAt = Date()
        let corners = ScanPage.cornersArray(from: document)
        let filterRaw = filterMode.rawValue

        let result = await Task.detached(priority: .userInitiated) { () -> (ScanPage, UIImage)? in
            guard let processedData = processed.jpegData(compressionQuality: 0.9) else { return nil }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try processedData.write(to: directory.appendingPathComponent(processedName), options: .atomic)
                if let raw = raw, let rawData = raw.jpegData(compressionQuality: 0.92) {
                    try rawData.write(to: directory.appendingPathComponent(rawName!), options: .atomic)
                }
            } catch {
                print("[ScanPageStore] 影像寫入失敗: \(error)")
                return nil
            }

            let page = ScanPage(
                id: id,
                createdAt: createdAt,
                processedFileName: processedName,
                rawFileName: rawName,
                filterModeRaw: filterRaw,
                corners: corners
            )
            let thumbnail = ScanPageStore.makeThumbnail(from: processedData, maxPixel: 320)
            return (page, thumbnail ?? processed)
        }.value

        guard let (page, thumbnail) = result else { return nil }
        pages.append(page)
        thumbnailCache[id] = thumbnail
        persistIndex()
        return page
    }

    /// 以新的已處理影像取代指定頁（切換濾鏡或重新裁切後呼叫）
    @discardableResult
    public func updateProcessed(id: UUID, image: UIImage, filterMode: DocumentFilterMode) async -> Bool {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return false }
        let page = pages[index]
        let url = fileURL(page.processedFileName)
        let modeRaw = filterMode.rawValue

        let thumbnail = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                print("[ScanPageStore] 覆寫頁面失敗: \(error)")
                return nil
            }
            return ScanPageStore.makeThumbnail(from: data, maxPixel: 320)
        }.value

        guard let thumbnail = thumbnail else { return false }
        pages[index].filterModeRaw = modeRaw
        thumbnailCache[id] = thumbnail
        persistIndex()
        return true
    }

    public func updateRaw(id: UUID, image: UIImage) async {
        guard let page = pages.first(where: { $0.id == id }),
              let rawName = page.rawFileName else { return }
        let url = fileURL(rawName)
        await Task.detached(priority: .utility) {
            guard let data = image.jpegData(compressionQuality: 0.92) else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }

    public func updateOCR(id: UUID, text: String?) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].ocrText = text
        persistIndex()
    }

    /// 將指定頁面移入垃圾桶 (最近刪除，保留 30 天)
    public func delete(id: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let page = pages.remove(at: index)
        thumbnailCache.removeValue(forKey: id)

        let trashItem = TrashPage(page: page)
        trashPages.insert(trashItem, at: 0)

        persistIndex()
        persistTrashIndex()
    }

    /// 將所有頁面移入垃圾桶 (最近刪除，保留 30 天)
    public func deleteAll() {
        let allPages = pages
        pages = []
        thumbnailCache.removeAll()

        let now = Date()
        let newTrash = allPages.map { TrashPage(page: $0, deletedAt: now) }
        trashPages.insert(contentsOf: newTrash, at: 0)

        persistIndex()
        persistTrashIndex()
    }

    /// 從垃圾桶還原指定頁面
    public func restore(id: UUID) {
        guard let index = trashPages.firstIndex(where: { $0.id == id }) else { return }
        let trashItem = trashPages.remove(at: index)
        pages.append(trashItem.page)

        persistIndex()
        persistTrashIndex()
    }

    /// 從垃圾桶全部還原
    public func restoreAll() {
        let restored = trashPages.map { $0.page }
        trashPages.removeAll()
        pages.append(contentsOf: restored)

        persistIndex()
        persistTrashIndex()
    }

    /// 徹底永久刪除指定垃圾桶項目 (無法撤銷)
    public func permanentlyDelete(id: UUID) {
        guard let index = trashPages.firstIndex(where: { $0.id == id }) else { return }
        let item = trashPages.remove(at: index)
        let directory = rootURL
        let names = [item.page.processedFileName, item.page.rawFileName].compactMap { $0 }
        Task.detached(priority: .utility) {
            for name in names {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
        persistTrashIndex()
    }

    /// 徹底清空垃圾桶 (全部永久抹除)
    public func emptyTrash() {
        let allItems = trashPages
        trashPages.removeAll()
        let directory = rootURL
        Task.detached(priority: .utility) {
            for item in allItems {
                for name in [item.page.processedFileName, item.page.rawFileName].compactMap({ $0 }) {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                }
            }
        }
        persistTrashIndex()
    }

    // MARK: - 讀取

    /// 讀取指定頁的已處理影像（僅在需要顯示大圖時呼叫）
    public func image(for page: ScanPage) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(page.processedFileName)) else { return nil }
        return UIImage(data: data)
    }

    /// 讀取指定頁「已裁切、未上濾鏡」的原始影像
    public func rawImage(for page: ScanPage) -> UIImage? {
        guard let rawName = page.rawFileName,
              let data = try? Data(contentsOf: fileURL(rawName)) else { return nil }
        return UIImage(data: data)
    }

    /// 取得（或產生）縮圖；縮圖會快取在記憶體中
    public func thumbnail(for page: ScanPage, maxPixel: Int = 320) -> UIImage? {
        if let cached = thumbnailCache[page.id] {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL(page.processedFileName)),
              let thumbnail = ScanPageStore.makeThumbnail(from: data, maxPixel: maxPixel) else {
            return nil
        }
        thumbnailCache[page.id] = thumbnail
        return thumbnail
    }

    /// 批次讀取頁面影像（PDF 匯出用，解碼在背景進行）
    public func loadImages(for pages: [ScanPage]) async -> [UIImage] {
        let directory = rootURL
        let names = pages.map { $0.processedFileName }
        return await Task.detached(priority: .userInitiated) { () -> [UIImage] in
            names.compactMap { name in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
                return UIImage(data: data)
            }
        }.value
    }

    // MARK: - 縮圖

    nonisolated private static func makeThumbnail(from data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
