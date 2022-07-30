package profiler

import "../queue"

import "core:time"
import "core:runtime"
import "core:fmt"
import "core:path/filepath"
import "core:sort"
import "core:sync"
import "core:thread"

@(private="file")
PROFILER_ENABLED :: #config(PROFILER, false)

Queue :: ^queue.Queue

@(private="file")
CodeLocation :: runtime.Source_Code_Location

@(private="file")
Measurement :: struct {
    startTime: time.Time,
    caller: CodeLocation,
    label: string,
    depth: int,
}

@(private="file")
ScopeCost :: struct {
    codeLocation: CodeLocation,
    totalDuration: time.Duration,
    tapCount: int,
    longestDuration: time.Duration,
    label: string,
    addOrder: int,
    depth: int,
}

@(private="file")
Command :: struct {
    commandType: CommandType,
    measurement: Measurement,
    duration: time.Duration,
}

@(private="file")
CommandType :: enum {
    StartScope,
    EndScope,
}

@(private="file")
scopes: map[CodeLocation]ScopeCost

@(private="file")
currentDepth: int

@(private="file")
commandQueue := queue.Make(Command, 60000)

@(private="file")
activeThread : ^thread.Thread

StartOfFrame :: proc() {
    when PROFILER_ENABLED {
        scopes = make(map[CodeLocation]ScopeCost, 50)
        currentDepth = 0
    
        activeThread = thread.create(Worker, .High)
        
        goSignal := new(bool)
        goSignal^ = true
        activeThread.user_args[0] = cast(rawptr)goSignal
        thread.start(activeThread)
    }
}

EndOfFrame :: proc() {
    when PROFILER_ENABLED {
        goSignal := cast(^bool)activeThread.user_args[0]
        goSignal^ = false
    
        for thread.is_done(activeThread) == false {
            // wait for thread to finish
        }
        free(activeThread.user_args[0])
        thread.destroy(activeThread)
    
        //fmt.printf("queue count after worker finished: %v\n", commandQueue.count)
    
        sortedScopes := make([]ScopeCost, len(scopes))
        
        i := 0
        for _, scope in scopes {
            sortedScopes[i] = scope
            i += 1
        }
    
        sort.quick_sort_proc(sortedScopes, proc(a, b: ScopeCost) -> int {
            return sort.compare_ints(a.addOrder, b.addOrder)
        })
    
        for scope in sortedScopes {
            for _ in 0..<scope.depth {
                fmt.print("  ");
            }
            fmt.printf("%v: %vms (taps: %v, worst: %vms)\n",
                       ResolveLabel(scope),
                       time.duration_milliseconds(scope.totalDuration),
                       scope.tapCount,
                       time.duration_milliseconds(scope.longestDuration))
        }
    
        delete(scopes)
        delete(sortedScopes)
    }
}

@(deferred_out=ScopeFinished)
MeasureThisScope :: proc(label:string = "", caller := #caller_location) -> Measurement {
    when PROFILER_ENABLED {
        //fmt.printf("starting scope: %v\n", caller)
        measurement: Measurement
        measurement.startTime = time.now()
        measurement.caller = caller
        measurement.label = label
        measurement.depth = currentDepth
    
        command := Command {
            commandType = .StartScope,
            measurement = measurement,
        }
    
        queue.Add(commandQueue, command)
    
        currentDepth += 1
    
        return measurement
    } else {
        return {}
    }
}

@(private="file")
ScopeFinished :: proc(measurement: Measurement) {
    when PROFILER_ENABLED {
        duration := time.since(measurement.startTime)
    
        command := Command {
            commandType = .EndScope,
            measurement = measurement,
            duration = duration,
        }
        queue.Add(commandQueue, command)
    
        currentDepth -= 1
    }
}

@(private="file")
@(deferred_out=FreeLabel)
ResolveLabel :: proc(scope: ScopeCost) -> (result: string, allocated: bool) #optional_ok {
    if scope.label != "" {
        return scope.label, false
    } else {
        label := fmt.aprintf("%v (%v L%v)",
                             scope.codeLocation.procedure,
                             filepath.base(scope.codeLocation.file_path),
                             scope.codeLocation.line)
        return label, true
    }
}

@(private="file")
FreeLabel :: proc(label: string, didAllocate: bool) {
    if didAllocate {
        delete(label)
    }
}

@(private="file")
Worker :: proc(thread: ^thread.Thread) {
    for {
        command, ok := queue.Read(commandQueue)
        if ok {
            //fmt.printf("got a command! %v remaining, L%v\n", commandQueue.count, command.measurement.caller)
            // got a command!
            if command.commandType == .StartScope {
                measurement := command.measurement
                _, ok := scopes[measurement.caller]
                if !ok {
                    scopes[measurement.caller] = ScopeCost {
                        codeLocation = measurement.caller,
                        label = measurement.label,
                        addOrder = len(scopes),
                        depth = measurement.depth,
                    }
                }

            } else if command.commandType == .EndScope {
                measurement := command.measurement
                
                scope := scopes[measurement.caller]

                scope.longestDuration = max(scope.longestDuration, command.duration)
                scope.totalDuration += command.duration
                scope.tapCount += 1

                scopes[measurement.caller] = scope
            }

        } else {
            // queue is empty

            goSignal := cast(^bool)thread.user_args[0]
            if goSignal^ == false {
                //fmt.println("kill the thread!")
                break
            }
        }
    }
}