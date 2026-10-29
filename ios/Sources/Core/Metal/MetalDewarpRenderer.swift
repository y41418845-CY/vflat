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
    private var currentTexture: MTLTexture?

    // 著色器全域參數
    private var uniforms = DewarpUniforms(
        viewportSize: SIMD2<Float>(1.0, 1.0),
        dewarpStrength: 1.0,
        edgeFeather: 0.02,
        renderMode: 1
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

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        setupPipeline()
        setupDefaultMesh()
    }

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("[MetalDewarpRenderer] 無法載入預設 Metal Library，請確認 Shaders.metal 已包含在專案中")
            return
        }

        let vertexFunction = library.makeFunction(name: "dewarpVertexShader")
        let fragmentFunction = library.makeFunction(name: "dewarpFragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "vFlat.DewarpPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // 啟用透明度混合
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
        // 預設載入平整網格
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

        if status == kCVReturnSuccess, let cvMetalTexture = cvMetalTexture {
            lock.lock()
            self.currentTexture = CVMetalTextureGetTexture(cvMetalTexture)
            lock.unlock()
        }
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
        lock.lock()
        guard let pipelineState = self.pipelineState,
              let vertexBuffer = self.vertexBuffer,
              let indexBuffer = self.indexBuffer,
              let texture = self.currentTexture,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            lock.unlock()
            return
        }

        var currentUniforms = uniforms
        lock.unlock()

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&currentUniforms, length: MemoryLayout<DewarpUniforms>.stride, index: 1)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentBytes(&currentUniforms, length: MemoryLayout<DewarpUniforms>.stride, index: 1)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
