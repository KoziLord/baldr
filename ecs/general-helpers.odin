package ECS

import "core:fmt"
import "core:math/rand"

Optional :: union($T: typeid) { T }

IsNil :: proc { IsSystemNil, IsEntityNil }

IsSystemNil :: proc(systemID : SystemID) -> bool {
    return systemID == 0
}

IsEntityNil :: proc(entityID : EntityID) -> bool {
    if (entityID == 0) {
        return true
    }

    _, ok := entityInfoLookup[entityID]
    return (ok == false)
}

GetIteratorCount :: proc(iterator: ^SystemIterator) -> int {
    totalCount := 0
    for archetype in iterator.archetypes {
        totalCount += archetype.count
    }
    return totalCount
}

GetRandomEntity :: proc(iterator: ^SystemIterator) -> Optional(EntityID) {
    totalCount := GetIteratorCount(iterator)

    randomIndex := int(rand.int31_max(i32(totalCount)))

    for archetype in iterator.archetypes {
        if randomIndex < archetype.count {
            return archetype.entityIDs[randomIndex]
        } else {
            randomIndex -= archetype.count
        }
    }
    return nil
}