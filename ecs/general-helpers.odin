package ecs

IsNil :: proc { IsSystemNil }

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