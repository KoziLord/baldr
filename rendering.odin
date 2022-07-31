package main

import "ecs"
import "profiler"

import "core:strings"
import "core:fmt"
import "core:math"

asciiWidth :: 50
asciiHeight :: 25

charsPerRow :: asciiWidth+1

sb := strings.make_builder_len(charsPerRow * asciiHeight)
heatmap : [asciiWidth * asciiHeight]int = 0

collectBoidsSystem: ecs.SystemID
collectBulletsSystem: ecs.SystemID

minPos, maxPos, fieldSize: float2

InitIfNeeded :: proc() {
    if (ecs.IsNil(collectBoidsSystem)) {
        collectBoidsSystem = ecs.CreateSystem({Boid, Transform}, CollectBoids)
    }
    if (ecs.IsNil(collectBulletsSystem)) {
        collectBulletsSystem = ecs.CreateSystem({Bullet, Transform}, CollectBullets)
    }
}

WriteWorldToConsole :: proc() {
    profiler.MeasureThisScope("Render Systems")
    InitIfNeeded()

    heatmap = 0

    ecs.RunSystem(collectBoidsSystem)
    ecs.RunSystem(collectBulletsSystem)

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
                if heat == -1 {
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

CollectBoids :: proc(iterator: ^ecs.SystemIterator) {
    for ecs.Iterate(iterator) {
        transform := ecs.GetComponent(iterator, Transform)
        if iterator.isFirstEntity {
            minPos = transform.position
            maxPos = transform.position
        } else {
            minPos = Min(minPos, transform.position)
            maxPos = Max(maxPos, transform.position)
        }
    }
    
    minPos -= 5
    maxPos += 5
    fieldSize = maxPos - minPos

    ecs.ResetIterator(iterator)

    for ecs.Iterate(iterator) {
        transform := ecs.GetComponent(iterator, Transform)
        cell := HeatmapCell(transform.position)
        heatmap[cell.y*asciiWidth + cell.x] += 1
    }
}

CollectBullets :: proc(iterator: ^ecs.SystemIterator) {
    for ecs.Iterate(iterator) {
        transform := ecs.GetComponent(iterator, Transform)
        cell, ok := HeatmapCell(transform.position)
        if ok {
            heatmap[cell.y*asciiWidth + cell.x] = -1
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