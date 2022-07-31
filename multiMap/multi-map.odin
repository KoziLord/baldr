package multiMap

import "../profiler"

import "core:hash"
import "core:fmt"
import "core:mem"
import "core:runtime"

END_OF_LIST :: -1

NO_VALUE :: -2

MultiMap :: struct($Key, $Value: typeid) {
    firstIndex: map[Key]int,
    nextIndex: []int,
    values: []Value,
    capacity: int,
    allocator: runtime.Allocator,
}

Iterator :: struct($Key, $Value: typeid) {
    multiMap: ^MultiMap(Key, Value),
    value: Value,
    startIndex: int,
    nextIndex: int,
}

Make :: proc($Key, $Value: typeid, capacity: int, allocator: runtime.Allocator = context.allocator) -> ^MultiMap(Key, Value) {
    multiMap := new(MultiMap(Key, Value), allocator)

    multiMap.firstIndex = make(map[Key]int, capacity, allocator)
    multiMap.nextIndex = make([]int, capacity, allocator)
    multiMap.values = make([]Value, capacity, allocator)
    multiMap.capacity = capacity
    multiMap.allocator = allocator

    Clear(multiMap)

    return multiMap
}

Clear :: proc(multiMap: ^MultiMap($Key, $Value)) {
    for i in 0..<multiMap.capacity {
        multiMap.nextIndex[i] = NO_VALUE
    }
    clear(&multiMap.firstIndex)
}

Delete :: proc(multiMap: ^MultiMap($Key, $Value)) {
    delete(multiMap.firstIndex)
    delete(multiMap.nextIndex, multiMap.allocator)
    delete(multiMap.values, multiMap.allocator)
    free(multiMap, multiMap.allocator)
}

Add :: proc(multiMap: ^MultiMap($Key, $Value), key: Key, value: Value) {
    firstIndex, ok := multiMap.firstIndex[key]
    index: int
    if !ok {
        // start new list
        hash := GetHash(key)
        index = int(hash % uint(multiMap.capacity))
        firstAttemptedIndex := index
        for multiMap.nextIndex[index] != NO_VALUE {
            index = (index+1) % multiMap.capacity
            if index == firstAttemptedIndex {
                fmt.println("hashmap is full!")
                return
            }
        }
        multiMap.firstIndex[key] = index
        //fmt.printf("writing firstIndex: %v\n", index)

    } else {
        // add to end of existing list
        index = firstIndex
        //fmt.printf("reading firstIndex: %v\n", index)
        for multiMap.nextIndex[index] != END_OF_LIST {
            index = multiMap.nextIndex[index]
        }
        //fmt.println("end of list")
        
        prevEndOfListIndex := index
        index = (index+1) % multiMap.capacity
        for multiMap.nextIndex[index] != NO_VALUE {
            index = (index+1) % multiMap.capacity
            if index == prevEndOfListIndex {
                fmt.println("hashmap is full!")
                return
            }
        }
        multiMap.nextIndex[prevEndOfListIndex] = index
    }

    multiMap.nextIndex[index] = END_OF_LIST
    multiMap.values[index] = value
}

HasKey :: proc(multiMap: ^MultiMap($Key, $Value), key: Key) -> bool {
    _, ok := multiMap.firstIndex[key]
    return ok
}

SetupIterator :: proc(multiMap: ^MultiMap($Key, $Value), key: Key, iterator: ^Iterator(Key, Value)) {
    firstIndex, ok := multiMap.firstIndex[key]
    if !ok do firstIndex = END_OF_LIST

    iterator.startIndex = firstIndex
    iterator.nextIndex = firstIndex
    iterator.multiMap = multiMap
}

Iterate :: proc(iterator: ^Iterator($Key, $Value)) -> bool {
    //profiler.MeasureThisScope()
    if iterator.nextIndex == END_OF_LIST {
        return false
    } else {
        iterator.value = iterator.multiMap.values[iterator.nextIndex]
        iterator.nextIndex = iterator.multiMap.nextIndex[iterator.nextIndex]
        return true
    }
}

@(private="file")
BIG_PRIME :: 23456789

@(private="file")
GetHash :: proc(key: $T) -> uint {
    bytes := mem.any_to_bytes(key)
    return uint(hash.crc32(bytes))
}