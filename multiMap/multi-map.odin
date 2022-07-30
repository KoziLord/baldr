package multiMap

import "core:hash"
import "core:fmt"
import "core:mem"
import "core:runtime"

@(private="file")
END_OF_LIST :: -1

@(private="file")
NO_VALUE :: -2

MultiMap :: struct($Key, $Value: typeid) {
    firstIndex: map[Key]int,
    nextIndex: []int,
    values: []Value,
    capacity: int,
}

Make :: proc($Key, $Value: typeid, capacity: int, allocator: runtime.Allocator = context.allocator) -> ^MultiMap(Key, Value) {
    multiMap := new(MultiMap(Key, Value), allocator)

    multiMap.firstIndex = make(map[Key]int, capacity, allocator)
    multiMap.nextIndex = make([]int, capacity, allocator)
    multiMap.values = make([]Value, capacity, allocator)
    multiMap.capacity = capacity

    Clear(multiMap)

    return multiMap
}

Clear :: proc(multiMap: ^MultiMap($Key, $Value)) {
    for i in 0..<multiMap.capacity {
        multiMap.nextIndex[i] = NO_VALUE
    }
    for key, _ in multiMap.firstIndex {
        delete_key(&multiMap.firstIndex, key)
    }
}

Delete :: proc(multiMap: ^MultiMap($Key, $Value), allocator: runtime.Allocator = context.allocator) {
    delete(multiMap.firstIndex)
    delete(multiMap.nextIndex, allocator)
    delete(multiMap.values, allocator)
    free(multiMap)
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

    } else {
        // add to end of existing list
        index = firstIndex
        for multiMap.nextIndex[index] != END_OF_LIST {
            index = multiMap.nextIndex[index]
        }
        
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

MakeIterator :: proc(multiMap: ^MultiMap($Key, $Value), key: Key) -> ^Iterator(Key, Value) {
    firstIndex, ok := multiMap.firstIndex[key]

    if !ok do firstIndex = END_OF_LIST

    iterator := new(Iterator(Key, Value))
    iterator.startIndex = firstIndex
    iterator.nextIndex = firstIndex
    iterator.multiMap = multiMap
    return iterator
}

Iterate :: proc(iterator: ^Iterator($Key, $Value)) -> bool {
    if iterator.nextIndex == END_OF_LIST {
        return false
    } else {
        iterator.value = iterator.multiMap.values[iterator.nextIndex]
        iterator.nextIndex = iterator.multiMap.nextIndex[iterator.nextIndex]
        return true
    }
}

Iterator :: struct($Key, $Value: typeid) {
    multiMap: ^MultiMap(Key, Value),
    value: Value,
    startIndex: int,
    nextIndex: int,
}

@(private="file")
GetHash :: proc(key: $T) -> uint {
    bytes := mem.any_to_bytes(key)
    when size_of(uint) == 4 {
        return uint(hash.crc32(bytes))
    } else when size_of(uint) == 8 {
        return uint(hash.crc64_ecma_182(bytes))
    }
}