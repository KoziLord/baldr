package ecs

import "../multiMap"

import "core:fmt"
import "core:math"

@(private)
int3 :: [3]int

@(private)
int2 :: [2]int

BucketMap :: struct {
    cellSize: f64,
    buckets: map[int3][dynamic]EntityID,
    buckets2: multiMap.MultiMap(int2, EntityID),
}

CreateBucketMap :: proc(cellSize: f64) -> ^BucketMap {
    result := new(BucketMap)
    result.buckets = make(map[int3][dynamic]EntityID, 100, context.temp_allocator)
    result.cellSize = cellSize
    return result
}

WriteBuckets :: proc(bucketMap: ^BucketMap, iterator: ^SystemIterator, $T: typeid, boundsGetter: proc(T) -> (min: [$N]f64, max: [N]f64)) where N>0 && N<4 {
    // fmt.println("clearing buckets...")
    for cell, _ in bucketMap.buckets {
        delete(bucketMap.buckets[cell])
        delete_key(&bucketMap.buckets, cell)
    }
    // fmt.println("cleared buckets!")


    for Iterate(iterator) {
        component := GetComponent(iterator, T)
        entityID := iterator.archetype.entityIDs[iterator.index]
        minPos, maxPos := boundsGetter(component^)

        minCell := GetCell(minPos, bucketMap.cellSize)
        maxCell := GetCell(maxPos, bucketMap.cellSize)

        for x in minCell.x..maxCell.x {
            for y in minCell.y..maxCell.y {
                for z in minCell.z..maxCell.z {
                    AddEntityToBucket(bucketMap, entityID, int3{x,y,z})
                }
            }
        }
    }

    ResetIterator(iterator)
}

GetCell :: proc(position: [$N]f64, cellSize: f64) -> int3 {
    cell: int3

    for piece, i in position {
        cell[i] = cast(int)math.floor(piece / cellSize)
    }

    return cell
}

GetBucket :: proc(bucketMap: ^BucketMap, cell: int3) -> [dynamic]EntityID {
    return bucketMap.buckets[cell]
}

@(private="file")
AddEntityToBucket :: proc(bucketMap: ^BucketMap, entityID: EntityID, cell: int3) {
    bucket: [dynamic]EntityID
    ok: bool
    bucket, ok = bucketMap.buckets[cell]
    if !ok {
        bucket = make([dynamic]EntityID)
    }
    append(&bucket, entityID)

    bucketMap.buckets[cell] = bucket
}