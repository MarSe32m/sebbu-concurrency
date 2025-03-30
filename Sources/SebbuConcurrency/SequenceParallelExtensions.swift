//
//  SequenceParallelExtensions.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 30.3.2025.
//

import Dispatch
import Foundation
import SebbuTSDS
import Synchronization

public extension Sequence where Element: Sendable {
    func parallelMap<T>(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                        blockSize: Int = 1,
                        _ transform: @Sendable @escaping (Element) -> T) -> [T] {
        if parallelism == 1 { return map(transform) }
        let resultQueue = MPSCQueue<(Int, T)>()
        nonisolated(unsafe) let queues = UnsafeMutableBufferPointer<SPSCBoundedQueue<(Int, Element)>>.allocate(capacity: parallelism)
        nonisolated(unsafe) let semaphores = UnsafeMutableBufferPointer<DispatchSemaphore>.allocate(capacity: parallelism)
        defer {
            queues.deinitialize()
            queues.deallocate()
            semaphores.deinitialize()
            semaphores.deallocate()
        }
        for i in 0..<queues.count {
            queues.initializeElement(at: i, to: SPSCBoundedQueue(size: 2 * blockSize))
            semaphores.initializeElement(at: i, to: DispatchSemaphore(value: 0))
        }
        
        let readySemaphore = DispatchSemaphore(value: 0)
        let workSemaphore = DispatchSemaphore(value: 2 * parallelism * blockSize)
        let done = Atomic<Bool>(false)
        
        for i in 0..<parallelism {
            DispatchQueue.global().async {
                while !done.load(ordering: .relaxed) {
                    semaphores[i].wait()
                    while let element = queues[i].dequeue() {
                        let result = transform(element.1)
                        let _ = resultQueue.enqueue((element.0, result))
                        workSemaphore.signal()
                    }
                }
                readySemaphore.signal()
            }
        }
        
        var results: [T] = []
        if underestimatedCount > 0 {
            results.reserveCapacity(underestimatedCount)
        }
        
        var elementsSent = 0
        var elementsReceived = 0
        
        func drainResultQueue() {
            if let (index, value) = resultQueue.dequeue() {
                elementsReceived += 1
                while index >= results.count {
                    results.append(value)
                }
                results[index] = value
            }
        }
        
        precondition(blockSize >= 1, "Block size must be atleast one.")
        var iterator = self.enumerated().makeIterator()
        while true {
            drainResultQueue()
            let queueIndex = (elementsSent / blockSize) % queues.count
            var iterations = 0
            while iterations < blockSize, let (index, element) = iterator.next() {
                workSemaphore.wait()
                iterations += 1
                queues[queueIndex].blockingEnqueue((index, element))
                elementsSent += 1
            }
            semaphores[queueIndex].signal()
            if iterations != blockSize { break }
        }
        
        done.store(true, ordering: .releasing)
        for i in 0..<semaphores.count { semaphores[i].signal() }
        while elementsSent > elementsReceived { drainResultQueue() }
        for _ in 0..<parallelism { readySemaphore.wait() }
        return results
    }
    
    func parallelForEach(parallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
                         blockSize: Int = 1,
                         _ body: @Sendable @escaping (Element) -> Void) {
        precondition(parallelism >= 1, "Parallelism must be atleast one.")
        precondition(blockSize >= 1, "Block size must be atleast one.")
        if parallelism == 1 {
            forEach(body)
            return
        }
        nonisolated(unsafe) let queues = UnsafeMutableBufferPointer<SPSCBoundedQueue< Element>>.allocate(capacity: parallelism)
        nonisolated(unsafe) let semaphores = UnsafeMutableBufferPointer<DispatchSemaphore>.allocate(capacity: parallelism)
        defer {
            queues.deinitialize()
            queues.deallocate()
            semaphores.deinitialize()
            semaphores.deallocate()
        }
        for i in 0..<queues.count {
            queues.initializeElement(at: i, to: SPSCBoundedQueue(size: 2 * blockSize))
            semaphores.initializeElement(at: i, to: DispatchSemaphore(value: 0))
        }
        
        let readySemaphore = DispatchSemaphore(value: 0)
        let workSemaphore = DispatchSemaphore(value: 2 * parallelism * blockSize)
        let done = Atomic<Bool>(false)
        for i in 0..<parallelism {
            DispatchQueue.global().async {
                while !done.load(ordering: .relaxed) {
                    semaphores[i].wait()
                    while let element = queues[i].dequeue() {
                        body(element)
                        workSemaphore.signal()
                    }
                }
                readySemaphore.signal()
            }
        }
        
        var count = 0
        var iterator = self.makeIterator()
        while true {
            let queueIndex = (count / blockSize) % queues.count
            var iterations = 0
            while iterations < blockSize, let element = iterator.next() {
                workSemaphore.wait()
                iterations += 1
                queues[queueIndex].blockingEnqueue(element)
                count += 1
            }
            semaphores[queueIndex].signal()
            if iterations != blockSize { break }
        }
        
        done.store(true, ordering: .releasing)
        for i in 0..<semaphores.count { semaphores[i].signal() }
        for _ in 0..<parallelism { readySemaphore.wait() }
    }
}

public extension Array where Element: Sendable {
    func parallelMap<T>(_ transform: @Sendable (Element) -> T) -> [T] {
        if self.isEmpty { return [] }
        return [T].init(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: count) { i in
                buffer[i] = transform(self[i])
            }
            initializedCount = count
        }
    }
    
    func parallelMap<T>(parallelism: Int,
                        _ transform: @Sendable (Element) -> T) -> [T] {
        if self.isEmpty { return [] }
        precondition(parallelism >= 1, "Parallelism must be atleast one.")
        let counter = Atomic<Int>(0)
        return [T].init(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: parallelism) { i in
                while true {
                    let index = counter.add(1, ordering: .relaxed).oldValue
                    if index >= count { break }
                    buffer[index] = transform(self[index])
                }
            }
            initializedCount = count
        }
    }
    
    func parallelForEach(_ body: @Sendable (Element) -> Void) {
        if self.isEmpty { return }
        DispatchQueue.concurrentPerform(iterations: count) { i in
            body(self[i])
        }
    }
    
    func parallelForEach(parallelism: Int,
                         _ body: @Sendable (Element) -> Void) {
        if self.isEmpty { return }
        precondition(parallelism >= 1, "Parallelism must be atleast one.")
        let counter = Atomic<Int>(0)
        DispatchQueue.concurrentPerform(iterations: parallelism) { _ in
            while true {
                let index = counter.add(1, ordering: .relaxed).oldValue
                if index >= count { break }
                body(self[index])
            }
        }
    }
}
