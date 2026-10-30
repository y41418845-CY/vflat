import Foundation

/// Metal 著色器的執行期原始碼（`MetalLibraryProvider` 的最後手段）。
///
/// 這裡刻意不 `#include "ShaderTypes.h"`，改為內嵌等價結構定義，
/// 因為 `makeLibrary(source:)` 不會經過 Xcode 的標頭搜尋路徑。
/// **修改 `Shaders.metal` 或 `ShaderTypes.h` 時，必須同步更新本字串。**
enum MetalShaderSource {
    static let deviceSource: String = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct DewarpVertex {
        float2 position;
        float2 texCoord;
    };

    struct DewarpUniforms {
        float2 viewportSize;
        float dewarpStrength;
        float edgeFeather;
        int renderMode;
        int _padding;
    };

    struct RasterizerData {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex RasterizerData dewarpVertexShader(
        uint vertexID [[vertex_id]],
        constant DewarpVertex *vertices [[buffer(0)]],
        constant DewarpUniforms &uniforms [[buffer(1)]]
    ) {
        RasterizerData out;
        DewarpVertex v = vertices[vertexID];

        out.position = float4(v.position.x, v.position.y, 0.0, 1.0);

        // 依 dewarpStrength 在「1:1 直通對應」與「25x25 曲面網格對應」之間混合
        float2 flatUV = float2((v.position.x + 1.0) * 0.5, (1.0 - v.position.y) * 0.5);
        float strength = clamp(uniforms.dewarpStrength, 0.0, 1.0);
        out.texCoord = mix(flatUV, v.texCoord, strength);

        return out;
    }

    fragment float4 dewarpFragmentShader(
        RasterizerData in [[stage_in]],
        texture2d<float, access::sample> colorTexture [[texture(0)]],
        constant DewarpUniforms &uniforms [[buffer(1)]]
    ) {
        constexpr sampler textureSampler(
            coord::normalized,
            filter::linear,
            address::clamp_to_edge
        );

        float2 sampleUV = in.texCoord;

        // Aspect-Fill 比例映射（離屏模式會把 viewportSize 設為 0 以停用）
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

        float4 color = colorTexture.sample(textureSampler, sampleUV);

        if (uniforms.renderMode == 1) {
            float edgeDistX = min(in.texCoord.x, 1.0 - in.texCoord.x);
            float edgeDistY = min(in.texCoord.y, 1.0 - in.texCoord.y);
            float feather = max(uniforms.edgeFeather, 0.0001);
            float edgeAlpha = smoothstep(0.0, feather, min(edgeDistX, edgeDistY));
            color.a *= edgeAlpha;
        }

        return color;
    }
    """#
}
