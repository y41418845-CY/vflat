import Foundation
import Metal

/// 統一解析 Metal 函式庫。
///
/// 本專案同時支援兩種建置路徑：
/// 1. **XcodeGen / Xcode 專案**：`Shaders.metal` 會被編譯成 App Bundle 內的 `default.metallib`。
/// 2. **Swift Package Manager**：`.metal` 以資源方式打包，可能落在資源 bundle 而非主 bundle。
///
/// 舊版只呼叫 `device.makeDefaultLibrary()`，在部分建置路徑下會取不到函式，
/// 導致預覽與離屏展平靜默失效（畫面全黑但沒有任何錯誤）。此處加入：
/// - 逐一掃描所有已載入的 bundle 尋找 `default.metallib`
/// - 最後手段：以執行期原始碼編譯（`MetalShaderSource`）
enum MetalLibraryProvider {
    static func makeLibrary(device: MTLDevice) -> MTLLibrary? {
        if let library = device.makeDefaultLibrary() {
            return library
        }

        for bundle in candidateBundles() {
            if let library = try? device.makeDefaultLibrary(bundle: bundle) {
                return library
            }
        }

        do {
            return try device.makeLibrary(source: MetalShaderSource.deviceSource, options: nil)
        } catch {
            print("[MetalLibraryProvider] 執行期著色器編譯失敗: \(error)")
            return nil
        }
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main, Bundle(for: BundleToken.self)]
        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(contentsOf: Bundle.allFrameworks)
        return bundles
    }

    /// 用於取得本檔案所屬 bundle 的錨點型別
    private final class BundleToken {}
}
