//
//  SequenceParallelExtensions.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 30.3.2025.
//

import Dispatch
import Foundation
import Synchronization

public extension Sequence where Element: Sendable {
    @inlinable
    func parallelMap<T>(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                        blockSize: Int = 1,
                        _ transform: @Sendable @escaping (Element) -> T) -> [T] {
        precondition(parallelism >= 1, "Parallelism must be atleast 1")
        precondition(blockSize >= 1, "Block size must be atleast 1")
        if parallelism == 1 { return map(transform) }
        nonisolated(unsafe) var result: [T] = []
        result.reserveCapacity(underestimatedCount)
        nonisolated(unsafe) var iterator = self.makeIterator()
        nonisolated(unsafe) var index = 0
        let mutex = Mutex<Void>(())
        DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
            var localBuffer: [(index: Int, element: Element)] = []
            localBuffer.reserveCapacity(blockSize)
            var resultBuffer: [(index: Int, value: T)] = []
            resultBuffer.reserveCapacity(blockSize)
            while true {
                // Fill the local buffer with the next batch.
                mutex.withLock { _ in
                    for _ in 0..<blockSize {
                        if let element = iterator.next() {
                            localBuffer.append((index, element))
                            index += 1
                        } else { break }
                    }
                }
                // If no elements were added, then the sequence has terminated.
                // So we stop here
                if localBuffer.isEmpty { return }
                
                // Perform the map
                for (index, element) in localBuffer {
                    resultBuffer.append((index, transform(element)))
                }
                // Insert the transformed elements into the resulting array.
                mutex.withLock { _ in
                    for (index, resultValue) in resultBuffer {
                        while result.count <= index {
                            result.append(resultValue)
                        }
                        result[index] = resultValue
                    }
                }
                // Clean up the buffers
                localBuffer.removeAll(keepingCapacity: true)
                resultBuffer.removeAll(keepingCapacity: true)
            }
        }
        return result
    }
    
    @inlinable
    func parallelForEach(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                         blockSize: Int = 1,
                         _ body: @Sendable @escaping (Element) -> Void) {
        precondition(parallelism >= 1, "Parallelism must be atleast one.")
        precondition(blockSize >= 1, "Block size must be atleast one.")
        if parallelism == 1 {
            forEach(body)
            return
        }
        let mutex = Mutex<Void>(())
        nonisolated(unsafe) var iterator = self.makeIterator()
        DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
            var localBuffer: [Element] = []
            localBuffer.reserveCapacity(blockSize)
            while true {
                mutex.withLock { _ in
                    for _ in 0..<blockSize {
                        if let element = iterator.next() {
                            localBuffer.append(element)
                        } else { break }
                    }
                }
                for element in localBuffer {
                    body(element)
                }
                if localBuffer.count < blockSize { break }
                localBuffer.removeAll(keepingCapacity: true)
            }
        }
    }
}

// Array specialization of sequence parallelMap and parallelForEach
public extension Array where Element: Sendable {
    @inlinable
    func parallelMap<T>(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                         blockSize: Int = 1,
                         _ transform: @Sendable (Element) -> T) -> [T] {
        precondition(parallelism >= 1, "Parallelism must be atleast 1")
        precondition(blockSize >= 1, "Block size must be atleast 1")
        if parallelism == 1 { return map(transform) }
        let index = Atomic<Int>(0)
        return [T].init(unsafeUninitializedCapacity: count) { buffer, initializedCount in
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
