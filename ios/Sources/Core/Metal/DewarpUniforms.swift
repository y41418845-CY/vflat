import Foundation
import simd

/// 供 Swift 與 Metal 著色器共用之全域常數參數 (與 Shaders.metal 保持二進位記憶體佈局一致)
public struct DewarpUniforms {
    /// 渲染畫布大小 (寬度, 高度)
    public var viewportSize: SIMD2<Float>
    /// 網格變形強度 (0.0: 無變形, 1.0: 完整展平)
    public var dewarpStrength: Float
    /// 邊緣羽化微調參數
    public var edgeFeather: Float
    /// 渲染模式：0 為相機原圖直通，1 為 25x25 幾何網格展平
    public var renderMode: Int32
    /// 8 位元組記憶體對齊填充
    public var _padding: Int32

    public init(
        viewportSize: SIMD2<Float>,
        dewarpStrength: Float,
        edgeFeather: Float,
        renderMode: Int32
    ) {
        self.viewportSize = viewportSize
        self.dewarpStrength = dewarpStrength
        self.edgeFeather = edgeFeather
        self.renderMode = renderMode
        self._padding = 0
    }
}
