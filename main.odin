package main

import "ecs"
import "profiler"
import "multiMap"

import "core:math"
import "core:math/rand"
import "core:fmt"
import "core:time"
import "core:strings"

float2 :: [2]f64
int2 :: [2]int
Optional :: ecs.Optional

teamCount :: 5
boidsPerTeam :: 200
CELL_SIZE :: 20.0


boidBuckets : ^multiMap.MultiMap(int2, BucketPayload)

Boid :: struct {
    speed: f64,
    shootTimer: int,
    target: Optional(ecs.EntityID),
}

Bullet :: struct {
    velocity: float2,
    life: int,
}

TeamID :: distinct int

Transform :: struct {
    position: float2,
    rotation: f64,
}

BucketPayload :: struct {
    entity: ecs.EntityID,
    using transform: Transform,
    team: TeamID,
}

Health :: struct {
    health: int,
}

ExplosionParticle :: struct {
    position: float2,
    velocity: float2,
    life: f64,
}

main :: proc() {
    TestECSStuff()
    TestQueue()
    TestMultiMap()

    RunBoidsSimulation()
}

RunBoidsSimulation :: proc() {
    for i in 0..<teamCount {
        for j in 0..<boidsPerTeam {
            boid := ecs.NewEntity()
            ecs.AddComponent(boid, Boid {
                speed = 1,
            })
            ecs.AddComponent(boid, TeamID(i))
            ecs.AddComponent(boid, Transform {
                position = GetSpawnPosition(i, j),
                rotation = GetTeamRotation(i),
            })
            ecs.AddComponent(boid, Health {
                health = 4,
            })
        }
    }

    boidBuckets = multiMap.Make(int2, BucketPayload, teamCount * boidsPerTeam * 2)

    updateBoidsSystem := ecs.CreateSystem({Boid, Transform, TeamID}, UpdateBoids)
    updateBulletsSystem := ecs.CreateSystem({Bullet, Transform, TeamID}, UpdateBullets)
    updateExplosionsSystem := ecs.CreateSystem({ExplosionParticle}, UpdateExplosions)

    for {
        profiler.StartOfFrame()

        {
            profiler.MeasureThisScope("Full Frame")

            ecs.RunSystem(updateBoidsSystem)
            ecs.RunSystem(updateBulletsSystem)
            ecs.RunSystem(updateExplosionsSystem)
    
            ecs.PerformScheduledEntityDeletions()
    
            WriteWorldToConsole()
        }

        profiler.EndOfFrame()

        time.sleep(5 * time.Millisecond)
    }
}

UpdateBoids :: proc(iterator: ^ecs.SystemIterator) {
    profiler.MeasureThisScope("Boids System")

    {
        profiler.MeasureThisScope("Write Buckets")
        multiMap.Clear(boidBuckets)
        for ecs.Iterate(iterator) {
            transform := ecs.GetComponent(iterator, Transform)
            team := ecs.GetComponent(iterator, TeamID)
            cell := GetBucketCell(transform.position)
            payload := BucketPayload {
                entity = iterator.entity,
                transform = transform^,
                team = team^,
            }
            multiMap.Add(boidBuckets, cell, payload)
        }
        ecs.ResetIterator(iterator)
    }

    
    {
        profiler.MeasureThisScope("Update Boids")
        for ecs.Iterate(iterator) {
            entity := iterator.entity
            boid := ecs.GetComponent(iterator, Boid)
            team := ecs.GetComponent(iterator, TeamID)
            transform := ecs.GetComponent(iterator, Transform)

            if boid.target == nil {
                boid.target = ecs.GetRandomEntity(iterator)
                targetEntity, ok := boid.target.(ecs.EntityID)
                if ok {
                    targetTeam := ecs.GetComponent(targetEntity, TeamID)
                    if targetTeam == team {
                        boid.target = nil
                    }
                }
            }
        
            lookaheadDist := 10.0

            forward := GetDirection(transform.rotation)

            lookaheadPos := transform.position + forward*lookaheadDist
    
            avgNearbyPos: float2 = 0
            nearbyCount := 0
    
            minCell := GetBucketCell(lookaheadPos - lookaheadDist)
            maxCell := GetBucketCell(lookaheadPos + lookaheadDist)

            for x in minCell.x..maxCell.x {
                for y in minCell.y..maxCell.y {
                    cell := int2 {x,y}

                    bucketIterator := multiMap.SetupIterator(boidBuckets, cell)
                    for multiMap.Iterate(&bucketIterator) {
                        payload := bucketIterator.value
                        if payload.entity != entity {
                            avgNearbyPos += payload.position
                            nearbyCount += 1
                        }
                    }
                }
            }
        
            if nearbyCount > 0 {
                //profiler.MeasureThisScope("Steering")
                avgNearbyPos /= f64(nearbyCount)
                delta := avgNearbyPos - transform.position
                angleToGroup := GetAngle(delta)
                
                transform.rotation += AngleDiff(angleToGroup, transform.rotation) * .005
                
                transform.rotation += rand.float64_range(-1, 1)*.1
                
                transform.rotation -= math.floor((transform.rotation + math.PI) / (math.PI*2)) * math.PI*2
            }
            
            target, hasTarget := boid.target.(ecs.EntityID)
            if hasTarget {
                if ecs.IsNil(target) {
                    boid.target = nil
                } else {
                    targetTransform := ecs.GetComponent(target, Transform)
                    angleToTarget := GetAngle(targetTransform.position - transform.position)
                    angleDiff := AngleDiff(angleToTarget, transform.rotation)
                    transform.rotation += angleDiff * .005
                    
                    boid.shootTimer -= 1
                    if boid.shootTimer <= 0 {
                        if abs(angleDiff) < .1 {
                            ShootBullet(transform.position, transform.rotation, team^)
                            boid.shootTimer = 20
                        }
                    }
                }
            }
            
            transform.position += forward * boid.speed
        }
    }
}

