import Foundation
import UIKit
import Combine

struct ScanPage: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var filterMode: DocumentFilterMode
    var ocrText: String?
    var document: DetectedDocument?
    let rawFileName: String
    let processedFileName: String
    let thumbnailFileName: String

    static func == (lhs: ScanPage, rhs: ScanPage) -> Bool { lhs.id == rhs.id }
}

struct TrashPage: Codable, Identifiable {
    let page: ScanPage
    let deletedAt: Date
    var id: UUID { page.id }
    var daysUntilExpiry: Int {
        let expiry = deletedAt.addingTimeInterval(30 * 86400)
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0)
    }
}

@MainActor
final class ScanPageStore: ObservableObject {
    @Published private(set) var pages: [ScanPage] = []
    @Published private(set) var trashPages: [TrashPage] = []

    private let baseDir: URL
    private let pagesDir: URL
    private let thumbsDir: URL
    private let indexURL: URL
    private let trashURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseDir = docs.appendingPathComponent("vFlat", isDirectory: true)
        pagesDir = baseDir.appendingPathComponent("pages", isDirectory: true)
        thumbsDir = baseDir.appendingPathComponent("thumbnails", isDirectory: true)
        indexURL = baseDir.appendingPathComponent("index.json")
        trashURL = baseDir.appendingPathComponent("trash.json")
        try? FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ScanPage].self, from: data) {
            pages = decoded
        }
        if let data = try? Data(contentsOf: trashURL),
           let decoded = try? JSONDecoder().decode([TrashPage].self, from: data) {
            trashPages = decoded
        }
        pruneExpiredTrash()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(pages) {
            try? data.write(to: indexURL)
        }
        if let data = try? JSONEncoder().encode(trashPages) {
            try? data.write(to: trashURL)
        }
    }

    func append(processed: UIImage, raw: UIImage?, filterMode: DocumentFilterMode, document: DetectedDocument?) async -> ScanPage? {
        let id = UUID()
        let rawName = "\(id.uuidString)_raw.jpg"
        let procName = "\(id.uuidString)_proc.jpg"
        let thumbName = "\(id.uuidString)_thumb.jpg"
        if let raw = raw, let data = raw.jpegData(compressionQuality: 0.90) {
            try? data.write(to: pagesDir.appendingPathComponent(rawName))
        }
        if let data = processed.jpegData(compressionQuality: 0.92) {
            try? data.write(to: pagesDir.appendingPathComponent(procName))
        }
        let thumb = processed.resized(to: CGSize(width: 120, height: 160))
        if let data = thumb.jpegData(compressionQuality: 0.60) {
            try? data.write(to: thumbsDir.appendingPathComponent(thumbName))
        }
        let page = ScanPage(id: id, createdAt: Date(), filterMode: filterMode, ocrText: nil, document: document,
                            rawFileName: rawName, processedFileName: procName, thumbnailFileName: thumbName)
        pages.append(page)
        saveIndex()
        return page
    }

    func delete(id: UUID) {
        if let idx = pages.firstIndex(where: { $0.id == id }) {
            let page = pages.remove(at: idx)
            trashPages.append(TrashPage(page: page, deletedAt: Date()))
            saveIndex()
        }
    }

    func deleteAll() {
        for p in pages { trashPages.append(TrashPage(page: p, deletedAt: Date())) }
        pages.removeAll()
        saveIndex()
    }

    func restore(id: UUID) {
        if let idx = trashPages.firstIndex(where: { $0.id == id }) {
            let tp = trashPages.remove(at: idx)
            pages.append(tp.page)
            saveIndex()
        }
    }

    func restoreAll() {
        for tp in trashPages { pages.append(tp.page) }
        trashPages.removeAll()
        saveIndex()
    }

    func permanentlyDelete(id: UUID) {
        if let idx = trashPages.firstIndex(where: { $0.id == id }) {
            let tp = trashPages.remove(at: idx)
            removeFiles(for: tp.page)
            saveIndex()
        }
    }

    func emptyTrash() {
        for tp in trashPages { removeFiles(for: tp.page) }
        trashPages.removeAll()
        saveIndex()
    }

    func pruneExpiredTrash() {
        let expired = trashPages.filter { $0.daysUntilExpiry <= 0 }
        for tp in expired { removeFiles(for: tp.page) }
        trashPages.removeAll { $0.daysUntilExpiry <= 0 }
        saveIndex()
    }

    func updateProcessed(id: UUID, image: UIImage, filterMode: DocumentFilterMode) async -> Bool {
        guard let idx = pages.firstIndex(where: { $0.id == id }) else { return false }
        let name = pages[idx].processedFileName
        if let data = image.jpegData(compressionQuality: 0.92) {
            try? data.write(to: pagesDir.appendingPathComponent(name))
        }
        pages[idx].filterMode = filterMode
        saveIndex()
        return true
    }

    func updateRaw(id: UUID, image: UIImage) async {
        guard let idx = pages.firstIndex(where: { $0.id == id }) else { return }
        let name = pages[idx].rawFileName
        if let data = image.jpegData(compressionQuality: 0.90) {
            try? data.write(to: pagesDir.appendingPathComponent(name))
        }
    }

    func updateOCR(id: UUID, text: String?) {
        if let idx = pages.firstIndex(where: { $0.id == id }) {
            pages[idx].ocrText = text
            saveIndex()
        }
    }

    func image(for page: ScanPage) -> UIImage? {
        let url = pagesDir.appendingPathComponent(page.processedFileName)
        return UIImage(contentsOfFile: url.path)
    }

    func rawImage(for page: ScanPage) -> UIImage? {
        let url = pagesDir.appendingPathComponent(page.rawFileName)
        return UIImage(contentsOfFile: url.path)
    }

    func thumbnail(for page: ScanPage) -> UIImage? {
        let url = thumbsDir.appendingPathComponent(page.thumbnailFileName)
        return UIImage(contentsOfFile: url.path)
    }

    var lastPage: ScanPage? { pages.last }
    var count: Int { pages.count }

    private func removeFiles(for page: ScanPage) {
        try? FileManager.default.removeItem(at: pagesDir.appendingPathComponent(page.rawFileName))
        try? FileManager.default.removeItem(at: pagesDir.appendingPathComponent(page.processedFileName))
        try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(page.thumbnailFileName))
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        draw(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? self
    }
}
