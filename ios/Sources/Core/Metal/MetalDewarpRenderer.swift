import Foundation
import Metal
import MetalKit
import CoreVideo
import simd

#if canImport(UIKit)
import UIKit
#endif

/// 負責透過 Metal GPU 即時渲染 25x25 幾何網格並將相機影格展平重採樣之渲染器
public final class MetalDewarpRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    // 零拷貝紋理快取 (Zero-copy CoreVideo Texture Cache)
    private var textureCache: CVMetalTextureCache?
    /// 保留 CVMetalTexture 參照，確保 MTLTexture 在 GPU 使用期間仍有效
    private var currentCVTexture: CVMetalTexture?
    private var currentTexture: MTLTexture?

    // 著色器全域參數
    private var uniforms = DewarpUniforms(
        viewportSize: SIMD2<Float>(1.0, 1.0),
        dewarpStrength: 0.0,
        edgeFeather: 0.02,
        renderMode: 0
    )

    private let meshBuilder = DewarpMesh()
    private let lock = NSLock()

    public init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        super.init()

        metalView.device = device
        metalView.delegate = self
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 1)

        // 真正啟用 60fps 預覽（實際上限仍由裝置與相機格式決定）
        #if canImport(UIKit)
        metalView.preferredFramesPerSecond = min(60, UIScreen.main.maximumFramesPerSecond)
        #else
        metalView.preferredFramesPerSecond = 60
        #endif

        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            print("[MetalDewarpRenderer] CVMetalTextureCache 建立失敗: \(status)")
        }

        setupPipeline()
        setupDefaultMesh()
    }

    deinit {
        if let textureCache = textureCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
    }

    private func setupPipeline() {
        guard let library = MetalLibraryProvider.makeLibrary(device: device),
              let vertexFunction = library.makeFunction(name: "dewarpVertexShader"),
              let fragmentFunction = library.makeFunction(name: "dewarpFragmentShader") else {
            print("[MetalDewarpRenderer] 無法載入 Metal 著色器函式")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "vFlat.DewarpPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // 啟用透明度混合（邊緣羽化用）
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[MetalDewarpRenderer] 建立 RenderPipelineState 失敗: \(error)")
        }
    }

    private func setupDefaultMesh() {
        let flatGrid = DewarpGeometry.makeFlatGrid()
        updateMesh(with: flatGrid)

        let indices = meshBuilder.generateIndices()
        self.indexCount = indices.count
        self.indexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )
    }

    /// 更新 25x25 彎曲網格節點座標 (觸發即時幾何變形)
    public func updateMesh(with curvedPoints: [SIMD2<Float>]) {
        let vertices = meshBuilder.generateVertices(from: curvedPoints)
        let bufferSize = vertices.count * MemoryLayout<DewarpVertexData>.stride
        guard bufferSize > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        if let existingBuffer = vertexBuffer, existingBuffer.length == bufferSize {
            existingBuffer.contents().copyMemory(from: vertices, byteCount: bufferSize)
        } else {
            self.vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: bufferSize,
                options: .storageModeShared
            )
        }
    }

    /// 接收來自相機的 CVPixelBuffer 影格，透過硬體快取進行零拷貝映射至 MTLTexture
    public func feedFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let textureCache = self.textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )

        // 建立失敗時才 flush 快取並重試一次，避免每幀 flush 造成 60fps 下的 CPU 開銷
        var finalStatus = status
        var finalTexture = cvMetalTexture
        if finalStatus != kCVReturnSuccess || finalTexture == nil {
            CVMetalTextureCacheFlush(textureCache, 0)
            var retryTexture: CVMetalTexture?
            finalStatus = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &retryTexture
            )
            finalTexture = retryTexture
        }

        guard finalStatus == kCVReturnSuccess,
              let cvTexture = finalTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return }

        lock.lock()
        self.currentCVTexture = cvTexture
        self.currentTexture = texture
        lock.unlock()
    }

    /// 設定展平強度與渲染模式 (0: 原圖, 1: 展平)
    public func setDewarpStrength(_ strength: Float, mode: Int = 1) {
        lock.lock()
        uniforms.dewarpStrength = strength
        uniforms.renderMode = Int32(mode)
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lock.lock()
        uniforms.viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        lock.unlock()
    }

    public func draw(in view: MTKView) {
        guard let pipelineState = self.pipelineState else { return }

        // 只在鎖內複製參照，避免把整個 GPU 編碼流程都鎖住
        lock.lock()
        let vertexBuffer = self.vertexBuffer
        let indexBuffer = self.indexBuffer
        let texture = self.currentTexture
        let currentUniforms = self.uniforms
        let currentIndexCount = self.indexCount
        lock.unlock()

        guard let vertexBuffer = vertexBuffer,
              let indexBuffer = indexBuffer,
              let texture = texture,
              currentIndexCount > 0,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        var uniformsToUse = currentUniforms

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&uniformsToUse, length: MemoryLayout<DewarpUniforms>.stride, index: 1)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentBytes(&uniformsToUse, length: MemoryLayout<DewarpUniforms>.stride, index: 1)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: currentIndexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
