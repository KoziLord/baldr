package ecs

import "../profiler"

import "core:fmt"

SystemIterator :: struct {
    archetypes: []^Archetype,
    guaranteedComponentTypes: []typeid,
    
    archetype: ^Archetype,
    index: int,
    entity: EntityID,
    
    isFirstEntity: bool,
    
    internals: SystemIteratorInternals,
}

@(private="file")
SystemIteratorInternals :: struct {
    nextArchetypeIndex: int,
    nextIndexWithinArchetype: int,
    tappedEntityCount: int,
}

BucketIterator :: struct {
    bucketMap: ^BucketMap,
    bucket: [dynamic]EntityID,
    minCell, maxCell, cell: int3,
    indexWithinBucket: int,
    entity: EntityID,
}


@(private)
AllocateSystemIterator :: proc(archetypes: []^Archetype, componentTypes: []typeid) -> ^SystemIterator {
    iterator := new(SystemIterator)
    iterator.archetypes = archetypes
    iterator.guaranteedComponentTypes = componentTypes
    
    return iterator
}

ResetIterator :: proc {
    ResetSystemIterator,
    ResetBucketIterator,
}

ResetSystemIterator :: proc(iterator: ^SystemIterator) {
    iterator.archetype = nil
    iterator.internals.nextArchetypeIndex = 0
    iterator.internals.nextIndexWithinArchetype = 0
    iterator.internals.tappedEntityCount = 0
    iterator.isFirstEntity = false
}

Iterate :: proc {
    IterateSystemIterator,
    IterateBucketIterator,
}

IterateSystemIterator :: proc(iterator: ^SystemIterator) -> bool {
    if iterator.internals.nextArchetypeIndex < len(iterator.archetypes) {
        if iterator.internals.nextIndexWithinArchetype == 0 {
            iterator.archetype = iterator.archetypes[iterator.internals.nextArchetypeIndex]
            for iterator.archetype.count == 0 {
                iterator.internals.nextArchetypeIndex += 1
                if (iterator.internals.nextArchetypeIndex < len(iterator.archetypes)) {
                    iterator.archetype = iterator.archetypes[iterator.internals.nextArchetypeIndex]
                } else {
                    return false
                }
            }
        }
        
        if iterator.internals.nextIndexWithinArchetype < iterator.archetype.count {
            iterator.index = iterator.internals.nextIndexWithinArchetype
            iterator.internals.tappedEntityCount += 1
            iterator.isFirstEntity = (iterator.internals.tappedEntityCount == 1)
            iterator.entity = iterator.archetype.entityIDs[iterator.index]
            
            iterator.internals.nextIndexWithinArchetype += 1
            if iterator.internals.nextIndexWithinArchetype >= iterator.archetype.count {
                iterator.internals.nextIndexWithinArchetype = 0
                iterator.internals.nextArchetypeIndex += 1
            }
            return true
        }
    }
    return false
}


GetBucketIterator :: proc {
    GetBucketIteratorFloat2,
    GetBucketIteratorFloat3,
}

@(deferred_out=DeleteBucketIterator)
@(private)
GetBucketIteratorFloat2 :: proc(bucketMap: ^BucketMap, minPos, maxPos: [2]f64) -> ^BucketIterator {
    return GetBucketIteratorCommon(bucketMap, minPos, maxPos)
}

@(deferred_out=DeleteBucketIterator)
@(private)
GetBucketIteratorFloat3 :: proc(bucketMap: ^BucketMap, minPos, maxPos: [3]f64) -> ^BucketIterator {
    return GetBucketIteratorCommon(bucketMap, minPos, maxPos)
}

@(private="file")
GetBucketIteratorCommon :: proc(bucketMap: ^BucketMap, minPos, maxPos: [$N]f64) -> ^BucketIterator {
    iterator := new(BucketIterator, context.temp_allocator)
    iterator.bucketMap = bucketMap
    iterator.minCell = GetCell(minPos, bucketMap.cellSize)
    iterator.maxCell = GetCell(maxPos, bucketMap.cellSize)
    iterator.cell = iterator.minCell
    iterator.cell.x -= 1
    return iterator
}

@(private)
DeleteBucketIterator :: proc(iterator: ^BucketIterator) {
    free(iterator, context.temp_allocator)
}

IterateBucketIterator :: proc(iterator: ^BucketIterator) -> bool {
    //profiler.MeasureThisScope()
    for {
        if iterator.bucket == nil {

            iterator.cell.x += 1
            if iterator.cell.x > iterator.maxCell.x {
                iterator.cell.x = iterator.minCell.x
                iterator.cell.y += 1
                if iterator.cell.y > iterator.maxCell.y {
                    iterator.cell.y = iterator.minCell.y
                    iterator.cell.z += 1
                    if iterator.cell.z > iterator.maxCell.z {
                        return false
                    }
                }
            }
            
            ok : bool
            iterator.bucket, ok = iterator.bucketMap.buckets[iterator.cell]
            if ok {
                iterator.indexWithinBucket = -1
            } else {
                iterator.bucket = nil
            }
        } else {
            iterator.indexWithinBucket += 1
            if iterator.indexWithinBucket < len(iterator.bucket) {
                iterator.entity = iterator.bucket[iterator.indexWithinBucket]
                return true
            } else {
                iterator.bucket = nil
            }
        }
    }
}

ResetBucketIterator :: proc(iterator: ^BucketIterator) {
    iterator.cell = iterator.minCell
}