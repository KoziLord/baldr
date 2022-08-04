package Transform

import "../ECS"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

@(private)
Optional :: ECS.Optional

@(private)
float2 :: [2]f64

@(private)
float3 :: [3]f64

@(private)
float4 :: [4]f64

@(private)
float4x4 :: matrix[4,4]f64

Transform2D :: struct {
    localPosition: float2,
    localRotation: f64,
    localScale: f64,
    parent: Optional(ECS.EntityID),
    cache: Transform2DCache,
}

Transform3D :: struct {
    localPosition: float3,
    localRotation: quaternion128,
    localScale: f64,
    parent: Optional(ECS.EntityID),
    cache: Transform3DCache,
}

@(private="file")
Transform2DCache :: struct {
    localPosition: float2,
    localRotation: f64,
    localScale: f64,
    parent: Optional(ECS.EntityID),
    localToWorld: float4x4,
    worldToLocal: float4x4,
}

@(private="file")
Transform3DCache :: struct {
    localPosition: float3,
    localRotation: quaternion128,
    localScale: f64,
    parent: Optional(ECS.EntityID),
    localToWorld: float4x4,
    worldToLocal: float4x4,
}

Make2D :: proc(position: float2 = 0, rotation: f64 = 0, scale: f64 = 1) -> Transform2D {
    return Transform2D {
        localPosition = position,
        localRotation = rotation,
        localScale = scale,
        parent = nil,
        cache = Transform2DCache {
            localPosition = position,
            localRotation = rotation,
            localScale = scale,
            parent = nil,
            localToWorld = TRSMatrix2D(position, rotation, scale),
            worldToLocal = InverseTRSMatrix2D(position, rotation, scale),
        },
    }
}

Make3D :: proc(position: float3 = 0, rotation: quaternion128 = 1, scale: f64 = 1) -> Transform3D {
    return Transform3D {
        localPosition = position,
        localRotation = rotation,
        localScale = scale,
        parent = nil,
        cache = Transform3DCache {
            localPosition = position,
            localRotation = rotation,
            localScale = scale,
            parent = nil,
            localToWorld = TRSMatrix3D(position, rotation, scale),
            worldToLocal = InverseTRSMatrix3D(position, rotation, scale),
        },
    }
}

TRSMatrix2D :: proc(position: float2, rotation: f64, scale: f64) -> float4x4 {
    rotScale := RotationScaleMatrix2D(rotation, scale)
    result := cast(float4x4)rotScale
    result[2,2] = scale
    result[0,3] = position.x
    result[1,3] = position.y
    return result
}

InverseTRSMatrix2D :: proc(position: float2, rotation: f64, scale: f64) -> float4x4 {
    rotScale := RotationScaleMatrix2D(-rotation, 1.0 / scale)
    result := cast(float4x4)rotScale
    result[2,2] = scale
    result[0,3] = -position.x
    result[1,3] = -position.y
    return result
}

RotationScaleMatrix2D :: proc(rotation: f64, scale: f64) -> matrix[2,2]f64 {
    cos := math.cos(rotation)
    sin := math.sin(rotation)
    return matrix[2,2]f64 {
        cos, -sin,
        sin,  cos,
    }
}

TRSMatrix3D :: proc(position: float3, rotation: quaternion128, scale: f64) -> float4x4 {
    result := linalg.matrix4_from_trs_f64(linalg.Vector3f64(position),
                                          linalg.Quaternionf64(rotation),
                                          scale)
    return cast(float4x4)(result)
}

InverseTRSMatrix3D :: proc(position: float3, rotation: quaternion128, scale: f64) -> float4x4 {
    inverseRotation := linalg.quaternion_inverse(linalg.Quaternionf64(rotation))
    result := linalg.matrix4_from_trs_f64(linalg.Vector3f64(-position),
                                          inverseRotation,
                                          1.0 / scale)

    return cast(float4x4)(result)
}

GetWorldPos :: proc(transform: ^$Transform) -> float3
        where (Transform==Transform2D || Transform==Transform3D) {

    return LocalToWorld(transform, float3{0,0,0})
}

LocalToWorld :: proc(transform: ^$Transform, localPosition: $Vector) -> float3
        where ((Transform==Transform2D || Transform==Transform3D) && (Vector==float2 || Vector==float3)) {
    
    
    localPos3D: float4
    localPos3D.w = 1

    when Vector == float2 {
        localPos3D.xy = localPosition
    } else when Vector == float3 {
        localPos3D.xyz = localPosition
    }

    localToWorld := GetLocalToWorld(transform)

    //fmt.printf("localPos3D: %v\nmatrix: %v\nresult: %v\n", localPos3D, localToWorld, (localToWorld * localPos3D).xyz)

    return (localToWorld * localPos3D).xyz
}

@(private="file")
GetLocalToWorld :: proc(transform: ^$Transform) ->
        (localToWorld: float4x4, wasUpdated: bool)
        where (Transform==Transform2D || Transform==Transform3D) #optional_ok {

    parent, hasParent := transform.parent.(ECS.EntityID)
    parentLocalToWorld: float4x4 = 1

    parentWasUpdated := false
    if hasParent {
        parentInfo := ECS.entityInfoLookup[parent]
        if slice.contains(parentInfo.components[:], Transform2D) {
            parentTransform := ECS.GetComponent(parent, Transform2D)
            parentLocalToWorld, parentWasUpdated = GetLocalToWorld(parentTransform)

        } else if slice.contains(parentInfo.components[:], Transform3D) {
            parentTransform := ECS.GetComponent(parent, Transform3D)
            parentLocalToWorld, parentWasUpdated = GetLocalToWorld(parentTransform)
        }
    }

    if parentWasUpdated ||
        transform.parent != transform.cache.parent ||
        transform.localPosition != transform.cache.localPosition ||
        transform.localRotation != transform.cache.localRotation ||
        transform.localScale != transform.cache.localScale {
        
        newMatrix: float4x4
        when Transform==Transform2D {

            newMatrix = TRSMatrix2D(transform.localPosition,
                                    transform.localRotation,
                                    transform.localScale)
            //fmt.println("updating Transform2D cache")
        } else when Transform==Transform3D {
            newMatrix = TRSMatrix3D(transform.localPosition,
                                    transform.localRotation,
                                    transform.localScale)
            //fmt.println("updating Transform3D cache")
        }

        transform.cache.localToWorld = newMatrix
        transform.cache.worldToLocal = MatrixInverse(transform.cache.localToWorld)
        
        transform.cache.localPosition = transform.localPosition
        transform.cache.localRotation = transform.localRotation
        transform.cache.localScale = transform.localScale
        transform.cache.parent = transform.parent

        wasUpdated = true
        return parentLocalToWorld * transform.cache.localToWorld, true
    } else {
        return parentLocalToWorld * transform.cache.localToWorld, false
    }
}

MatrixInverse :: proc(mat: float4x4) -> float4x4 {
    return float4x4(linalg.matrix4_inverse(linalg.Matrix4x4f64(mat)))
}