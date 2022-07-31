package ecs

import "core:fmt"

EntityID :: distinct int

nextEntityID: EntityID = 1

entityInfoLookup := make(map[EntityID]EntityInfo)

@(private="file")
scheduledDeletions := make(map[EntityID]bool)

EntityInfo :: struct {
    id: EntityID,
    components: [dynamic]typeid,
    archetype: ^Archetype,
    indexInArchetype: int,
}

NewEntity :: proc() -> EntityID {
    nextEntityID += 1
    //fmt.printf("new entity ID: %v\n", nextEntityID)
    entityInfo: EntityInfo
    entityInfo.id = cast(EntityID)nextEntityID
    entityInfo.components = make([dynamic]typeid)
    entityInfoLookup[nextEntityID] = entityInfo
    return entityInfo.id
}

ScheduleEntityDeletion :: proc(entity: EntityID) {
    scheduledDeletions[entity] = true
}

PerformScheduledEntityDeletions :: proc() {
    for entity, _ in scheduledDeletions {
        entityInfo := entityInfoLookup[entity]
        archetype := entityInfo.archetype
        for _, i in archetype.componentInstanceLists {
            instanceList := archetype.componentInstanceLists[i]
            RemoveComponentDataFromInstanceList(&instanceList, entityInfo.indexInArchetype)
        }

        movedEntity := archetype.entityIDs[archetype.count-1]
        archetype.entityIDs[entityInfo.indexInArchetype] = movedEntity
        pop(&archetype.entityIDs)
        archetype.count -= 1
        movedEntityInfo := entityInfoLookup[movedEntity]
        movedEntityInfo.indexInArchetype = entityInfo.indexInArchetype
        entityInfoLookup[movedEntity] = movedEntityInfo

        delete_key(&entityInfoLookup, entity)
    }
    clear(&scheduledDeletions)
}