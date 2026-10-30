import Foundation

/// 智慧文件命名服務 (對齊 OpenScan 命名規則)
public struct DocumentNamingService {
    /// 產生標準檔案名稱
    /// - Parameters:
    ///   - prefix: 自訂分類前綴或資料夾名稱 (如 "涓建築" 或 "Scan")
    ///   - date: 建立時間
    ///   - extension: 副檔名 (如 "pdf" 或 "jpg")
    /// - Returns: 格式化後之檔名 (如 "涓建築_20261030_0905.pdf")
    public static func generateName(prefix: String? = nil, date: Date = Date(), ext: String = "pdf") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: date)

        let safePrefix: String
        if let p = prefix?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            safePrefix = p
        } else {
            safePrefix = "Scan"
        }

        return "\(safePrefix)_\(timestamp).\(ext)"
    }
}
