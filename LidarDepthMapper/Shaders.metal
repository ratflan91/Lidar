#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Must match DepthMapRenderer.Uniforms exactly.
struct Uniforms {
    int   mode;
    float maxDepth;
    float alpha;
    float contourInterval;
    float4x4 displayTransform;
};

// ---------------------------------------------------------------------------
// Vertex shader
// Each vertex in the buffer is packed as (clipX, clipY, uvX, uvY).
// ---------------------------------------------------------------------------

vertex VertexOut vertexPassthrough(
    uint vid               [[vertex_id]],
    constant float4 *verts [[buffer(0)]]
) {
    VertexOut out;
    float4 v      = verts[vid];
    out.position  = float4(v.xy, 0.0, 1.0);
    out.uv        = v.zw;
    return out;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// BT.601 full-range YCbCr → linear RGB
float3 ycbcrToRgb(float y, float2 cbcr) {
    float cb = cbcr.x - 0.5;
    float cr = cbcr.y - 0.5;
    return saturate(float3(
        y               + 1.40200 * cr,
        y - 0.34414 * cb - 0.71414 * cr,
        y + 1.77200 * cb
    ));
}

// 5-stop topographic color ramp: red (near) → orange → yellow → green → blue (far)
float4 depthColor(float depth, float maxDepth) {
    float t = saturate(depth / maxDepth);

    const float3 stops[5] = {
        float3(0.90, 0.12, 0.10),   // red
        float3(1.00, 0.55, 0.00),   // orange
        float3(0.95, 0.95, 0.08),   // yellow
        float3(0.10, 0.78, 0.28),   // green
        float3(0.08, 0.28, 0.92),   // blue
    };

    float s = t * 4.0;
    int   i = clamp(int(s), 0, 3);
    float f = fract(s);
    return float4(mix(stops[i], stops[i + 1], f), 1.0);
}

// Returns 1.0 on contour band edges, 0.0 elsewhere (smooth).
float contourEdge(float depth, float interval) {
    float f = fract(depth / interval);
    float w = 0.06;
    return saturate(
        smoothstep(w, 0.0, f) + smoothstep(1.0 - w, 1.0, f)
    );
}

// ---------------------------------------------------------------------------
// Fragment shader
// ---------------------------------------------------------------------------

fragment float4 fragmentDepthMap(
    VertexOut                           in         [[stage_in]],
    texture2d<float, access::sample>    texY       [[texture(0)]],
    texture2d<float, access::sample>    texCbCr    [[texture(1)]],
    texture2d<float, access::sample>    texDepth   [[texture(2)]],
    constant Uniforms                  &u          [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    // Apply ARKit display transform to orient camera UVs for portrait mode.
    float2 camUV = (u.displayTransform * float4(in.uv, 0.0, 1.0)).xy;

    float  y    = texY.sample(s, camUV).r;
    float2 cbcr = texCbCr.sample(s, camUV).rg;
    float4 camera = float4(ycbcrToRgb(y, cbcr), 1.0);

    // Camera-only mode
    if (u.mode == 3) return camera;

    // Depth uses the same display-transformed UV as the camera
    // (LiDAR and camera are co-registered in ARKit).
    float depth = texDepth.sample(s, camUV).r;

    bool valid = depth > 0.05 && depth < u.maxDepth
                 && !isnan(depth) && !isinf(depth);
    if (!valid) return camera;

    float4 dc   = depthColor(depth, u.maxDepth);
    float  edge = contourEdge(depth, u.contourInterval);

    if (u.mode == 0) {
        // Gradient overlay
        return mix(camera, dc, u.alpha);
    }

    if (u.mode == 1) {
        // Contour lines over faint band tint
        float4 base = mix(camera, dc, 0.22);
        return mix(base, float4(0, 0, 0, 1), edge);
    }

    // Combined (mode == 2): gradient + contour lines
    float4 blended = mix(camera, dc, u.alpha);
    return mix(blended, float4(0, 0, 0, 1), edge * 0.9);
}
