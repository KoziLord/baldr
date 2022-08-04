package ECS

import "core:fmt"
import "core:mem"
import "core:slice"

SystemID :: distinct int

nextSystemID: SystemID = 1


systemLookup := make(map[SystemID]System)

System :: struct {
    id: SystemID,
    componentTypes: []typeid,
    procedure: proc(^SystemIterator),
}

CreateSystem :: proc(componentTypes: []typeid, procedure: proc(^SystemIterator)) -> SystemID {
    SortComponents(componentTypes)
    
    system: System
    system.procedure = procedure

    // system.componentTypes = make([]typeid, len(componentTypes))
    // for t, i in componentTypes {
    //     system.componentTypes[i] = t
    // }
    system.componentTypes = slice.clone(componentTypes)
    
    system.id = nextSystemID

    systemLookup[system.id] = system

    defer nextSystemID += 1
    return nextSystemID
}

RunSystem :: proc(systemID: SystemID) {
    system := systemLookup[systemID]

    archetypes := make([dynamic]^Archetype)
    for _, archetype in archetypeLookup {
        if ArchetypeMatches(archetype, system.componentTypes) {
            append(&archetypes, archetype)
        }
    }

    iterator := AllocateSystemIterator(archetypes[:], system.componentTypes)
    
    system.procedure(iterator)
    
    delete(archetypes)
    free(iterator)
}