//
//  File.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

import SebbuConcurrency
import ConcurrencyRuntimeC
import Foundation
#if !os(Windows)
MultiThreadedGlobalExecutor.shared.setup()
print("Whast?")
@globalActor
struct GlobAct {
    actor ActorType {}
    
    static var shared: ActorType = ActorType()
}


Task { @GlobAct in
    print("Hello from mainActor!")
}
Task { @GlobAct in
    print("Actually hello from global actor!")
}

func mainActorFunc() async {
    print("Main actor function")
    print("After sleep")
}

Task {
    print("Hello fr")
    await mainActorFunc()
    print("?")
    await withTaskGroup(of: Int.self, returning: Void.self) { group in
        print("???")
        for i in 0..<1_000_000 {
            group.addTask {
                return i
            }
        }
        let sum = await group.reduce(0, +)
        print(sum)
    }
    MultiThreadedGlobalExecutor.shared.reset()
    print("hehe 1")
}

MultiThreadedGlobalExecutor.shared.run()
print("hehe 2")
#endif
