import Foundation
import CoreGraphics

/// QR Code 或條碼辨識結果物件
public struct DetectedBarcode: Identifiable, Equatable {
    public let id = UUID()
    public let payloadString: String
    public let symbology: String
    public let boundingBox: CGRect
    public let timestamp: TimeInterval

    public init(payloadString: String, symbology: String, boundingBox: CGRect = .zero, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.payloadString = payloadString
        self.symbology = symbology
        self.boundingBox = boundingBox
        self.timestamp = timestamp
    }

    /// 是否為 URL 網址
    public var isURL: Bool {
        if let url = URL(string: payloadString), url.scheme != nil, (url.scheme == "http" || url.scheme == "https") {
            return true
        }
        return false
    }

    /// 簡潔圖標
    public var iconName: String {
        if isURL {
            return "link"
        } else if symbology.contains("QR") {
            return "qrcode"
        } else {
            return "barcode"
        }
    }
}
