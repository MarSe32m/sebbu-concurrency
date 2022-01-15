//
//  ThreadPoolExtensions.swift
//  
//
//  Created by Sebastian Toivonen on 15.1.2022.
//

import SebbuTSDS

public extension ThreadPool {
    final func runAsync<T>(_ block: @escaping () -> T) async -> T {
        return await withUnsafeContinuation { continuation in
            run {
                let result = block()
                continuation.resume(returning: result)
            }
        }
    }
}
