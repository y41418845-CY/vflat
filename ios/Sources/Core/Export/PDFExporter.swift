import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
import PDFKit

/// PDF 頁面大小規格 (對齊原廠 vFlat 與 OpenScan)
public enum PDFPageSize: String, CaseIterable, Identifiable {
    case original = "原圖自適應"
    case fitWidth = "適應寬度"
    case a4 = "A4 標準 (595x842)"
    case letter = "美規 Letter (612x792)"

    public var id: String { rawValue }

    public var dimensions: CGSize? {
        switch self {
        case .original, .fitWidth: return nil
        case .a4: return CGSize(width: 595.2, height: 841.8)
        case .letter: return CGSize(width: 612.0, height: 792.0)
        }
    }
}

/// PDF 頁面方向設定
public enum PDFPageOrientation: String, CaseIterable, Identifiable {
    case auto = "自動 (依照原圖)"
    case portrait = "垂直直向"
    case landscape = "水平橫向"

    public var id: String { rawValue }
}

/// PDF 頁面色彩模式
public enum PDFColorMode: String, CaseIterable, Identifiable {
    case color = "彩色"
    case grayscale = "黑白灰階"

    public var id: String { rawValue }
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

    /// 將 UIImage 陣列轉換為 PDFData (支援方向、色彩、尺寸、密碼與文字層)
    public func createPDFData(
        from images: [UIImage],
        ocrTexts: [String?]? = nil,
        pageSize: PDFPageSize = .a4,
        orientation: PDFPageOrientation = .auto,
        colorMode: PDFColorMode = .color,
        quality: PDFCompressionQuality = .medium,
        password: String? = nil
    ) -> Data? {
        guard !images.isEmpty else { return nil }

        let pdfDocument = PDFDocument()

        for (index, originalImage) in images.enumerated() {
            var workingImage = originalImage

            // 1. 色彩模式轉換（若選擇黑白灰階）
            if colorMode == .grayscale, let cgImage = workingImage.cgImage {
                let ci = CIImage(cgImage: cgImage)
                if let grayFilter = CIFilter(name: "CIPhotoEffectNoir") {
                    grayFilter.setValue(ci, forKey: kCIInputImageKey)
                    if let outCI = grayFilter.outputImage,
                       let outCG = CIContext().createCGImage(outCI, from: outCI.extent) {
                        workingImage = UIImage(cgImage: outCG, scale: workingImage.scale, orientation: workingImage.imageOrientation)
                    }
                }
            }

            // 2. 根據壓縮品質重新編碼圖片
            let compressedImage: UIImage
            if quality != .original, let data = workingImage.jpegData(compressionQuality: quality.compressionRatio), let reloaded = UIImage(data: data) {
                compressedImage = reloaded
            } else {
                compressedImage = workingImage
            }

            // 3. 決定方向與寬高尺寸
            var targetBounds: CGRect
            if let fixedSize = pageSize.dimensions {
                var size = fixedSize
                if orientation == .landscape || (orientation == .auto && compressedImage.size.width > compressedImage.size.height) {
                    size = CGSize(width: max(fixedSize.width, fixedSize.height), height: min(fixedSize.width, fixedSize.height))
                } else if orientation == .portrait {
                    size = CGSize(width: min(fixedSize.width, fixedSize.height), height: max(fixedSize.width, fixedSize.height))
                }
                targetBounds = CGRect(origin: .zero, size: size)
            } else if pageSize == .fitWidth {
                let standardWidth: CGFloat = 595.2
                let aspect = compressedImage.size.height / compressedImage.size.width
                targetBounds = CGRect(x: 0, y: 0, width: standardWidth, height: standardWidth * aspect)
            } else {
                targetBounds = CGRect(origin: .zero, size: compressedImage.size)
            }

            // 4. 透過 UIGraphicsPDFRenderer 繪製頁面與嵌入 OCR 文字層
            let renderer = UIGraphicsPDFRenderer(bounds: targetBounds)
            let pageData = renderer.pdfData { context in
                context.beginPage()

                // 繪製影像
                if pageSize.dimensions != nil || pageSize == .fitWidth {
                    let imgSize = compressedImage.size
                    let scale = min(targetBounds.width / imgSize.width, targetBounds.height / imgSize.height)
                    let drawWidth = imgSize.width * scale
                    let drawHeight = imgSize.height * scale
                    let drawX = (targetBounds.width - drawWidth) / 2.0
                    let drawY = (targetBounds.height - drawHeight) / 2.0
                    let drawRect = CGRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)
                    compressedImage.draw(in: drawRect)
                } else {
                    compressedImage.draw(in: targetBounds)
                }

                // 5. 可搜尋 PDF：若有 OCR 文字，將文字以透明層嵌入該頁
                if let ocrList = ocrTexts, index < ocrList.count, let text = ocrList[index], !text.isEmpty {
                    let textRect = CGRect(x: 20, y: 20, width: targetBounds.width - 40, height: targetBounds.height - 40)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10),
                        .foregroundColor: UIColor.clear // 隱形文字層，供選取複製
                    ]
                    (text as NSString).draw(in: textRect, withAttributes: attrs)
                }
            }

            if let singlePageDoc = PDFDocument(data: pageData), let page = singlePageDoc.page(at: 0) {
                pdfDocument.insert(page, at: index)
            }
        }

        // 6. 密碼保護處理 (若有設定密碼)
        if let pwd = password, !pwd.trimmingCharacters(in: .whitespaces).isEmpty {
            let options: [PDFDocumentWriteOption: Any] = [
                .userPasswordOption: pwd,
                .ownerPasswordOption: pwd
            ]
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            if pdfDocument.write(to: tempURL, withOptions: options), let protectedData = try? Data(contentsOf: tempURL) {
                try? FileManager.default.removeItem(at: tempURL)
                return protectedData
            }
        }

        return pdfDocument.dataRepresentation()
    }

    /// 輸出 PDF 實體檔案至暫存目錄（供 UIActivityViewController 分享）
    public func exportTemporaryPDF(
        images: [UIImage],
        ocrTexts: [String?]? = nil,
        fileName: String = "ScanDocument.pdf",
        pageSize: PDFPageSize = .a4,
        orientation: PDFPageOrientation = .auto,
        colorMode: PDFColorMode = .color,
        quality: PDFCompressionQuality = .medium,
        password: String? = nil
    ) -> URL? {
        guard let data = createPDFData(
            from: images,
            ocrTexts: ocrTexts,
            pageSize: pageSize,
            orientation: orientation,
            colorMode: colorMode,
            quality: quality,
            password: password
        ) else { return nil }

        let cleanName = fileName.hasSuffix(".pdf") ? fileName : "\(fileName).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(cleanName)

        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("[PDFExporter] 寫入暫存 PDF 失敗: \(error)")
            return nil
        }
    }
}
#endif
