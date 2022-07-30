package main

import "ecs"
import "core:strings"
import "core:fmt"
import "core:math"

asciiWidth :: 50
asciiHeight :: 25

charsPerRow :: asciiWidth+1

sb := strings.make_builder_len(charsPerRow * asciiHeight)
heatmap : [asciiWidth * asciiHeight]int = 0

collectBoidsSystem : ecs.SystemID

InitIfNeeded :: proc() {
    if (ecs.IsNil(collectBoidsSystem)) {
        collectBoidsSystem = ecs.CreateSystem({Boid, Transform}, CollectBoids)
    }
}

WriteWorldToConsole :: proc() {
    InitIfNeeded()

    heatmap = 0

    ecs.RunSystem(collectBoidsSystem)

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
                if heat == 0 {
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
    minPos, maxPos: float2

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
    fieldSize := maxPos - minPos

    ecs.ResetIterator(iterator)

    for ecs.Iterate(iterator) {
        transform := ecs.GetComponent(iterator, Transform)
        normalizedPos := (transform.position - minPos) / fieldSize

        cell : [2]int = Floor(normalizedPos * float2 {asciiWidth, asciiHeight})
        heatmap[cell.y*asciiWidth + cell.x] += 1
    }
}


Min :: proc(a, b: float2) -> float2 {
    return float2 {
        min(a.x, b.x),
        min(a.y, b.y),
    }
}

Max :: proc(a, b: float2) -> float2 {
    return float2 {
        max(a.x, b.x),
        max(a.y, b.y),
    }
}

Floor :: proc(vector: float2) -> int2 {
    return int2 {
        int(math.floor(vector.x)),
        int(math.floor(vector.y)),
    }
}