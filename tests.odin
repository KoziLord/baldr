package main

import "ecs"
import "queue"
import "multiMap"

import "core:fmt"
import "core:thread"
import "core:sync"

TestECSStuff :: proc() {
    entity1 := ecs.NewEntity()
    entity2 := ecs.NewEntity()
    
    ecs.AddComponent(entity2, Transform { position = 0, rotation = 0 })
    ecs.AddComponent(entity1, Transform { position = 5, rotation = 0})
    ecs.AddComponent(entity1, Health { health = 100 })

    updateTransformsSystem := ecs.CreateSystem({Transform}, UpdateTransformsTest)

    ecs.RunSystem(updateTransformsSystem)
    ecs.RunSystem(updateTransformsSystem)
    ecs.RunSystem(updateTransformsSystem)

    archetypesToTest : [][]typeid = {
        {Transform},
        {Health},
        {Health, Transform},
    }

    for typeSet in archetypesToTest {
        archetype := ecs.GetArchetype(typeSet)
        fmt.printf("count/capacity of %v: %v/%v\n", typeSet, archetype.count, archetype.capacity)
    }

    entity1Info := ecs.entityInfoLookup[entity1]
    fmt.printf("entity1's index in its archetype: %v\n", entity1Info.indexInArchetype)
}

UpdateTransformsTest :: proc(iterator: ^ecs.SystemIterator) {
    for ecs.Iterate(iterator) {
        transform := ecs.GetComponent(iterator, Transform)
        transform.position += 1
    }
}

@(private="file")
sum := 0

@(private="file")
testQueue: ^queue.Queue(int)

TestQueue :: proc() {
    testQueue = queue.Make(int, 10000)
    defer queue.Delete(testQueue)

    for i in 1..10000 {
        queue.Add(testQueue, i)
    }

    threadCount := 4
    threads := make([]^thread.Thread, threadCount)
    defer delete(threads)

    for i in 0..<threadCount {
        t := thread.create(DequeueWorker)
        t.user_index = i
        threads[i] = t
        thread.start(t)
    }

    for i in 0..<threadCount {
        for !thread.is_done(threads[i]) {
            //wait
        }
        thread.destroy(threads[i])
    }
    
    fmt.printf("queue-count: %v, sum: %v\n", testQueue.count, sum)
}

DequeueWorker :: proc(t: ^thread.Thread) {
    for testQueue.count > 0 {
        if value, ok := queue.Read(testQueue); ok {
            sync.atomic_add(&sum, value, .Sequentially_Consistent)
        }
    }
}



TestMultiMap :: proc() {
    buckets := multiMap.Make(int2, int, 200)

    for x in 0..5 {
        for y in 0..5 {
            for i in 0..<x {
                multiMap.Add(buckets, int2 {x,y}, 10*i)
            }
        }
    }

    iterator := multiMap.SetupIterator(buckets, int2 {5,5})

    for multiMap.Iterate(&iterator) {
        fmt.printf("%v\n", iterator.value)
    }

    fmt.println("second round")
    multiMap.Clear(buckets)

    for x in 0..5 {
        for y in 0..5 {
            for i in 0..<x*2 {
                multiMap.Add(buckets, int2{x,y}, 20*i)
            }
        }
    }

    iterator = multiMap.SetupIterator(buckets, int2 {5,5})

    for multiMap.Iterate(&iterator) {
        fmt.printf("%v\n", iterator.value)
    }

    multiMap.Delete(buckets)

    fmt.println("multi-map test complete")
}

