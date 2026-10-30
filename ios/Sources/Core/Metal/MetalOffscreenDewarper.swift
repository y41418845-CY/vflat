import Foundation
import Metal
import CoreGraphics
import simd

#if canImport(UIKit)
import UIKit

/// 負責在靜態拍照後，透過 Metal GPU 離屏運算 (Offscreen Rendering) 將拍攝之高畫質影像依據 25x25 自由曲面網格真實展平拉直
public final class MetalOffscreenDewarper {
    public static let shared = MetalOffscreenDewarper()

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
        guard let device = self.device else { return }

        let library: MTLLibrary?
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else if let bundleLib = try? device.makeDefaultLibrary(bundle: Bundle.main) {
            library = bundleLib
        } else {
            library = nil
        }

        guard let lib = library,
              let vertexFunc = lib.makeFunction(name: "dewarpVertexShader"),
              let fragmentFunc = lib.makeFunction(name: "dewarpFragmentShader") else {
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
    ///   - curvedGrid: 625 個 SIMD2<Float> 自由曲面網格座標 (若為 nil 則自動依弧長分析自適應建立展開網格)
    ///   - dewarpStrength: 展平拉直強度 (0.0: 原樣, 1.0: 完整展平)
    /// - Returns: GPU 離屏渲染展開後之高畫質 UIImage
    public func dewarpImage(
        image: UIImage,
        curvedGrid: [SIMD2<Float>]? = nil,
        dewarpStrength: Float = 1.0
    ) -> UIImage? {
        guard let device = self.device,
              let commandQueue = self.commandQueue,
              let pipelineState = self.pipelineState,
              let cgImage = image.cgImage else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height

        // 1. 建立或採用 25x25 展平網格 (若無特定模型輸出，依據書本物理曲率自適應展開)
        let grid: [SIMD2<Float>]
        if let custom = curvedGrid, custom.count == DewarpGeometry.totalPoints {
            grid = custom
        } else {
            // 自動估算微曲率網格以修正中縫彎曲
            grid = DewarpGeometry.makeCurvedGrid(curvature: 0.12 * dewarpStrength)
        }

        // 2. 依據 25 條橫向弧長微分積分，計算展平後之最佳物理像素尺寸
        let outputSize = DewarpGeometry.calculateOutputSize(
            points: grid,
            inputWidth: width,
            aspectRatio: Float(height) / Float(max(width, 1))
        )
        let outWidth = outputSize.width > 0 ? outputSize.width : width
        let outHeight = outputSize.height > 0 ? outputSize.height : height

        // 3. 建立輸入 MTLTexture
        let inTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        inTexDesc.usage = [.shaderRead]
        guard let inTexture = device.makeTexture(descriptor: inTexDesc) else { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var rawData = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        inTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: rawData,
            bytesPerRow: bytesPerRow
        )

        // 4. 建立輸出目標 MTLTexture
        let outTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: outWidth,
            height: outHeight,
            mipmapped: false
        )
        outTexDesc.usage = [.renderTarget, .shaderRead]
        guard let outTexture = device.makeTexture(descriptor: outTexDesc) else { return image }

        // 5. 構建頂點與索引緩衝區
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

        var uniforms = DewarpUniforms(
            viewportSize: SIMD2<Float>(Float(outWidth), Float(outHeight)),
            dewarpStrength: dewarpStrength,
            edgeFeather: 0.005,
            renderMode: 0 // 靜態照片離屏拉直模式 (無黑框羽化)
        )

        // 6. 執行 GPU 離屏渲染
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

        // 7. 將輸出 MTLTexture 讀回轉為高畫質 UIImage
        var outBytes = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        outTexture.getBytes(
            &outBytes,
            bytesPerRow: outWidth * 4,
            from: MTLRegionMake2D(0, 0, outWidth, outHeight),
            mipmapLevel: 0
        )

        guard let outProvider = CGDataProvider(data: Data(outBytes) as CFData),
              let outCG = CGImage(
                  width: outWidth,
                  height: outHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: outWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: outProvider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return image
        }

        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }
}
#endif
