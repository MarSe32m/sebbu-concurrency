//
//  ThreadPoolExtensions.swift
//  
//
//  Created by Sebastian Toivonen on 15.1.2022.
//

#if canImport(Atomics)
import SebbuTSDS

public extension ThreadPool {
    final func runAsync<T>(_ block: @escaping () -> T) async -> T {
        await withUnsafeContinuation { continuation in
            run {
                let result = block()
                continuation.resume(returning: result)
            }
        }
    }
    
    final func runAsync<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withUnsafeThrowingContinuation { continuation in
            run {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif

import Dispatch
public extension DispatchQueue {
    final func runAsync<T>(_ block: @escaping () -> T) async -> T {
        await withUnsafeContinuation { continuation in
            `async` {
                let result = block()
                continuation.resume(returning: result)
            }
        }
    }
    
    final func runAsync<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withUnsafeThrowingContinuation { continuation in
            `async` {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
