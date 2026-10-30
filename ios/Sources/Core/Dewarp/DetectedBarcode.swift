import Foundation
import CoreGraphics

/// QR Code 或條碼辨識結果物件
public struct DetectedBarcode: Identifiable, Equatable {
    /// 僅作為 SwiftUI 身分識別使用，**不參與相等性比較**
    public let id: UUID
    public let payloadString: String
    public let symbology: String
    public let boundingBox: CGRect
    public let timestamp: TimeInterval

    public init(payloadString: String, symbology: String, boundingBox: CGRect = .zero, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.id = UUID()
        self.payloadString = payloadString
        self.symbology = symbology
        self.boundingBox = boundingBox
        self.timestamp = timestamp
    }

    /// 只比較真正代表「同一個條碼」的欄位。
    /// 舊版讓合成的 `id`（每次新建都不同）參與比較，導致同一條碼每一幀都被判定為新值，
    /// 使 UI 持續重繪、動畫抖動，且 SwiftUI 的 `onChange` / `Equatable` 判斷完全失效。
    public static func == (lhs: DetectedBarcode, rhs: DetectedBarcode) -> Bool {
        lhs.payloadString == rhs.payloadString &&
        lhs.symbology == rhs.symbology &&
        lhs.boundingBox == rhs.boundingBox &&
        lhs.timestamp == rhs.timestamp
    }

    /// 是否為 URL 網址
    public var isURL: Bool {
        if let url = URL(string: payloadString), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return true
        }
        return false
    }

    /// 簡潔圖標
    public var iconName: String {
        if isURL {
            return "link"
        } else if symbology.uppercased().contains("QR") {
            return "qrcode"
        } else {
            return "barcode"
        }
    }
}