UpdateBullets :: proc(iterator: ^ecs.SystemIterator) {
    profiler.MeasureThisScope()
    
    deleteCount := 0
    for ecs.Iterate(iterator) {
        bullet := ecs.GetComponent(iterator, Bullet)
        transform := ecs.GetComponent(iterator, Transform)
        team := ecs.GetComponent(iterator, TeamID)^

        minCell := GetBucketCell(Min(transform.position,
                                     transform.position+bullet.velocity) - 2)
        maxCell := GetBucketCell(Max(transform.position,
                                     transform.position+bullet.velocity) + 2)
        
        bucketLoop:
        for x in minCell.x .. maxCell.x {
            for y in minCell.y .. maxCell.y {
                cell := int2{x,y}
                
                bucketIterator := multiMap.SetupIterator(boidBuckets, cell)
                for multiMap.Iterate(&bucketIterator) {
                    payload := bucketIterator.value
                    if payload.team != team {
                        boidPos := payload.transform.position
                        delta := boidPos - transform.position
                        t := Dot(delta, bullet.velocity) / SqrLength(bullet.velocity)
                        closePoint := transform.position + bullet.velocity*t
                        deltaToClosePoint := closePoint - boidPos
                        if SqrLength(deltaToClosePoint) < 1 {
                            health := ecs.GetComponent(payload.entity, Health)
                            health.health -= 1
                            if health.health <= 0 {
                                ecs.ScheduleEntityDeletion(payload.entity)
                                SpawnExplosion(boidPos)
                            }
                            bullet.life = 0
                            break bucketLoop
                        }
                    }
                }
            }
        }

        transform.position += bullet.velocity
        bullet.life -= 1
        if bullet.life < 0 {
            ecs.ScheduleEntityDeletion(iterator.entity)
            deleteCount += 1
        }
    }
}

UpdateExplosions :: proc(iterator: ^ecs.SystemIterator) {
    for ecs.Iterate(iterator) {
        particle := ecs.GetComponent(iterator, ExplosionParticle)
        
        particle.life -= .05
        particle.position += particle.velocity
        particle.velocity *= .85

        if particle.life <= 0 {
            ecs.ScheduleEntityDeletion(iterator.entity)
        }
    }
}

ShootBullet :: proc(position: float2, rotation: f64, team: TeamID) {
    entity := ecs.NewEntity()
    ecs.AddComponent(entity, Transform {
        position = position,
        rotation = rotation,
    })
    ecs.AddComponent(entity, Bullet {
        velocity = GetDirection(rotation) * 10,
        life = 100,
    })
    ecs.AddComponent(entity, team)
}

SpawnExplosion :: proc(position: float2) {
    for i in 0..<30  {
        angle := rand.float64() * math.PI*2
        speed := rand.float64() * 10
        velocity := GetDirection(angle) * speed

        entity := ecs.NewEntity()
        ecs.AddComponent(entity, ExplosionParticle {
            position = position,
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