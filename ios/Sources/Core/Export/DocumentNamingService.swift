import Foundation

final class DocumentNamingService {
    static func defaultName(folder: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "\(folder)_\(formatter.string(from: Date()))"
    }
}
