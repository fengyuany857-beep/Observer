#include <metal_stdlib>
using namespace metal;

// Observer Static Topology Prototype
//
// Procedural contour-field prototype for Observer UI V2.
// The visual model is intentionally non-authoritative: it receives no runtime,
// health, connection, approval, job, or operation state.
//
// Noise/contour approach adapted conceptually from idleCyrex/topolines
// (MIT) and the Ashima Arts / Stefan Gustavson simplex-noise lineage (MIT).
// SwiftUI shader integration follows Apple's stitchable shader model and was
// cross-checked against twostraws/Inferno examples (MIT).
//
// This V1 is static by design. There is no time input and no scroll input.

// MARK: - Ashima-style 2D simplex helpers

inline float2 observer_mod289(float2 x) {
    return x - floor(x * (1.0f / 289.0f)) * 289.0f;
}

inline float3 observer_mod289(float3 x) {
    return x - floor(x * (1.0f / 289.0f)) * 289.0f;
}

inline float3 observer_permute(float3 x) {
    return observer_mod289(((x * 34.0f) + 1.0f) * x);
}

inline float observer_simplex2D(float2 v) {
    const float4 C = float4(
        0.211324865405187f,   // (3 - sqrt(3)) / 6
        0.366025403784439f,   // 0.5 * (sqrt(3) - 1)
       -0.577350269189626f,   // -1 + 2 * C.x
        0.024390243902439f    // 1 / 41
    );

    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);

    float2 i1 = (x0.x > x0.y) ? float2(1.0f, 0.0f) : float2(0.0f, 1.0f);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;

    i = observer_mod289(i);
    float3 p = observer_permute(
        observer_permute(i.y + float3(0.0f, i1.y, 1.0f))
        + i.x + float3(0.0f, i1.x, 1.0f)
    );

    float3 m = max(
        0.5f - float3(
            dot(x0, x0),
            dot(x12.xy, x12.xy),
            dot(x12.zw, x12.zw)
        ),
        0.0f
    );

    m = m * m;
    m = m * m;

    float3 x = 2.0f * fract(p * C.www) - 1.0f;
    float3 h = abs(x) - 0.5f;
    float3 ox = floor(x + 0.5f);
    float3 a0 = x - ox;

    m *= 1.79284291400159f - 0.85373472095314f * (a0 * a0 + h * h);

    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x12.x + h.y * x12.y;
    g.z = a0.z * x12.z + h.z * x12.w;

    return 130.0f * dot(m, g);
}

inline float observer_fbm2(float2 p) {
    // Intentionally only two octaves for the first mobile prototype.
    float n0 = observer_simplex2D(p);
    float n1 = observer_simplex2D(p * 2.03f + float2(7.13f, -3.71f));
    return (n0 + 0.5f * n1) / 1.5f;
}

inline float observer_contourLine(float value, float width) {
    float phase = fract(value);
    float distanceToLevel = min(phase, 1.0f - phase);
    return 1.0f - smoothstep(0.0f, max(width, 0.0001f), distanceToLevel);
}

// MARK: - SwiftUI stitchable entry point

[[ stitchable ]] half4 observerStaticTopology(
    float2 position,
    half4 currentColor,
    float2 size,
    float seedX,
    float seedY,
    float scale,
    float levels,
    float warp,
    float minorLineWidth,
    float majorLineWidth,
    float minorOpacity,
    float majorOpacity,
    float majorEvery,
    half4 minorColor,
    half4 majorColor
) {
    float shortest = max(min(size.x, size.y), 1.0f);
    float2 centered = (position - size * 0.5f) / shortest;

    float2 seed = float2(seedX, seedY);
    float2 p = centered * max(scale, 0.001f) + seed;

    // Stable domain warp. No time component: geometry must not morph in V1.
    float qx = observer_fbm2(p + float2(5.2f, 1.3f));
    float qy = observer_fbm2(p + float2(-2.8f, 8.3f));
    p += float2(qx, qy) * warp;

    float height = observer_fbm2(p);
    height = clamp(height * 0.5f + 0.5f, 0.0f, 1.0f);

    float contourCoordinate = height * max(levels, 1.0f);
    float minor = observer_contourLine(contourCoordinate, minorLineWidth);

    float safeMajorEvery = max(majorEvery, 1.0f);
    float majorCoordinate = contourCoordinate / safeMajorEvery;
    float major = observer_contourLine(majorCoordinate, majorLineWidth);

    half3 result = currentColor.rgb;
    result = mix(result, minorColor.rgb, half(clamp(minor * minorOpacity, 0.0f, 1.0f)));
    result = mix(result, majorColor.rgb, half(clamp(major * majorOpacity, 0.0f, 1.0f)));

    return half4(result, currentColor.a);
}
