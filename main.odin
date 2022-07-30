package main

import "ecs"
import "profiler"

import "core:math"
import "core:math/rand"
import "core:fmt"
import "core:time"
import "core:strings"

float2 :: [2]f64
int2 :: [2]int

teamCount :: 5
boidsPerTeam :: 200

boidBuckets : ^ecs.BucketMap

Boid :: struct {
    speed: f64,
    team: int,
}

Transform :: struct {
    position: float2,
    rotation: f64,
}

Health :: struct {
    health: f64,
}

main :: proc() {
    //TestECSStuff()
    //TestQueue()

    for i in 0..<teamCount {
        for j in 0..<boidsPerTeam {
            boid := ecs.NewEntity()
            ecs.AddComponent(boid, Boid{
                speed = 1,
                team = i,
            })
            ecs.AddComponent(boid, Transform {
                position = GetSpawnPosition(i, j),
                rotation = GetTeamRotation(i),
            })
            ecs.AddComponent(boid, Health {
                health = 100,
            })
        }
    }

    boidBuckets = ecs.CreateBucketMap(8.0)

    updateBoidsSystem := ecs.CreateSystem({Boid, Transform}, UpdateBoids)

    for i in 0..<2000 {
        profiler.StartOfFrame()

        ecs.RunSystem(updateBoidsSystem)

        WriteWorldToConsole()

        profiler.EndOfFrame()

        time.sleep(16 * time.Millisecond)
    }
}

GetTransformBounds :: proc(transform: Transform) -> (min: float2, max: float2) {
    min = transform.position
    max = transform.position
    return
}

UpdateBoids :: proc(iterator: ^ecs.SystemIterator) {
    profiler.MeasureThisScope()

    {
        profiler.MeasureThisScope("Write Buckets")
        ecs.WriteBuckets(boidBuckets, iterator, Transform, GetTransformBounds)
    }

    lookaheadDist := 20.0

    for ecs.Iterate(iterator) {
        entity := iterator.entity
        boid := ecs.GetComponent(iterator, Boid)
        transform := ecs.GetComponent(iterator, Transform)

        forward := GetDirection(transform.rotation)

        {
            profiler.MeasureThisScope("Iterate Buckets")
            lookaheadPos := transform.position + forward*lookaheadDist
    
            avgNearbyPos: float2 = 0
            nearbyCount := 0
    
            bucketIterator := ecs.GetBucketIterator(boidBuckets,
                                                    lookaheadPos-lookaheadDist,
                                                    lookaheadPos+lookaheadDist)
    
            for ecs.Iterate(bucketIterator) {
                //profiler.MeasureThisScope("Tap Nearby Boid")
                if bucketIterator.entity != entity {
                    otherTransform := ecs.GetComponent(bucketIterator, Transform)
                    avgNearbyPos += otherTransform.position
                    nearbyCount += 1
                }
            }
            
            if nearbyCount > 0 {
                profiler.MeasureThisScope("Steering")
                avgNearbyPos /= f64(nearbyCount)
                delta := avgNearbyPos - transform.position
                targetAngle := GetAngle(delta)
                if targetAngle - transform.rotation > math.PI {
                    targetAngle -= math.PI*2
                }
                if targetAngle - transform.rotation < -math.PI {
                    targetAngle += math.PI*2
                }
                
                transform.rotation += (targetAngle - transform.rotation) * .005
                transform.rotation += rand.float64_range(-1, 1)*.1
                
                transform.rotation -= math.floor((transform.rotation + math.PI) / (math.PI*2)) * math.PI*2
            }
        }
            

        transform.position += forward * boid.speed
    }


}


GetSpawnPosition :: proc(team: int, indexOnTeam: int) -> float2 {
    forwardAngle := GetTeamRotation(team)
    forward := GetDirection(forwardAngle)
    perp := forward.yx * float2 {1, -1}
    basePos := -forward * boidsPerTeam
    xOffset := f64(indexOnTeam) - f64(boidsPerTeam - 1) * .5
    return basePos + xOffset*perp
}

GetTeamRotation :: proc(team: int) -> f64 {
    t := f64(team) / f64(teamCount)
    return math.PI * 2 * t
}

GetAngle :: proc(direction: float2) -> f64 {
    return math.atan2(direction.y, direction.x)
}

GetDirection :: proc(angle: f64) -> float2 {
    return float2 {
        math.cos(angle),
        math.sin(angle),
    }
}