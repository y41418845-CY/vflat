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

    out.position = float4(v.position.x, v.position.y, 0.0, 1.0);

    // 依 dewarpStrength 在「1:1 直通對應」與「25x25 曲面網格對應」之間混合：
    // strength = 0.0 時取 NDC 反推的平直 UV（畫面完全不變形）
    // strength = 1.0 時完整使用網格控制點 UV（曲面展平）
    float2 flatUV = float2((v.position.x + 1.0) * 0.5, (1.0 - v.position.y) * 0.5);
    float strength = clamp(uniforms.dewarpStrength, 0.0, 1.0);
    out.texCoord = mix(flatUV, v.texCoord, strength);

    return out;
}

// 片段著色器：以高品質雙線性採樣將相機紋理重對齊至展平後的網格
fragment float4 dewarpFragmentShader(
    RasterizerData in [[stage_in]],
    texture2d<float, access::sample> colorTexture [[texture(0)]],
    constant DewarpUniforms &uniforms [[buffer(1)]]
) {
    // 建立雙線性濾波採樣器，超出邊緣以邊緣顏色夾取
    constexpr sampler textureSampler(
        coord::normalized,
        filter::linear,
        address::clamp_to_edge
    );

    float2 sampleUV = in.texCoord;

    // 啟用 1:1 原生 Aspect-Fill 比例映射，防止畫面被拉長拉扁，並與 ScanGuideOverlay 座標系 100% 精準對齊
    // （離屏展平會將 viewportSize 設為 0 以停用此段）
    if (uniforms.viewportSize.x > 0.0 && uniforms.viewportSize.y > 0.0) {
        float viewAspect = uniforms.viewportSize.x / uniforms.viewportSize.y;
        float texAspect = float(colorTexture.get_width()) / float(colorTexture.get_height());
        if (viewAspect < texAspect) {
            float scale = viewAspect / texAspect;
            sampleUV.x = (sampleUV.x - 0.5) * scale + 0.5;
        } else if (viewAspect > texAspect) {
            float scale = texAspect / viewAspect;
            sampleUV.y = (sampleUV.y - 0.5) * scale + 0.5;
        }
    }

    // 採樣相機原始影格紋理
    float4 color = colorTexture.sample(textureSampler, sampleUV);

    // 模式 1：開啟展平增強，執行邊緣羽化
    if (uniforms.renderMode == 1) {
        float edgeDistX = min(in.texCoord.x, 1.0 - in.texCoord.x);
        float edgeDistY = min(in.texCoord.y, 1.0 - in.texCoord.y);
        float feather = max(uniforms.edgeFeather, 0.0001);
        float edgeAlpha = smoothstep(0.0, feather, min(edgeDistX, edgeDistY));
        color.a *= edgeAlpha;
    }

    return color;
}
