//
//  main.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

import SebbuConcurrency
import ConcurrencyRuntimeC
import Foundation
import Dispatch
import SebbuTSDS
import Synchronization

func foo() async {
    print("HEllo from gloabl")
}

SingleThreadedGlobalExecutor.shared.setup()
let task = Task {  
    print("Hello from main actor!")
}

let executor = MultiThreadedTaskExecutor(numberOfThreads: 16)

let tasks = (0..<executor.numberOfThreads * 10 * 5).map { i in
    Task.detached(executorPreference: executor) {
        try! await Task.sleep(for: .seconds(3))
        //let start = ContinuousClock.now
        //while start.duration(to: .now) < .seconds(0.1) {}
        print("Done", i)
    }
}
await foo()
print("Sleeping")
try? await Task.sleep(for: .seconds(6))
await foo()
print("Hehe")
await task.value
print("high", TaskPriority.high, TaskPriority.high.rawValue)
print("medium", TaskPriority.medium, TaskPriority.medium.rawValue)
print("low", TaskPriority.low, TaskPriority.low.rawValue)
print("background", TaskPriority.background, TaskPriority.background.rawValue)

print("utility", TaskPriority.utility, TaskPriority.utility.rawValue) // Same as low
print("userInitiated", TaskPriority.userInitiated, TaskPriority.userInitiated.rawValue) // Same as high
