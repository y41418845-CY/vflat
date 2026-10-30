import Foundation
import Vision
import UIKit

/// 以 Apple Vision 原生離線引擎辨識文件文字（支援繁體中文）。
public struct OCRService: Sendable {
    public static let shared = OCRService()

    /// 使用者偏好的語言順序；Vision 不支援的語言會被自動剔除
    public let preferredLanguages: [String]

    public init(preferredLanguages: [String] = ["zh-Hant", "zh-Hans", "en-US"]) {
        self.preferredLanguages = preferredLanguages
    }

    /// 非同步辨識單張影像中的文字
    /// - Returns: 依視覺由上到下、由左到右排序並以換行串接的文字；無結果時回傳 nil。
    public func recognizeText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = false

                let supported = (try? request.supportedRecognitionLanguages()) ?? []
                let candidates = self.preferredLanguages.filter { supported.contains($0) }
                if !candidates.isEmpty {
                    request.recognitionLanguages = candidates
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    print("[OCRService] 文字辨識失敗: \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                let observations = (request.results ?? []).sorted { lhs, rhs in
                    // Vision 座標原點在左下角：Y 越大越上面
                    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }

                let lines: [String] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }

                guard !lines.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
