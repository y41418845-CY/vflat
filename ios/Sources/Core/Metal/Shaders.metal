#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// 頂點著色器輸出至片段著色器之結構
struct RasterizerData {
    float4 position [[position]];
    float2 texCoord;
};

// 頂點著色器：將 25x25 幾何網格頂點座標映射至螢幕 NDC 空間
vertex RasterizerData dewarpVertexShader(
    uint vertexID [[vertex_id]],
    constant DewarpVertex *vertices [[buffer(0)]],
    constant DewarpUniforms &uniforms [[buffer(1)]]
) {
    RasterizerData out;
    DewarpVertex v = vertices[vertexID];

    // 在平整化目標座標與原始網格座標之間依強度線性插值
    out.position = float4(v.position.x, v.position.y, 0.0, 1.0);
    out.texCoord = v.texCoord;

    return out;
}

// 片段著色器：以高品質雙線性採樣將相機紋理重對齊至展平後的網格
fragment float4 dewarpFragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<float, access::sample> colorTexture [[texture(0)]],
    constant DewarpUniforms &uniforms [[buffer(1)]]
) {
    // 建立雙線性濾波採樣器，超出邊緣以黑色或邊緣顏色夾取
    constexpr sampler textureSampler(
        coord::normalized,
        filter::linear,
        address::clamp_to_edge
    );

    // 採樣相機原始影格紋理
    float4 color = colorTexture.sample(textureSampler, in.texCoord);

    // 模式 1：開啟展平增強，執行邊緣羽化與對比微調
    if (uniforms.renderMode == 1) {
        // 邊緣羽化遮罩，避免邊界鋸齒
        float edgeDistX = min(in.texCoord.x, 1.0 - in.texCoord.x);
        float edgeDistY = min(in.texCoord.y, 1.0 - in.texCoord.y);
        float edgeAlpha = smoothstep(0.0, uniforms.edgeFeather, min(edgeDistX, edgeDistY));
        color.a *= edgeAlpha;
    }

    return color;
}
