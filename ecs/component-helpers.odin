package ecs

import "../profiler"

import "core:fmt"
import "core:mem"
import "core:slice"

AddComponent :: proc(entity: EntityID, component: $T) {
    //fmt.printf("adding component %v to entity %v\n", typeid_of(type_of(component)), entity)

    entityInfo := &entityInfoLookup[entity]

    oldArchetype: ^Archetype = nil
    if (len(entityInfo.components) > 0) {
        oldArchetype = GetArchetype(entityInfo.components[:])
    }

    append(&entityInfo.components, typeid_of(T))
    SortComponents(entityInfo.components)
    //fmt.printf("entity %v's components: %v\n", entity, entityInfo.components)

    archetype := GetArchetype(entityInfo.components[:])

    indexInNewArchetype := archetype.count
    append(&archetype.entityIDs, entity)

    // fmt.printf("%v - %v entities after adding %v\n",
    //            archetype.componentTypeSet,
    //            len(archetype.entityIDs),
    //            typeid_of(type_of(component)));

    AddInstanceSlotToArchetype(archetype)
    WriteComponent(archetype, indexInNewArchetype, component)

    if oldArchetype != nil {
        for instanceList,i in oldArchetype.componentInstanceLists {
            //fmt.printf("copying a %v to new archetype (%v) - old index: %v, new index: %v\n", instanceList.typeID, archetype.componentTypeSet, entityInfo.indexInArchetype, indexInNewArchetype)
            oldComponent := GetComponentDataFromInstanceList(instanceList, entityInfo.indexInArchetype)
            WriteComponent(archetype, indexInNewArchetype, oldComponent, instanceList.typeID)
            RemoveComponentDataFromInstanceList(&oldArchetype.componentInstanceLists[i], entityInfo.indexInArchetype)
        }

        oldArchetype.entityIDs[entityInfo.indexInArchetype] = oldArchetype.entityIDs[oldArchetype.count-1]
        pop(&oldArchetype.entityIDs)
        oldArchetype.count -= 1
    }

    entityInfo.archetype = archetype
    entityInfo.indexInArchetype = indexInNewArchetype
}

GetComponent :: proc {
    GetComponentBySystemIterator,
    GetComponentByEntity,
    GetComponentByIndex,
}

GetComponentBySystemIterator :: proc(iterator: ^SystemIterator, $T: typeid) -> ^T {
    if slice.contains(iterator.guaranteedComponentTypes, T) == false {
        fmt.printf("System is requesting a %v, but the system only guarantees %v", typeid_of(T), iterator.guaranteedComponentTypes)
    }

    return GetComponentByIndex(iterator.archetype,
                               iterator.index,
                               T)
}

GetComponentByEntity :: proc(entity: EntityID, $T: typeid) -> ^T {
    info := entityInfoLookup[entity]
    return GetComponentByIndex(info.archetype, info.indexInArchetype, T)
}

GetComponentByIndex :: proc(archetype: ^Archetype, index: int, $T: typeid) -> ^T {
    instanceList := GetInstanceList(archetype, T)
    return &(cast([^]T)instanceList.instances)[index]
}

SortComponentsDynamicArray :: proc(components: [dynamic]typeid) {
    SortComponentsSlice(components[:])
}

SortComponentsSlice :: proc(components: []typeid) {
    for i:=1; i<len(components); i+=1 {
        t := transmute(int)components[i]
        for j:=i-1; j>=0; j-=1 {
            other := transmute(int)components[j]
            if other > t {
                components[j+1] = transmute(typeid)other
            } else {
                components[j+1] = transmute(typeid)t
                break
            }
            if j==0 {
                components[0] = transmute(typeid)t
            }
        }
    }
}

SortComponents :: proc { SortComponentsDynamicArray, SortComponentsSlice }