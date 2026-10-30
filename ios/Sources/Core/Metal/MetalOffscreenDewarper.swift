import Foundation
import Metal
import CoreGraphics
import simd

#if canImport(UIKit)
import UIKit

/// 負責在靜態拍照後，透過 Metal GPU 離屏運算 (Offscreen Rendering) 將拍攝之高畫質影像
/// 依據 25x25 自由曲面網格展平拉直。
public final class MetalOffscreenDewarper: @unchecked Sendable {
    public static let shared = MetalOffscreenDewarper()

    /// 輸出尺寸上限，避免異常網格造成巨型配置而 OOM
    private static let maxOutputDimension = 8192
    private static let maxOutputPixels = 16_000_000

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private let meshBuilder = DewarpMesh()

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            self.device = nil
            self.commandQueue = nil
            return
        }
        self.device = dev
        self.commandQueue = queue
        setupPipeline()
    }

    private func setupPipeline() {
        guard let device = self.device,
              let library = MetalLibraryProvider.makeLibrary(device: device),
              let vertexFunc = library.makeFunction(name: "dewarpVertexShader"),
              let fragmentFunc = library.makeFunction(name: "dewarpFragmentShader") else {
            print("[MetalOffscreenDewarper] 無法載入 Metal 著色器")
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[MetalOffscreenDewarper] Pipeline 建立失敗: \(error)")
        }
    }

    /// 使用 Metal GPU 將輸入之 UIImage 依據 25x25 網格拓撲進行硬體加速展平 (Dewarping)
    /// - Parameters:
    ///   - image: 原始或透視拉正後之影像
    ///   - curvedGrid: 625 個 SIMD2<Float> 自由曲面網格座標；**必須提供真實模型輸出**才會展平。
    ///   - dewarpStrength: 展平拉直強度 (0.0: 原樣, 1.0: 完整展平)
    /// - Returns: GPU 離屏渲染展開後之高畫質 UIImage；若無有效網格則原樣回傳。
    public func dewarpImage(
        image: UIImage,
        curvedGrid: [SIMD2<Float>]? = nil,
        dewarpStrength: Float = 1.0
    ) -> UIImage? {
        // 沒有真實的 25x25 曲面網格時直接回傳原圖。
        // 早期版本會在此合成正弦曲面，會把正常照片扭成波浪狀並持續破壞輸出，
        // 此「合成假曲面」行為已移除；展平必須依賴真實模型推論結果。
        guard let grid = curvedGrid, grid.count == DewarpGeometry.totalPoints else {
            return image
        }

        guard let device = self.device,
              let commandQueue = self.commandQueue,
              let pipelineState = self.pipelineState,
              let cgImage = Self.normalizedCGImage(image) else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        // 1. 依據 25 條橫向弧長微分積分，計算展平後之最佳物理像素尺寸
        let outputSize = DewarpGeometry.calculateOutputSize(
            points: grid,
            inputWidth: width,
            aspectRatio: Float(height) / Float(max(width, 1))
        )
        var outWidth = outputSize.width > 0 ? outputSize.width : width
        var outHeight = outputSize.height > 0 ? outputSize.height : height
        Self.clampOutputSize(width: &outWidth, height: &outHeight)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // 2. 建立輸入 MTLTexture（以安全配置的緩衝區繪製，避免 `CGContext(data: &array)` 的懸空指標）
        let inTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        inTexDesc.usage = [.shaderRead]
        inTexDesc.storageMode = .shared
        guard let inTexture = device.makeTexture(descriptor: inTexDesc) else { return image }

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { rawPointer.deallocate() }

        guard let context = CGContext(
            data: rawPointer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        inTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: rawPointer,
            bytesPerRow: bytesPerRow
        )

        // 3. 建立輸出目標 MTLTexture
        let outTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: outWidth,
            height: outHeight,
            mipmapped: false
        )
        outTexDesc.usage = [.renderTarget, .shaderRead]
        outTexDesc.storageMode = .shared
        guard let outTexture = device.makeTexture(descriptor: outTexDesc) else { return image }

        // 4. 構建頂點與索引緩衝區
        let vertices = meshBuilder.generateVertices(from: grid)
        let vertexBufferSize = vertices.count * MemoryLayout<DewarpVertexData>.stride
        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertexBufferSize, options: .storageModeShared) else {
            return image
        }

        let indices = meshBuilder.generateIndices()
        guard let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else { return image }

        // 離屏模式不可套用 Aspect-Fill：viewportSize 設為 0 讓片段著色器停用該段映射
        var uniforms = DewarpUniforms(
            viewportSize: SIMD2<Float>(0, 0),
            dewarpStrength: dewarpStrength,
            edgeFeather: 0.0,
            renderMode: 0
        )

        // 5. 執行 GPU 離屏渲染
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = outTexture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            return image
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DewarpUniforms>.stride, index: 1)
        encoder.setFragmentTexture(inTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DewarpUniforms>.stride, index: 1)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indices.count,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )

        encoder.endEncoding()
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        guard cmdBuffer.error == nil else { return image }

        // 6. 將輸出 MTLTexture 讀回轉為高畫質 UIImage
        let outBytesPerRow = outWidth * 4
        var outBytes = [UInt8](repeating: 0, count: outBytesPerRow * outHeight)
        outBytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            outTexture.getBytes(
                base,
                bytesPerRow: outBytesPerRow,
                from: MTLRegionMake2D(0, 0, outWidth, outHeight),
                mipmapLevel: 0
            )
        }

        guard let outProvider = CGDataProvider(data: Data(outBytes) as CFData),
              let outCG = CGImage(
                  width: outWidth,
                  height: outHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: outBytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: outProvider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return image
        }

        return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
    }

    // MARK: - Helpers

    /// 將輸出尺寸限制在安全範圍內，維持長寬比
    private static func clampOutputSize(width: inout Int, height: inout Int) {
        width = max(1, width)
        height = max(1, height)

        let dimensionScale = min(
            1.0,
            CGFloat(maxOutputDimension) / CGFloat(max(width, height))
        )
        if dimensionScale < 1.0 {
            width = max(1, Int(CGFloat(width) * dimensionScale))
            height = max(1, Int(CGFloat(height) * dimensionScale))
        }

        let pixelScale = min(
            1.0,
            sqrt(CGFloat(maxOutputPixels) / CGFloat(max(width * height, 1)))
        )
        if pixelScale < 1.0 {
            width = max(1, Int(CGFloat(width) * pixelScale))
            height = max(1, Int(CGFloat(height) * pixelScale))
        }
    }

    /// 將任意方向的 UIImage 正規化為 `.up` 的 CGImage，避免裁剪與展平出現旋轉錯位
    static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalized.cgImage
    }
}
#endif
