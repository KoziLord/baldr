package main

import "core:math"

Min :: proc(a, b: float2) -> float2 {
    return float2 {
        min(a.x, b.x),
        min(a.y, b.y),
    }
}

Max :: proc(a, b: float2) -> float2 {
    return float2 {
        max(a.x, b.x),
        max(a.y, b.y),
    }
}

Floor :: proc(vector: float2) -> int2 {
    return int2 {
        int(math.floor(vector.x)),
        int(math.floor(vector.y)),
    }
}

Dot :: proc(a, b: float2) -> f64 {
    return a.x*b.x + a.y*b.y
}

SqrLength :: proc(vector: float2) -> f64 {
    return Dot(vector, vector)
}

GetAngle :: proc(direction: float2) -> f64 {
    return math.atan2(direction.y, direction.x)
}

GetDirection :: proc(angle: f64) -> float2 {
    return float2 {
        math.cos(angle),
        math.sin(angle),
    }
}

AngleDiff :: proc(a, b: f64) -> f64 {
    diff := a - b
    diff -= math.floor((diff + math.PI) / (math.PI*2)) * (math.PI*2)
    return diff
}