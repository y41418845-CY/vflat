import Foundation
import UIKit
import Vision

final class BarcodeScannerService {
    private let request = VNDetectBarcodesRequest()

    func detect(in pixelBuffer: CVPixelBuffer) -> DetectedBarcode? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first, let payload = obs.payloadStringValue else { return nil }
        let sym = obs.symbology
        let isURL = URL(string: payload)?.scheme != nil
        let icon: String
        switch sym {
        case .qr: icon = "qrcode"
        default: icon = "barcode"
        }
        return DetectedBarcode(payloadString: payload, symbology: sym, isURL: isURL, iconName: icon)
    }
}
