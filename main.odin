package main

import "ECS"
import "Profiler"
import "MultiMap"
import "Transform"

import "core:math"
import "core:math/rand"
import "core:fmt"
import "core:time"
import "core:strings"

float2 :: [2]f64
float3 :: [3]f64
int2 :: [2]int
Optional :: ECS.Optional

teamCount :: 5
boidsPerTeam :: 200
CELL_SIZE :: 20.0


boidBuckets : ^MultiMap.MultiMap(int2, BucketPayload)

Boid :: struct {
    speed: f64,
    shootTimer: int,
    target: Optional(ECS.EntityID),
}

Bullet :: struct {
    velocity: float2,
    life: int,
}

TeamID :: distinct int

BucketPayload :: struct {
    entity: ECS.EntityID,
    using transform: Transform2D,
    team: TeamID,
}

Health :: struct {
    health: int,
}

ExplosionParticle :: struct {
    velocity: float2,
    life: f64,
}

Transform2D :: Transform.Transform2D

main :: proc() {
    TestECSStuff()
    TestQueue()
    TestMultiMap()
    TestTransforms()

    RunBoidsSimulation()

}

RunBoidsSimulation :: proc() {
    for i in 0..<teamCount {
        for j in 0..<boidsPerTeam {
            boid := ECS.NewEntity()
            ECS.AddComponent(boid, Boid {
                speed = 1,
            })
            ECS.AddComponent(boid, TeamID(i))
            ECS.AddComponent(boid, Transform.Make2D(
                GetSpawnPosition(i, j),
                GetTeamRotation(i),
            ))
            ECS.AddComponent(boid, Health {
                health = 4,
            })
        }
    }

    boidBuckets = MultiMap.Make(int2, BucketPayload, teamCount * boidsPerTeam * 2)

    updateBoidsSystem := ECS.CreateSystem({Boid, Transform2D, TeamID}, UpdateBoids)
    updateBulletsSystem := ECS.CreateSystem({Bullet, Transform2D, TeamID}, UpdateBullets)
    updateExplosionsSystem := ECS.CreateSystem({ExplosionParticle, Transform2D}, UpdateExplosions)

    for {
        Profiler.StartOfFrame()

        {
            Profiler.MeasureThisScope("Full Frame")

            ECS.RunSystem(updateBoidsSystem)
            ECS.RunSystem(updateBulletsSystem)
            ECS.RunSystem(updateExplosionsSystem)
    
            ECS.PerformScheduledEntityDeletions()
    
            WriteWorldToConsole()
        }

        Profiler.EndOfFrame()

        time.sleep(5 * time.Millisecond)
    }
}

UpdateBoids :: proc(iterator: ^ECS.SystemIterator) {
    Profiler.MeasureThisScope("Boids System")

    {
        Profiler.MeasureThisScope("Write Buckets")
        MultiMap.Clear(boidBuckets)
        for ECS.Iterate(iterator) {
            transform := ECS.GetComponent(iterator, Transform2D)
            team := ECS.GetComponent(iterator, TeamID)
            cell := GetBucketCell(transform.localPosition)
            payload := BucketPayload {
                entity = iterator.entity,
                transform = transform^,
                team = team^,
            }
            MultiMap.Add(boidBuckets, cell, payload)
        }
        ECS.ResetIterator(iterator)
    }

    
    {
        Profiler.MeasureThisScope("Update Boids")
        for ECS.Iterate(iterator) {
            entity: ECS.EntityID
            boid: ^Boid
            team: ^TeamID
            transform: ^Transform2D
            {
                //profiler.MeasureThisScope("get components, write buckets")
                entity = iterator.entity
                boid = ECS.GetComponent(iterator, Boid)
                team = ECS.GetComponent(iterator, TeamID)
                transform = ECS.GetComponent(iterator, Transform2D)
    
                if boid.target == nil {
                    boid.target = ECS.GetRandomEntity(iterator)
                    targetEntity, ok := boid.target.(ECS.EntityID)
                    if ok {
                        targetTeam := ECS.GetComponent(targetEntity, TeamID)
                        if targetTeam == team {
                            boid.target = nil
                        }
                    }
                }
            }
        
            avgNearbyPos: float2 = 0
            nearbyCount := 0
            forward := GetDirection(transform.localRotation)

            {
                //profiler.MeasureThisScope("Get buckets")
                lookaheadDist := 10.0
    
    
                lookaheadPos := transform.localPosition + forward*lookaheadDist
        
        
                minCell := GetBucketCell(lookaheadPos - lookaheadDist)
                maxCell := GetBucketCell(lookaheadPos + lookaheadDist)
    
                for x in minCell.x..maxCell.x {
                    for y in minCell.y..maxCell.y {
                        cell := int2 {x,y}
    
                        bucketIterator := MultiMap.SetupIterator(boidBuckets, cell)
                        for MultiMap.Iterate(&bucketIterator) {
                            payload := bucketIterator.value
                            if payload.entity != entity {
                                avgNearbyPos += payload.localPosition
                                nearbyCount += 1
                            }
                        }
                    }
                }
            }
        
            if nearbyCount > 0 {
                //profiler.MeasureThisScope("Steering")
                avgNearbyPos /= f64(nearbyCount)
                delta := avgNearbyPos - transform.localPosition
                angleToGroup := GetAngle(delta)
                
                transform.localRotation += AngleDiff(angleToGroup, transform.localRotation) * .005
                
                transform.localRotation += rand.float64_range(-1, 1)*.1
                
                transform.localRotation -= math.floor((transform.localRotation + math.PI) / (math.PI*2)) * math.PI*2
            }
            
            target, hasTarget := boid.target.(ECS.EntityID)
            if hasTarget {
                //profiler.MeasureThisScope("Follow target")
                if ECS.IsNil(target) {
                    boid.target = nil
                } else {
                    targetTransform := ECS.GetComponent(target, Transform2D)
                    angleToTarget := GetAngle(targetTransform.localPosition - transform.localPosition)
                    angleDiff := AngleDiff(angleToTarget, transform.localRotation)
                    transform.localRotation += angleDiff * .005
                    
                    boid.shootTimer -= 1
                    if boid.shootTimer <= 0 {
                        if abs(angleDiff) < .1 {
                            //profiler.MeasureThisScope("Shoot bullets")
                            ShootBullet(transform.localPosition, transform.localRotation, team^)
                            boid.shootTimer = 20
                        }
                    }
                }
            }
            
            transform.localPosition += forward * boid.speed
        }
    }
}

