#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/// 傳遞給 Metal 著色器之單一頂點結構
typedef struct {
    // 歸一化裝置座標 (NDC: -1.0 .. 1.0)
    vector_float2 position;
    // 相機影格紋理座標 (UV: 0.0 .. 1.0)
    vector_float2 texCoord;
} DewarpVertex;

/// 傳遞給 Metal 著色器之全域常數參數
typedef struct {
    // 渲染畫布長寬比
    vector_float2 viewportSize;
    // 網格變形強度 (0.0: 無變形, 1.0: 完整展平)
    float dewarpStrength;
    // 邊緣微調參數
    float edgeFeather;
    // 模式：0 為相機原圖直通，1 為 25x25 幾何網格展平
    int renderMode;
    // 8 位元組對齊填充
    int _padding;
} DewarpUniforms;

#endif /* ShaderTypes_h */
