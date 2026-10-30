import Foundation
import UIKit
import PDFKit

enum PDFPageSize { case a4, fitWidth, original }

@MainActor
final class PDFExporter {
    func export(pages: [ScanPage], store: ScanPageStore, fileName: String, pageSize: PDFPageSize, password: String?, searchable: Bool) -> URL? {
        let doc = PDFDocument()
        for (i, page) in pages.enumerated() {
            guard let img = store.image(for: page) else { continue }
            let pdfPage = PDFPage(image: img) ?? PDFPage()
            doc.insert(pdfPage, at: i)
            if searchable, let text = page.ocrText {
                // attach as annotation? PDFKit PDFPage has no direct text layer API easily; skip advanced
                _ = text
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).pdf")
        var options: [PDFDocumentWriteOption: Any] = [:]
        if let pw = password, !pw.isEmpty {
            options[.ownerPasswordOption] = pw
            options[.userPasswordOption] = pw
        }
        if doc.write(to: url, withOptions: options) {
            return url
        }
        return nil
    }
}
