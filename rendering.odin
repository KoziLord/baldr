package main

import "ECS"
import "Profiler"
import "Transform"

import "core:strings"
import "core:fmt"
import "core:math"

asciiWidth :: 100
asciiHeight :: 50

charsPerRow :: asciiWidth+1

sb := strings.make_builder_len(charsPerRow * asciiHeight)
heatmap : [asciiWidth * asciiHeight]int = 0

collectBoidsSystem := ECS.CreateSystem({Boid, Transform2D}, CollectBoids)
collectBulletsSystem := ECS.CreateSystem({Bullet, Transform2D}, CollectBullets)
collectParticlesSystem := ECS.CreateSystem({ExplosionParticle, Transform2D}, CollectParticles)

minPos, maxPos, fieldSize: float2

WriteWorldToConsole :: proc() {
    Profiler.MeasureThisScope("Render Systems")

    heatmap = 0

    ECS.RunSystem(collectBoidsSystem)
    ECS.RunSystem(collectBulletsSystem)
    ECS.RunSystem(collectParticlesSystem)

    totalCount := 0

    for y in 0..<asciiHeight {
        for x in 0..asciiWidth {
            index := y * charsPerRow + x
            if x == asciiWidth {
                sb.buf[index] = '\n'
            } else {
                heat := heatmap[y*asciiWidth + x]
                totalCount += heat
                heat = min(heat, 35)
                if heat == -2 {
                    sb.buf[index] = '#'
                } else if heat == -1 {
                    sb.buf[index] = '*'
                } else if heat == 0 {
                    sb.buf[index] = ' '
                } else if heat < 10 {
                    sb.buf[index] = '0' + u8(heat)
                } else if heat < 36 {
                    sb.buf[index] = 'A' + u8(heat - 10)
                }
            }
        }
    }

    //fmt.print('\n')
    fmt.println(strings.to_string(sb))
    //fmt.printf("\nrendered boid count: %v\n", totalCount)
}

CollectBoids :: proc(iterator: ^ECS.SystemIterator) {
    for ECS.Iterate(iterator) {
        transform := ECS.GetComponent(iterator, Transform2D)
        worldPos: float2 = Transform.GetWorldPos(transform).xy

        if iterator.isFirstEntity {
            minPos = worldPos
            maxPos = worldPos
        } else {
            minPos = Min(minPos, worldPos)
            maxPos = Max(maxPos, worldPos)
        }
    }
    
    minPos -= 5
    maxPos += 5
    fieldSize = maxPos - minPos

    ECS.ResetIterator(iterator)

    for ECS.Iterate(iterator) {
        transform := ECS.GetComponent(iterator, Transform2D)

        cell := HeatmapCell(Transform.GetWorldPos(transform).xy)
        heatmap[cell.y*asciiWidth + cell.x] += 1
    }
}

CollectBullets :: proc(iterator: ^ECS.SystemIterator) {
    for ECS.Iterate(iterator) {
        transform := ECS.GetComponent(iterator, Transform2D)

        cell, ok := HeatmapCell(Transform.GetWorldPos(transform).xy)
        if ok {
            heatmap[cell.y*asciiWidth + cell.x] = -1
        }
    }
}

CollectParticles :: proc(iterator: ^ECS.SystemIterator) {
    for ECS.Iterate(iterator) {
        transform := ECS.GetComponent(iterator, Transform2D)
        
        cell, ok := HeatmapCell(Transform.GetWorldPos(transform).xy)
        if ok {
            heatmap[cell.y*asciiWidth + cell.x] = -2
        }
    }
}

HeatmapCell :: proc(position: float2) -> (int2, bool) #optional_ok {
    if position.x < minPos.x || position.y < minPos.y || position.x >= maxPos.x || position.y >= maxPos.y {
        return 0, false
    }
    normalizedPos := (position - minPos) / fieldSize
    cell := Floor(normalizedPos * float2 {asciiWidth, asciiHeight})
    return cell, true
}