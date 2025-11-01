#include <metal_stdlib>

using namespace metal;

#define MAX_POINTS 20
#define MAX_POINTS_BUFFER 190 // This is calculated by (0..<MAX_POINTS).map { $0 }.reduce(0, +)

struct Env {
    float2 canvasSize;
    uint32_t vertexCount;
    uint32_t lastVertexIndex;
    uint32_t controlPointsCount;
};

float lerpf(float p1, float p2, float t) {
    return (p2 - p1) * t + p1;
}

float2 lerp(float2 p1, float2 p2, float t) {
    return float2(
                  lerpf(p1.x, p2.x, t),
                  lerpf(p1.y, p2.y, t)
                  );
}

float2 getPointInCurve(
                       constant Env* env,
                       constant float2* controlPoints,
                       float t
                       ) {
    
    float2 interpolation_buffer[MAX_POINTS_BUFFER];
    for (uint i = 0; i < env->controlPointsCount - 1; i++) {
        float2 p1 = controlPoints[i];
        float2 p2 = controlPoints[i + 1];
        float2 interpolatedPoint = lerp(p1, p2, t);
        
        interpolation_buffer[i] = interpolatedPoint;
    }
    
    uint interpolationPoints = env->controlPointsCount - 1;
    uint previousPageStart = 0;
    uint pageStart = env->controlPointsCount - 1;

    while (interpolationPoints > 1) {
        
        for (uint i = 0; i < interpolationPoints - 1; i++) {
            float2 p1 = interpolation_buffer[previousPageStart + i];
            float2 p2 = interpolation_buffer[previousPageStart + i + 1];
            float2 interpolatedPoint = lerp(p1, p2, t);
            
            interpolation_buffer[pageStart + i] = interpolatedPoint;
        }
        
        previousPageStart = pageStart;
        pageStart += interpolationPoints - 1;
        interpolationPoints -= 1;
    }
    
    float2 pointInTheCurve = interpolation_buffer[previousPageStart];
    
    return pointInTheCurve;
}

struct VertexOut {
    float4 pos [[position]];
    float t;
};

[[vertex]]
VertexOut calculateVertex(
                       constant Env* env [[buffer(0)]],
                       constant float2* controlPoints[[buffer(1)]],
                       uint vertexId[[vertex_id]]
) {
    float t = (float)vertexId / (float)env->lastVertexIndex;
    
    float2 pointInCurve = getPointInCurve(env, controlPoints, t);
    
    VertexOut res;
    res.pos.xy = pointInCurve;
    res.pos.zw = {0, 1};
    res.t = t;
    
    return res;
}

[[fragment]]
half4 calculateFragment(VertexOut v [[stage_in]]) {
    float multiplier = 0.5 * v.t + 0.5;
    
    return half4(0.5 * multiplier, 0.9 * multiplier, 0.8 * multiplier, 1);
}
