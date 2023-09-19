//
//  File.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

import SebbuConcurrency
import ConcurrencyRuntimeC
import Foundation
import Atomics
import Dispatch
import SebbuTSDS

let queue = DispatchQueue(label: "Moiquuee")

actor QueueActor {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }
}

public final class BasicMultithreadedExecutor: @unchecked Sendable, SerialExecutor {
    let semaphore = DispatchSemaphore(value: 0)
    let queue = LockedQueue<UnownedJob>()
    
    public init(numberOfThreads: Int) {
        for _ in 0..<numberOfThreads {
            Thread.detachNewThread { [self] in
                while true {
                    semaphore.wait()
                    if let job = queue.dequeue() {
                        job.runSynchronously(on: asUnownedSerialExecutor())
                    }
                }
            }
        }
    }
    
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.enqueue(job)
        semaphore.signal()
    }
    
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

public final class UnsafeMultithreadedExecutor: @unchecked Sendable, SerialExecutor {
    @usableFromInline
    let workerDesires = ManagedAtomic<UInt64>(0)
    
    @usableFromInline
    let workerIndex = ManagedAtomic<Int>(0)
    
    @usableFromInline
    var workers: [Worker] = []
    
    @usableFromInline
    let numberOfWorkers: Int
    
    public init(numberOfThreads: Int) {
        self.numberOfWorkers = numberOfThreads
        assert(numberOfThreads > 0, "Must be atleast one thread")
        assert(numberOfThreads <= 64, "Currently the maximum number of threads supported is 64")
        for id in 0..<numberOfThreads {
            workers.append(Worker(executor: self, id: id))
        }
    }
    
    func start() {
        for worker in workers {
            Thread.detachNewThread {
                worker.run()
            }
        }
    }
    
    @inline(__always)
    @usableFromInline
    internal func getWorkerIndex() -> Int {
        let workerIndex = workerIndex.loadThenWrappingIncrement(ordering: .relaxed)
        let _workerDesires = workerDesires.load(ordering: .relaxed).powersOfTwo().map { $0.trailingZeroBitCount }
        return _workerDesires.isEmpty ? workerIndex % numberOfWorkers : _workerDesires[workerIndex % _workerDesires.count]
    }
    
#if swift(<5.9)
    @inlinable
    public func enqueue(_ job: UnownedJob) {
        let index = getWorkerIndex()
        workers[index].enqueue(job)
    }
#else
    @inlinable
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let index = getWorkerIndex()
        workers[index].enqueue(job)
    }
#endif

    @usableFromInline
    @inline(__always)
    internal func removeDesired(id: Int) {
        let _ =  workerDesires.bitwiseOrThenLoad(with: 1 &<< id, ordering: .relaxed)
    }
    
    @usableFromInline
    @inline(__always)
    internal func addDesired(id: Int) {
        let _ = workerDesires.bitwiseAndThenLoad(with: ~(1 &<< id), ordering: .relaxed)
    }
    
    @inlinable
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

extension UnsafeMultithreadedExecutor {
    @usableFromInline
    final class Worker {
        @usableFromInline
        unowned let executor: UnsafeMultithreadedExecutor
        
        @usableFromInline
        let id: Int
        
        @usableFromInline
        let running = ManagedAtomic<Bool>(true)
        
        @usableFromInline
        let semaphore = DispatchSemaphore(value: 0)
        
        @usableFromInline
        let lock = Spinlock()
        
        @usableFromInline
        let jobs: MPSCQueue<UnownedJob> = MPSCQueue(cacheSize: 128)
        
        @usableFromInline
        let unownedExecutor: UnownedSerialExecutor
        
        init(executor: UnsafeMultithreadedExecutor, id: Int) {
            self.executor = executor
            self.id = id
            self.unownedExecutor = executor.asUnownedSerialExecutor()
        }
        
        @inline(__always)
        @usableFromInline
        func enqueue(_ job: UnownedJob) {
            executor.removeDesired(id: id)
            jobs.enqueue(job)
            semaphore.signal()
        }
        
        @inline(__always)
        @usableFromInline
        func dequeue() -> UnownedJob? {
            lock.withLock { jobs.dequeue() }
        }
        
        func run() {
            while running.load(ordering: .relaxed) {
                if let job = jobs.dequeue() {
                    job.runSynchronously(on: unownedExecutor)
                    continue
                } else {
                    executor.addDesired(id: id)
                    let workerIndex = executor.getWorkerIndex()
                    if let job = executor.workers[workerIndex].dequeue() {
                        job.runSynchronously(on: unownedExecutor)
                    }
                }
                semaphore.wait()
            }
        }
    }
}

extension FixedWidthInteger {
    @_transparent
    var lowestSetBit: Self {
        self & ~(self &- 1)
    }
    
    func powersOfTwo() -> PowersOfTwo<Self> {
        PowersOfTwo(self)
    }
}

public struct PowersOfTwo<T: FixedWidthInteger>: Sequence, IteratorProtocol {
    internal var number: T
    
    public init(_ number: T) {
        self.number = number
    }
    
    public mutating func next() -> T? {
        if number == 0 { return nil }
        let lsb = number.lowestSetBit
        number &= ~lsb
        return lsb
    }
    
    public func makeIterator() -> PowersOfTwo<T> {
        self
    }
}

@globalActor
final actor BlockingWork {
    static let shared = BlockingWork()
    
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    
    nonisolated let executor: UnsafeMultithreadedExecutor = UnsafeMultithreadedExecutor(numberOfThreads: 8)
}

BlockingWork.shared.executor.start()

//@BlockingWork
func kek(index: Int) {
    if index % 10_000 == 0 {
        print("Job \(index)")
    }
}

for i in 0..<10_000_000 {
    Task.detached {
        await kek(index: i)
    }
}

try await Task.sleep(nanoseconds: 1200_000_000_000)
