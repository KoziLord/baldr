package ecs

import "core:fmt"

EntityID :: distinct int

nextEntityID: EntityID = 1

entityInfoLookup := make(map[EntityID]EntityInfo)

EntityInfo :: struct {
    id: EntityID,
    components: [dynamic]typeid,
    archetype: ^Archetype,
    indexInArchetype: int,
}

NewEntity :: proc() -> EntityID {
    defer nextEntityID += 1
    //fmt.printf("new entity ID: %v\n", nextEntityID)
    entityInfo: EntityInfo
    entityInfo.id = cast(EntityID)nextEntityID
    entityInfo.components = make([dynamic]typeid)
    entityInfoLookup[nextEntityID] = entityInfo
    return entityInfo.id
}