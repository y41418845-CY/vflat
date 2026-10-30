import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
import PDFKit

/// PDF 頁面大小規格 (對齊 OpenScan)
public enum PDFPageSize: String, CaseIterable, Identifiable {
    case original = "原圖自適應"
    case a4 = "A4 標準 (595x842)"
    case letter = "美規 Letter (612x792)"

    public var id: String { rawValue }

    public var dimensions: CGSize? {
        switch self {
        case .original: return nil
        case .a4: return CGSize(width: 595.2, height: 841.8)
        case .letter: return CGSize(width: 612.0, height: 792.0)
        }
    }
}

/// 匯出壓縮品質設定
public enum PDFCompressionQuality: String, CaseIterable, Identifiable {
    case low = "大幅壓縮 (極低容量)"
    case medium = "標準平衡 (建議)"
    case high = "高清晰度"
    case original = "原始未壓縮"

    public var id: String { rawValue }

    public var compressionRatio: CGFloat {
        switch self {
        case .low: return 0.35
        case .medium: return 0.65
        case .high: return 0.85
        case .original: return 1.0
        }
    }
}

/// 負責將單張或多張掃描圖像合成、壓縮並匯出為標準 PDF 文件 (使用 Apple 原生 PDFKit)
public final class PDFExporter {
    public static let shared = PDFExporter()

    private init() {}

    /// 將 UIImage 陣列轉換為 PDFData
    public func createPDFData(
        from images: [UIImage],
        pageSize: PDFPageSize = .a4,
        quality: PDFCompressionQuality = .medium
    ) -> Data? {
        guard !images.isEmpty else { return nil }

        let pdfDocument = PDFDocument()

        for (index, originalImage) in images.enumerated() {
            // 1. 根據壓縮品質重新編碼圖片
            let compressedImage: UIImage
            if quality != .original, let data = originalImage.jpegData(compressionQuality: quality.compressionRatio), let reloaded = UIImage(data: data) {
                compressedImage = reloaded
            } else {
                compressedImage = originalImage
            }

            // 2. 決定頁面寬高
            let pageBounds: CGRect
            if let fixedSize = pageSize.dimensions {
                pageBounds = CGRect(origin: .zero, size: fixedSize)
            } else {
                pageBounds = CGRect(origin: .zero, size: compressedImage.size)
            }

            // 3. 透過 UIGraphicsPDFRenderer 繪製單頁
            let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
            let pageData = renderer.pdfData { context in
                context.beginPage()

                if let fixedSize = pageSize.dimensions {
                    // 等比例 Aspect-Fit 居中繪製於 A4/Letter 上
                    let imgSize = compressedImage.size
                    let scale = min(fixedSize.width / imgSize.width, fixedSize.height / imgSize.height)
                    let drawWidth = imgSize.width * scale
                    let drawHeight = imgSize.height * scale
                    let drawX = (fixedSize.width - drawWidth) / 2.0
                    let drawY = (fixedSize.height - drawHeight) / 2.0
                    let drawRect = CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)
                    compressedImage.draw(in: drawRect)
                } else {
                    compressedImage.draw(in: pageBounds)
                }
            }

            if let singlePageDoc = PDFDocument(data: pageData), let page = singlePageDoc.page(at: 0) {
                pdfDocument.insert(page, at: index)
            }
        }

        return pdfDocument.dataRepresentation()
    }

    /// 將 PDF 寫入暫存檔以便原生 UIActivityViewController 進行分享
    public func exportTemporaryPDF(
        images: [UIImage],
        fileName: String,
        pageSize: PDFPageSize = .a4,
        quality: PDFCompressionQuality = .medium
    ) -> URL? {
        guard let data = createPDFData(from: images, pageSize: pageSize, quality: quality) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("PDF 寫入暫存檔失敗: \(error)")
            return nil
        }
    }
}
#endif
