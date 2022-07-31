package ecs

import "core:fmt"
import "core:mem"

archetypeLookup := make(map[int]^Archetype)

INITIAL_ALLOC_COUNT :: 1

InstanceList :: struct {
    typeID: typeid,
    stride: int,
    blobSize: int,
    instances: rawptr,
    archetype: ^Archetype,
}

Archetype :: struct {
    count: int,
    capacity: int,
    componentTypeSet: []typeid,
    componentInstanceLists: []InstanceList,
    entityIDs: [dynamic]EntityID,
}

GetArchetype :: proc(componentTypes: []typeid) -> ^Archetype {
    SortComponents(componentTypes)
    hash := ArchetypeHash(componentTypes)

    // fmt.printf("getting archetype for %v (hash: %v)\n", componentTypes, hash)

    archetype, ok := archetypeLookup[hash]
    if ok == false {
        //fmt.printf("creating new archetype for %v\n", componentTypes)
        archetype = CreateArchetype(componentTypes)
        archetypeLookup[hash] = archetype
    }
    return archetype
}

@(private)
CreateArchetype :: proc(types: []typeid) -> ^Archetype {
    archetype : ^Archetype = new(Archetype)
    SortComponents(types)
    archetype.componentTypeSet = types
    archetype.count = 0
    archetype.capacity = INITIAL_ALLOC_COUNT
    archetype.entityIDs = make([dynamic]EntityID)

    instanceLists := make([]InstanceList, len(types))
    for t, i in types {
        instanceLists[i] = CreateInstanceList(t, archetype)
    }
    archetype.componentInstanceLists = instanceLists

    return archetype
}

@(private)
CreateInstanceList :: proc(t: typeid, archetype: ^Archetype) -> InstanceList {
    list : InstanceList
    list.typeID = t
    list.stride = type_info_of(t).size
    list.blobSize = list.stride * INITIAL_ALLOC_COUNT
    list.instances = mem.alloc(list.blobSize)
    //fmt.printf("blob size for %v: %v (%v bytes x%v)\n", t, list.blobSize, list.stride, INITIAL_ALLOC_COUNT)
    list.archetype = archetype
    return list
}

@(private)
GetInstanceList :: proc(archetype: ^Archetype, t: typeid) -> ^InstanceList {
    for list, i in archetype.componentInstanceLists {
        if list.typeID == t {
            return &archetype.componentInstanceLists[i]
        }
    }
    return nil
}

@(private)
AddInstanceSlotToArchetype :: proc(archetype: ^Archetype) {
    indexInArchetype := archetype.count
    if archetype.capacity <= indexInArchetype {
        //fmt.printf("need to double capacity for %v\n", archetype.componentTypeSet)
        DoubleArchetypeCapacity(archetype)
    }
    archetype.count += 1
}

@(private)
RemoveComponentDataFromInstanceList :: proc(list: ^InstanceList, index: int) {
    lastComponent := GetComponentDataFromInstanceList(list^, list.archetype.count-1)
    WriteComponentFromBytes(list.archetype, index, lastComponent, list.typeID)
}

@(private)
GetComponentDataFromInstanceList :: proc(list: InstanceList, index: int) -> []byte {
    blob := mem.byte_slice(list.instances, list.blobSize)
    return blob[index*list.stride : (index+1)*list.stride]
}

@(private)
WriteComponentStronglyTyped :: proc(archetype: ^Archetype, writeIndex: int, component: $T) {
    instanceList := GetInstanceList(archetype, T)
    pointers := cast([^]T)instanceList.instances
    pointers[writeIndex] = component
    
    // t := typeid_of(T)
    // bytes := mem.any_to_bytes(component)
    // WriteComponentFromBytes(archetype, writeIndex, bytes, t)
}

@(private)
WriteComponentFromBytes :: proc(archetype: ^Archetype, writeIndex: int, component: []byte, componentType: typeid) {
    instanceList := GetInstanceList(archetype, componentType)
    blob := mem.byte_slice(instanceList.instances, instanceList.blobSize)
    slice := blob[writeIndex*instanceList.stride : (writeIndex+1)*instanceList.stride]
    //fmt.printf("writing component: %v\n", component)
    for _,i in slice {
        slice[i] = component[i]
    }
}

WriteComponent :: proc { WriteComponentStronglyTyped, WriteComponentFromBytes }

DoubleArchetypeCapacity :: proc(archetype: ^Archetype) {
    // fmt.printf("resizing archetype %v from %v to %v\n", archetype.componentTypeSet, archetype.capacity, archetype.capacity*2)
    archetype.capacity *= 2
    for list, i in archetype.componentInstanceLists {
        newBlobSize := archetype.capacity * list.stride
        archetype.componentInstanceLists[i].instances = mem.resize(archetype.componentInstanceLists[i].instances, list.blobSize, newBlobSize)
        archetype.componentInstanceLists[i].blobSize = newBlobSize
    }
}

@(private)
LARGE_PRIME :: 23456789

@(private)
ArchetypeHash :: proc(componentTypes: []typeid) -> int {
    hash := 0

    for t in componentTypes {
        hash *= LARGE_PRIME
        hash += transmute(int)t
    }
    return hash
}

ArchetypeMatches :: proc(archetype: ^Archetype, componentTypes: []typeid) -> bool {
    i := 0
    for t,j in archetype.componentTypeSet {
        if len(componentTypes) > i {
            if componentTypes[i] == t {
                i += 1
            }
        }
    }
    return i == len(componentTypes)
}