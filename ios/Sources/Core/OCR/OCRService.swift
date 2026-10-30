import Foundation
import UIKit
import Vision

final class OCRService {
    func recognizeText(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { request, error in
                guard let obs = request.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: nil); return
                }
                let text = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                cont.resume(returning: text.isEmpty ? nil : text)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) } catch { cont.resume(returning: nil) }
        }
    }
}
