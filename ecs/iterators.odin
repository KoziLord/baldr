package ECS

import "../Profiler"
import "../MultiMap"

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


@(private)
AllocateSystemIterator :: proc(archetypes: []^Archetype, componentTypes: []typeid) -> ^SystemIterator {
    iterator := new(SystemIterator)
    iterator.archetypes = archetypes
    iterator.guaranteedComponentTypes = componentTypes
    
    return iterator
}

ResetIterator :: proc {
    ResetSystemIterator,
    //ResetBucketIterator,
}

ResetSystemIterator :: proc(iterator: ^SystemIterator) {
    iterator.archetype = nil
    iterator.internals.nextArchetypeIndex = 0
    iterator.internals.nextIndexWithinArchetype = 0
    iterator.internals.tappedEntityCount = 0
    iterator.isFirstEntity = false
}

Iterate :: proc(iterator: ^SystemIterator) -> bool {
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