UpdateBullets :: proc(iterator: ^ECS.SystemIterator) {
    Profiler.MeasureThisScope()
    
    deleteCount := 0
    for ECS.Iterate(iterator) {
        bullet := ECS.GetComponent(iterator, Bullet)
        transform := ECS.GetComponent(iterator, Transform2D)
        team := ECS.GetComponent(iterator, TeamID)^

        minCell := GetBucketCell(Min(transform.localPosition,
                                     transform.localPosition+bullet.velocity) - 2)
        maxCell := GetBucketCell(Max(transform.localPosition,
                                     transform.localPosition+bullet.velocity) + 2)
        
        bucketLoop:
        for x in minCell.x .. maxCell.x {
            for y in minCell.y .. maxCell.y {
                cell := int2{x,y}
                
                bucketIterator := MultiMap.SetupIterator(boidBuckets, cell)
                for MultiMap.Iterate(&bucketIterator) {
                    payload := bucketIterator.value
                    if payload.team != team {
                        boidPos := payload.transform.localPosition
                        delta := boidPos - transform.localPosition
                        t := Dot(delta, bullet.velocity) / SqrLength(bullet.velocity)
                        closePoint := transform.localPosition + bullet.velocity*t
                        deltaToClosePoint := closePoint - boidPos
                        if SqrLength(deltaToClosePoint) < 1 {
                            health := ECS.GetComponent(payload.entity, Health)
                            health.health -= 1
                            if health.health <= 0 {
                                ECS.ScheduleEntityDeletion(payload.entity)
                                SpawnExplosion(boidPos)
                            }
                            bullet.life = 0
                            break bucketLoop
                        }
                    }
                }
            }
        }

        transform.localPosition += bullet.velocity
        bullet.life -= 1
        if bullet.life < 0 {
            ECS.ScheduleEntityDeletion(iterator.entity)
            deleteCount += 1
        }
    }
}

UpdateExplosions :: proc(iterator: ^ECS.SystemIterator) {
    for ECS.Iterate(iterator) {
        particle := ECS.GetComponent(iterator, ExplosionParticle)
        transform := ECS.GetComponent(iterator, Transform2D)
        
        particle.life -= .05
        transform.localPosition += particle.velocity
        particle.velocity *= .85

        if particle.life <= 0 {
            ECS.ScheduleEntityDeletion(iterator.entity)
        }
    }
}

ShootBullet :: proc(position: float2, rotation: f64, team: TeamID) {
    entity := ECS.NewEntity()
    ECS.AddComponent(entity, Transform2D {
        localPosition = position,
        localRotation = rotation,
    })
    ECS.AddComponent(entity, Bullet {
        velocity = GetDirection(rotation) * 10,
        life = 100,
    })
    ECS.AddComponent(entity, team)
}

SpawnExplosion :: proc(position: float2) {
    for i in 0..<30  {
        angle := rand.float64() * math.PI*2
        speed := rand.float64() * 10
        velocity := GetDirection(angle) * speed

        entity := ECS.NewEntity()
        ECS.AddComponent(entity, Transform2D {
            localPosition = position,
        })
        ECS.AddComponent(entity, ExplosionParticle {
            velocity = velocity,
            life = rand.float64_range(0.5, 1.0),
        })
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

GetBucketCell :: proc(position: float2) -> int2 {
    return Floor(position / CELL_SIZE)
}