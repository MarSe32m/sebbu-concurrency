//
//  Array+Parallel.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 5.4.2025.
//

import Dispatch
import Foundation
import Synchronization

// Array specialization of sequence parallelMap and parallelForEach
public extension Array where Element: Sendable {
    @inlinable
    func parallelMap<T>(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                         blockSize: Int = 1,
                         _ transform: @Sendable (Element) -> T) -> [T] {
        if isEmpty { return [] }
        precondition(parallelism >= 1, "Parallelism must be atleast 1")
        precondition(blockSize >= 1, "Block size must be atleast 1")
        if parallelism == 1 { return map(transform) }
        let index = Atomic<Int>(0)
        return [T].init(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            //TODO: Can we get rid of this nonisolated(unsafe)
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
                var resultBuffer: [T] = []
                while true {
                    var (startIndex, endIndex) = index.wrappingAdd(blockSize, ordering: .relaxed)
                    if startIndex >= self.count { break }
                    if endIndex > self.count { endIndex = self.count }
                    let range = startIndex..<endIndex
                    for i in range {
                        resultBuffer.append(transform(self[i]))
                    }
                    for (i, value) in zip(range, resultBuffer) {
                        buffer.initializeElement(at: i, to: value)
                    }
                    resultBuffer.removeAll(keepingCapacity: true)
                }
            }
            initializedCount = count
        }
    }
    
    @inlinable
    func parallelForEach(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                             blockSize: Int = 1,
                             _ body: @Sendable @escaping (Element) -> Void) {
        if isEmpty { return }
        precondition(parallelism >= 1, "Parallelism must be atleast 1")
        precondition(blockSize >= 1, "Block size must be atleast 1")
        if parallelism == 1 {
            forEach(body)
            return
        }
        let index = Atomic<Int>(0)
        let count = count
        DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
            while true {
                var (startIndex, endIndex) = index.wrappingAdd(blockSize, ordering: .relaxed)
                if startIndex >= count { break }
                if endIndex > count { endIndex = count }
                for i in startIndex..<endIndex { body(self[i]) }
            }
        }
    }
}
