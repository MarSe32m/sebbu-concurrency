//
//  Collection+Parallel.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 5.4.2025.
//

import Dispatch
import Foundation
import Synchronization

// Slices etc.
public extension Collection where Self: Sendable, Element: Sendable, Index: Sendable {
    @inlinable
    func parallelMap<T>(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                        blockSize: Int = 1,
                        _ transform: @Sendable (Element) -> T) -> [T] {
        precondition(parallelism >= 1, "Parallelism must be atleast 1")
        precondition(blockSize >= 1, "Block size must be atleast 1")
        if isEmpty { return [] }
        if parallelism == 1 { return map(transform) }
        let index = Atomic<Int>(0)
        let totalCount = count
        return [T].init(unsafeUninitializedCapacity: totalCount) { buffer, initializedCount in
            //TODO: Can we get rid of this nonisolated(unsafe)?
            nonisolated(unsafe) let buffer = buffer
            let _startIndex = self.startIndex
            let _endIndex = self.endIndex
            DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
                var resultBuffer: [T] = []
                while true {
                    let (start, end) = index.wrappingAdd(blockSize, ordering: .relaxed)
                    if start >= totalCount { break }
                    let startIndex = self.index(_startIndex, offsetBy: start)
                    let endIndex = self.index(_startIndex, offsetBy: end, limitedBy: _endIndex) ?? _endIndex
                    for value in self[startIndex..<endIndex] {
                        resultBuffer.append(transform(value))
                    }
                    for (i, value) in zip(start..<end, resultBuffer) {
                        buffer.initializeElement(at: i, to: value)
                    }
                    resultBuffer.removeAll(keepingCapacity: true)
                }
            }
            initializedCount = totalCount
        }
    }
    
    @inlinable
    func parallelForEach(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                         blockSize: Int = 1,
                         _ body: @Sendable (Element) -> Void) {
        precondition(parallelism >= 1, "Parallelism must be atleast 1")
        precondition(blockSize >= 1, "Block size must be atleast 1")
        if isEmpty { return }
        if parallelism == 1 {
            forEach(body)
            return
        }
        let index = Atomic<Int>(0)
        let totalCount = count
        let _startIndex = startIndex
        let _endIndex = endIndex
        DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
            while true {
                let (start, end) = index.wrappingAdd(blockSize, ordering: .relaxed)
                if start >= totalCount { break }
                let startIndex = self.index(_startIndex, offsetBy: start)
                let endIndex = self.index(_endIndex, offsetBy: end, limitedBy: _endIndex) ?? _endIndex
                for value in self[startIndex..<endIndex] {
                    body(value)
                }
            }
        }
    }
}
