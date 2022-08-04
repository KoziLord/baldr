package main

import "ECS"
import "Queue"
import "MultiMap"
import "Transform"

import "core:fmt"
import "core:thread"
import "core:sync"

TestECSStuff :: proc() {
    entity1 := ECS.NewEntity()
    entity2 := ECS.NewEntity()
    
    ECS.AddComponent(entity2, Transform2D { localPosition = 0, localRotation = 0 })
    ECS.AddComponent(entity1, Transform2D { localPosition = 5, localRotation = 0})
    ECS.AddComponent(entity1, Health { health = 100 })

    updateTransformsSystem := ECS.CreateSystem({Transform2D}, UpdateTransformsTest)

    ECS.RunSystem(updateTransformsSystem)
    ECS.RunSystem(updateTransformsSystem)
    ECS.RunSystem(updateTransformsSystem)

    archetypesToTest : [][]typeid = {
        {Transform2D},
        {Health},
        {Health, Transform2D},
    }

    for typeSet in archetypesToTest {
        archetype := ECS.GetArchetype(typeSet)
        fmt.printf("count/capacity of %v: %v/%v\n", typeSet, archetype.count, archetype.capacity)
    }

    entity1Info := ECS.entityInfoLookup[entity1]
    fmt.printf("entity1's index in its archetype: %v\n", entity1Info.indexInArchetype)
}

UpdateTransformsTest :: proc(iterator: ^ECS.SystemIterator) {
    for ECS.Iterate(iterator) {
        transform := ECS.GetComponent(iterator, Transform2D)
        transform.localPosition += 1
    }
}

@(private="file")
sum := 0

@(private="file")
testQueue: ^Queue.Queue(int)

TestQueue :: proc() {
    testQueue = Queue.Make(int, 10000)
    defer Queue.Delete(testQueue)

    for i in 1..10000 {
        Queue.Add(testQueue, i)
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
        if value, ok := Queue.Read(testQueue); ok {
            sync.atomic_add(&sum, value, .Sequentially_Consistent)
        }
    }
}



TestMultiMap :: proc() {
    buckets := MultiMap.Make(int2, int, 200)

    for x in 0..5 {
        for y in 0..5 {
            for i in 0..<x {
                MultiMap.Add(buckets, int2 {x,y}, 10*i)
            }
        }
    }

    iterator := MultiMap.SetupIterator(buckets, int2 {5,5})

    for MultiMap.Iterate(&iterator) {
        fmt.printf("%v\n", iterator.value)
    }

    fmt.println("second round")
    MultiMap.Clear(buckets)

    for x in 0..5 {
        for y in 0..5 {
            for i in 0..<x*2 {
                MultiMap.Add(buckets, int2{x,y}, 20*i)
            }
        }
    }

    iterator = MultiMap.SetupIterator(buckets, int2 {5,5})

    for MultiMap.Iterate(&iterator) {
        fmt.printf("%v\n", iterator.value)
    }

    MultiMap.Delete(buckets)

    fmt.println("multi-map test complete")
}

TestTransforms :: proc() {
    using ECS

    entity2D := NewEntity()
    entity3D := NewEntity()
    otherEntity3D := NewEntity()

    transform2D := AddComponent(entity2D,
                                Transform.Make2D(float2{3,7}, 0, 2))
    transform3D := AddComponent(entity3D,
                                Transform.Make3D(float3{10,20,30}, 1, 1))
    otherTransform3D := AddComponent(otherEntity3D,
                                     Transform.Make3D(float3{100,200,300}))

    transform2D.parent = entity3D
    transform3D.parent = otherEntity3D

    fmt.printf("2D localPos: %v\n2D worldPos: %v\n",
               transform2D.localPosition,
               Transform.GetWorldPos(transform2D))
    fmt.printf("3D localPos: %v\n3D worldPos: %v\n",
               transform3D.localPosition,
               Transform.GetWorldPos(transform3D))
    fmt.printf("other 3D localPos: %v\nother 3D worldPos: %v\n",
               otherTransform3D.localPosition,
               Transform.GetWorldPos(otherTransform3D))

    otherTransform3D.localPosition += 100
    fmt.printf("2D localPos: %v\n2D worldPos: %v\n",
               transform2D.localPosition,
               Transform.GetWorldPos(transform2D))
    
    fmt.printf("3D localPos: %v\n3D worldPos: %v\n",
               transform3D.localPosition,
               Transform.GetWorldPos(transform3D))
}

