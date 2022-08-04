package Queue

import "core:runtime"
import "core:sync"
import "core:fmt"

AtomicAdd :: sync.atomic_add
AtomicCompareExchange :: sync.atomic_compare_exchange

Queue :: struct($T: typeid) {
    buffer: []T,
    allocator: runtime.Allocator,
    readIndex, writeIndex, count: uint,
}

Make :: proc($T: typeid, capacity: int, allocator: runtime.Allocator = context.allocator) -> ^Queue(T) {
    queue := new(Queue(T), allocator)

    // one extra slot: allows us to detect an overflow before it actually happens
    queue.buffer = make([]T, capacity + 1, allocator)
    
    queue.allocator = allocator
    return queue
}

Delete :: proc(queue: ^Queue($T)) {
    delete(queue.buffer, queue.allocator)
    free(queue, queue.allocator)
}

Add :: proc(queue: ^Queue($T), item: T) -> bool {
    readIndex := queue.readIndex
    writeIndex := sync.atomic_add(&queue.writeIndex, 1, .Sequentially_Consistent)
    if QueueIndex(queue, writeIndex+1) == QueueIndex(queue, readIndex) {
        fmt.println("Queue has overflowed!")
        return false
    }
    queue.buffer[QueueIndex(queue, writeIndex)] = item
    sync.atomic_add(&queue.count, 1, .Sequentially_Consistent)
    return true
}

Read :: proc(queue: ^Queue($T)) -> (T, bool) {
    oldCount := queue.count
    for oldCount > 0 {
        ok: bool
        oldCount, ok = AtomicCompareExchange(&queue.count,
                                             oldCount,
                                             oldCount-1,
                                             .Sequentially_Consistent,
                                             .Sequentially_Consistent)
        if ok {
            readIndex := sync.atomic_add(&queue.readIndex, 1, .Sequentially_Consistent)
            return queue.buffer[QueueIndex(queue, readIndex)], true
        }
    }
    return {}, false
}

@(private="file")
QueueIndexUint :: proc(queue: ^Queue($T), index: uint) -> uint {
    return index % uint(len(queue.buffer))
}

@(private="file")
QueueIndexInt :: proc(queue: ^Queue($T), index: int) -> int {
    return index % len(queue.buffer)
}

@(private="file")
QueueIndex :: proc {
    QueueIndexUint,
    QueueIndexInt,
}