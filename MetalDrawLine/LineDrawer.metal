#include <metal_stdlib>

using namespace metal;

#define MAX_POINTS 20
#define MAX_POINTS_BUFFER 190 // This is calculated by (0..<MAX_POINTS).map { $0 }.reduce(0, +)

struct Env {
    float2 canvasSize;
    uint32_t vertexCount;
    uint32_t controlPointsCount;
    float strokeHalfWidth;
};

template <typename T>
T lerp(T p1, T p2, T t) {
    return (p2 - p1) * t + p1;
}

half4 lerp(half4 c1, half4 c2, half t) {
    return half4(
                 lerp(c1[0], c2[0], t),
                 lerp(c1[1], c2[1], t),
                 lerp(c1[2], c2[2], t),
                 lerp(c1[3], c2[3], t)
                 );
}

float2 lerp(float2 p1, float2 p2, float t) {
    return float2(
                  lerp(p1.x, p2.x, t),
                  lerp(p1.y, p2.y, t)
                  );
}

struct PointInCurve {
    float2 point;
    float2 derivative;
};

struct ColorsCount {
    uint32_t value;
};

PointInCurve getPointInCurve(
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
    
    float2 startForDerivative = interpolation_buffer[previousPageStart - 2];
    float2 endForDerivative = interpolation_buffer[previousPageStart - 1];
    float2 derivative = endForDerivative - startForDerivative;
    
    PointInCurve pointInTheCurve;
    
    pointInTheCurve.point = interpolation_buffer[previousPageStart];
    pointInTheCurve.derivative = derivative;
    
    return pointInTheCurve;
}

struct VertexOut {
    float4 pos [[position]];
    float t;
};

kernel void calculateVertex(
                            constant Env* env [[buffer(0)]],
                            constant float2* controlPoints[[buffer(1)]],
                            device VertexOut* results[[buffer(2)]],
                            uint vertexId [[thread_position_in_grid]]) {
    if (vertexId >= env->vertexCount) {
        return;
    }
    
    float t;
    if (vertexId == 0) {
        t = 0;
    } else if (vertexId == env->vertexCount - 1) {
        t = 1;
    } else {
        uint integerT = vertexId - 1;
        
        // minus first and last (which are reserved) and minus 1 because we shifted the integerT
        uint range = env->vertexCount - 3;
        t = (float)integerT / (float)range;
    }
    
    PointInCurve pointInCurve = getPointInCurve(env, controlPoints, t);
    
    float derivativeLength = length(pointInCurve.derivative);
    
    float2 resultPoint;
    if (derivativeLength == 0) {
        resultPoint = pointInCurve.point;
    } else {
        float2 derivativeWithUnitLength = pointInCurve.derivative / derivativeLength;
        
        bool normalDirectionIsLeft = vertexId % 2 == 0;
        
        float2 rotatedDerivativeUnitVector;
        if (normalDirectionIsLeft) {
            rotatedDerivativeUnitVector = float2(-derivativeWithUnitLength.y, derivativeWithUnitLength.x);
        } else {
            rotatedDerivativeUnitVector = float2(derivativeWithUnitLength.y, -derivativeWithUnitLength.x);
        }
        
        float2 offsetForStrokeWidth = env->strokeHalfWidth * rotatedDerivativeUnitVector;
        
        resultPoint = pointInCurve.point + offsetForStrokeWidth;
    }
    
    // Result point is in points, we need to convert it to GPU-land
    
    // Praying to allakh, there is no division by 0
    float2 pointInUnitCoordinates = resultPoint / env->canvasSize;
    
    float2 pointRelativeToCenter = pointInUnitCoordinates - float2(0.5, 0.5);
    
    pointRelativeToCenter.y = -pointRelativeToCenter.y;
    
    float2 pointInGpuLand = pointRelativeToCenter * 2.0;
    
    VertexOut res;
    res.pos.xy = pointInGpuLand;
    res.pos.zw = {0, 1};
    res.t = t;
    
    results[vertexId] = res;
}

[[vertex]]
VertexOut vertexPassthrough(const device VertexOut* vertices [[buffer(0)]],
                            uint vid [[vertex_id]]) {
    return vertices[vid];
}

[[fragment]]
half4 calculateFragment(
                        VertexOut v [[stage_in]],
                        constant half4* colors [[buffer(0)]],
                        constant float* stops [[buffer(1)]],
                        constant ColorsCount* _colorsCount [[buffer(2)]]
                        ) {
    uint colorsCount = _colorsCount->value;
    
    float t = v.t;
    half4 color;
    for (uint i = 0; i < colorsCount; i++) {
        float stop = stops[i];

        if (i == colorsCount - 1) {
            color = colors[i];
        } else {
            float nextStop = stops[i + 1];
            
            if (t < stop) {
                color = colors[i];
                break;
            } else if (t >= stop && t <= nextStop) {
                float range = nextStop - stop;
                
                if (range == 0) {
                    color = colors[i];
                    break;
                } else {
                    float diff = t - stop;
                    
                    float unitProgressBetweenStops = diff / range;
                    
                    color = lerp(colors[i], colors[i + 1], (half)unitProgressBetweenStops);
                    break;
                }
            } else {
                continue;
            }
        }
    }
    return color;
}
