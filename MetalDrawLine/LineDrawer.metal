#include <metal_stdlib>

using namespace metal;

#define MAX_POINTS 20
#define MAX_POINTS_BUFFER 190 // This is calculated by (0..<MAX_POINTS).map { $0 }.reduce(0, +)

struct Env {
    float2 canvasSize;
    float strokeHalfWidth;
};

struct BezierGeometry {
    uint32_t vertexCount;
    uint32_t controlPointsCount;
    uint32_t roundedEndResolution;
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
                       constant BezierGeometry* bezierGeometry,
                       constant float2* controlPoints,
                       float t
                       ) {

    if (bezierGeometry->controlPointsCount == 2) {
        float2 p1 = controlPoints[0];
        float2 p2 = controlPoints[1];
        float2 derivative = p2 - p1;
        float2 interpolatedPoint = lerp(p1, p2, t);
        
        PointInCurve pointInCurve;
        pointInCurve.derivative = derivative;
        pointInCurve.point = interpolatedPoint;
        return pointInCurve;
    }
    
    float2 interpolation_buffer[MAX_POINTS_BUFFER];
    for (uint32_t i = 0; i < bezierGeometry->controlPointsCount - 1; i++) {
        float2 p1 = controlPoints[i];
        float2 p2 = controlPoints[i + 1];
        float2 interpolatedPoint = lerp(p1, p2, t);
        
        interpolation_buffer[i] = interpolatedPoint;
    }
    
    uint32_t interpolationPoints = bezierGeometry->controlPointsCount - 1;
    uint32_t previousPageStart = 0;
    uint32_t pageStart = bezierGeometry->controlPointsCount - 1;

    while (interpolationPoints > 1) {
        
        for (uint32_t i = 0; i < interpolationPoints - 1; i++) {
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
    
    #if DEBUG
    uint8_t vertexType;
    float2 unscaledTailDirectionVector;
    float2 tailDirectionVector;
    float2 normalVector;
    float angleToRotateBy;
    uint32_t subdivisionIndex;
    float subdivisionArc;
    float subdivisionArcDividend;
    float subdivisionArcDivisor;
    float2 rotatedVector;
    float2 pointAttachedToTheEnd;
    #endif
};

// Result point is in points, we need to convert it to GPU-land
float2 convertPointToGpuLand(constant Env* env, float2 point) {
    // Praying to allakh, there is no division by 0
    float2 pointInUnitCoordinates = point / env->canvasSize;
    
    float2 pointRelativeToCenter = pointInUnitCoordinates - float2(0.5, 0.5);
    
    pointRelativeToCenter.y = -pointRelativeToCenter.y;
    
    float2 pointInGpuLand = pointRelativeToCenter * 2.0;
    
    return pointInGpuLand;
}

VertexOut calculateRoundedEndVertex(constant Env* env,
                                    constant BezierGeometry* bezierGeometry,
                                    constant float2* controlPoints,
                                    bool firstEnd,
                                    uint32_t vertexId) {
    float t;
    float2 unscaledTailDirectionVector;
    
    if (firstEnd) {
        float2 vectorFromStartToNext = controlPoints[0] - controlPoints[1];
        unscaledTailDirectionVector = vectorFromStartToNext / length(vectorFromStartToNext);
        t = 0;
    } else {
        float2 vectorFromEndToPrevious = controlPoints[bezierGeometry->controlPointsCount - 1]
            - controlPoints[bezierGeometry->controlPointsCount - 2];
        unscaledTailDirectionVector = vectorFromEndToPrevious / length(vectorFromEndToPrevious);
        t = 1;
    }
    
    float2 tailDirectionVector = unscaledTailDirectionVector * env->strokeHalfWidth;
    
    float2 normal = float2(tailDirectionVector.y, -tailDirectionVector.x);
    
    // allakh save me from division by 0
    float subdivisionArcDividend = __FLT_M_PI__;
    float subdivisionArcDivisor = bezierGeometry->roundedEndResolution + 1;
    float subdivisionArc = subdivisionArcDividend / subdivisionArcDivisor;
    uint32_t subdivisionIndex = vertexId + 1;
    float angleToRotateBy = subdivisionArc * subdivisionIndex;
    
    auto cosOfAngle = cos(angleToRotateBy);
    auto sinOfAngle = sin(angleToRotateBy);
    
    
    // This is local, keep in mind
    float2 rotatedVector = float2(
                                  cosOfAngle * normal.x - sinOfAngle * normal.y,
                                  sinOfAngle * normal.x + cosOfAngle * normal.y
                                  );
    
    float2 pointAttachedToTheEnd;
    if (firstEnd) {
        pointAttachedToTheEnd = controlPoints[0] + rotatedVector;
    } else {
        pointAttachedToTheEnd = controlPoints[bezierGeometry->controlPointsCount - 1]
            + rotatedVector;
    }
    
    auto pointInGpuLand = convertPointToGpuLand(env, pointAttachedToTheEnd);
    
    VertexOut res;
    res.pos.xy = pointInGpuLand;
    res.pos.zw = {0, 1};
    res.t = t;
    
#if DEBUG
    if (firstEnd) {
        res.vertexType = 0;
    } else {
        res.vertexType = 2;
    }
    res.unscaledTailDirectionVector = unscaledTailDirectionVector;
    res.tailDirectionVector = tailDirectionVector;
    res.normalVector = normal;
    res.angleToRotateBy = angleToRotateBy;
    res.subdivisionIndex = subdivisionIndex;
    res.subdivisionArc = subdivisionArc;
    res.subdivisionArcDividend = subdivisionArcDividend;
    res.subdivisionArcDivisor = subdivisionArcDivisor;
    res.rotatedVector = rotatedVector;
    res.pointAttachedToTheEnd = pointAttachedToTheEnd;
#endif
 
    return res;
}

VertexOut calculateBezierCurveVertex(
                                     constant Env* env,
                                     constant BezierGeometry* bezierGeometry [[buffer(1)]],
                                     constant float2* controlPoints[[buffer(2)]],
                                     uint32_t vertexId
                                     ) {
    float t;
    if (vertexId == 0) {
        t = 0;
    } else if (vertexId == bezierGeometry->vertexCount - 1) {
        t = 1;
    } else {
        uint32_t integerT = vertexId - 1;
        
        // minus first and last (which are reserved) and minus 1 because we shifted the integerT
        uint32_t range = bezierGeometry->vertexCount - 3;
        t = (float)integerT / (float)range;
    }
    
    PointInCurve pointInCurve = getPointInCurve(bezierGeometry, controlPoints, t);
    
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
    
    auto pointInGpuLand = convertPointToGpuLand(env, resultPoint);
    
    VertexOut res;
    res.pos.xy = pointInGpuLand;
    res.pos.zw = {0, 1};
    res.t = t;
    res.vertexType = 1;
 
    return res;
}

kernel void calculateVertex(
                            constant Env* env [[buffer(0)]],
                            constant BezierGeometry* bezierGeometry [[buffer(1)]],
                            constant float2* controlPoints[[buffer(2)]],
                            device VertexOut* results[[buffer(3)]],
                            uint32_t vertexId [[thread_position_in_grid]]) {
    uint32_t startVertexIdForRoundedEndSubdivisions1 = 0;
    uint32_t endVertexIdForRoundedEndSubdivisions1 = startVertexIdForRoundedEndSubdivisions1
        + bezierGeometry->roundedEndResolution;
    uint32_t startVertexIdForBezierGeometry = endVertexIdForRoundedEndSubdivisions1;
    uint32_t endVertexIdForBezierGeometry = startVertexIdForBezierGeometry
        + bezierGeometry->vertexCount;
    
    uint32_t startVertexIdForRoundedEndSubdivisions2 = endVertexIdForBezierGeometry;
    uint32_t endVertexIdForRoundedEndSubdivisions2 = startVertexIdForRoundedEndSubdivisions2 + bezierGeometry->roundedEndResolution;
    
    VertexOut res;
    
    if (startVertexIdForRoundedEndSubdivisions1 <= vertexId && vertexId < endVertexIdForRoundedEndSubdivisions1) {
        uint32_t localVertexId = vertexId - startVertexIdForRoundedEndSubdivisions1;
        res = calculateRoundedEndVertex(env, bezierGeometry, controlPoints, true, localVertexId);
    }
    
    else if (startVertexIdForBezierGeometry <= vertexId && vertexId < endVertexIdForBezierGeometry) {
        uint32_t localVertexId = vertexId - startVertexIdForBezierGeometry;
        res = calculateBezierCurveVertex(env, bezierGeometry, controlPoints, localVertexId);
        
    }
    
    else if (startVertexIdForRoundedEndSubdivisions2 <= vertexId && vertexId < endVertexIdForRoundedEndSubdivisions2) {
        uint32_t localVertexId = vertexId - startVertexIdForRoundedEndSubdivisions2;
        res = calculateRoundedEndVertex(env, bezierGeometry, controlPoints, false, localVertexId);
    }
    results[vertexId] = res;
}

[[vertex]]
VertexOut vertexPassthrough(const device VertexOut* vertices [[buffer(0)]],
                            uint32_t vid [[vertex_id]]) {
    return vertices[vid];
}

[[fragment]]
half4 calculateFragment(
                        VertexOut v [[stage_in]],
                        constant half4* colors [[buffer(0)]],
                        constant float* stops [[buffer(1)]],
                        constant ColorsCount* _colorsCount [[buffer(2)]]
                        ) {
    uint32_t colorsCount = _colorsCount->value;
    
    float t = v.t;
    half4 color;
    for (uint32_t i = 0; i < colorsCount; i++) {
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
