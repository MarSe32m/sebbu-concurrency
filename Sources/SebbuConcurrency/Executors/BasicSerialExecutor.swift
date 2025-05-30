//
//  BasicSerialExecutor.swift
//  
//
//  Created by Sebastian Toivonen on 15.2.2023.
//

import SebbuTSDS
import Dispatch
import Foundation

/// Basic serial executor implementation to allow actors to run on custom threads
/// This implementation is based on a single priority queue that is drained
/// so it is possible that a very low priority job will never be executed, which is a weakness of this implementation
public final class BasicPriorityAwareSerialExecutor: @unchecked Sendable, SerialExecutor {
    @usableFromInline
    internal struct _UnownedJob: Comparable {
        @usableFromInline
        let underlying: UnownedJob
        
        @usableFromInline
        init(_ job: consuming ExecutorJob) {
            underlying = UnownedJob(job)
        }
        
        @usableFromInline
        init(_ job: UnownedJob) {
            underlying = job
        }
        
        @inlinable
        static func < (lhs: BasicPriorityAwareSerialExecutor._UnownedJob, rhs: BasicPriorityAwareSerialExecutor._UnownedJob) -> Bool {
            lhs.underlying.priority < rhs.underlying.priority
        }
        
        @inlinable
        static func == (lhs: BasicPriorityAwareSerialExecutor._UnownedJob, rhs: BasicPriorityAwareSerialExecutor._UnownedJob) -> Bool {
            lhs.underlying.priority == rhs.underlying.priority
        }
    }
    
    @usableFromInline
    internal let semaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal let workQueue: LockedPriorityQueue<_UnownedJob> = LockedPriorityQueue()

    public let isDetached: Bool
    
    public init() {
        self.isDetached = false
    }
    
    internal init(detached: Bool) {
        self.isDetached = detached
    }
    
    /// Returns a new BasicSerialExecutor with a detached thread responsible for running the executors jobs
    public static func withDetachedThread() -> BasicPriorityAwareSerialExecutor {
        let executor = BasicPriorityAwareSerialExecutor(detached: true)
        Thread.detachNewThread {
            executor._loopDetached()
        }
        return executor
    }
    
    /// Drains the executor of any jobs that it might have.
    /// If the executor is detached, this will be a no-op
    @discardableResult
    public func loopOnce() -> Bool {
        if isDetached { return false }
        let ranJobs = !workQueue.isEmpty
        while let job = workQueue.popMax() {
            job.underlying.runSynchronously(on: asUnownedSerialExecutor())
        }
        return ranJobs
    }
    
    /// Parks the current thread and runs jobs indefinitely until the program is terminated.
    /// Note: You cannot drain a detached `BasicSerialExecutor`.
    public func loop() -> Never {
        if isDetached { fatalError("Tried to loop a detached BasicSerialExecutor") }
        while true {
            semaphore.wait()
            if let job = workQueue.popMax() {
                job.underlying.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }
    
    private func _loopDetached() {
        while true {
            semaphore.wait()
            if let job = workQueue.popMax() {
                job.underlying.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }
    
    @inlinable
    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob) {
        workQueue.insert(_UnownedJob(job))
        semaphore.signal()
    }
    
    @inlinable
    @inline(__always)
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

/// Basic serial executor implementation to allow actors to run on custom threads.
/// This executor doesn't take into account the job priority
public final class BasicSerialExecutor: @unchecked Sendable, SerialExecutor, TaskExecutor {
    @usableFromInline
    internal let semaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal let workQueue = MPSCQueue<ExecutorJob>()
    
    public let isDetached: Bool
    
    public init() {
        self.isDetached = false
    }
    
    internal init(detached: Bool) {
        self.isDetached = detached
    }
    
    /// Returns a new BasicSerialExecutor with a detached thread responsible for running the executors jobs
    public static func withDetachedThread() -> BasicSerialExecutor {
        let executor = BasicSerialExecutor(detached: true)
        Thread.detachNewThread {
            executor._loopDetached()
        }
        return executor
    }
    
    /// Drains the executor of any jobs that it might have.
    /// If the executor is detached, this will be a no-op
    @discardableResult
    public func loopOnce() -> Bool {
        if isDetached { return false }
        var ranJobs = false
        while let job = workQueue.dequeue() {
            job.runSynchronously(on: asUnownedSerialExecutor())
            ranJobs = true
        }
        return ranJobs
    }
    
    /// Parks the current thread and runs jobs indefinitely until the program is terminated.
    /// Note: You cannot drain a detached `BasicSerialExecutor`.
    public func loop() -> Never {
        if isDetached { fatalError("Tried to loop a detached BasicSerialExecutor") }
        while true {
            semaphore.wait()
            if let job = workQueue.dequeue() {
                job.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }
    
    private func _loopDetached() {
        while true {
            semaphore.wait()
            if let job = workQueue.dequeue() {
                job.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }
    
    @inlinable
    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob) {
        //TODO: Once the custom executor proposal lands, we have to take into account the priority of the job
        // We might have 3 or 4 different queues for different priorities. Then we run them by for example
        // running 61 high priority, 2 mid priority, 3 high priority, 1 low priority, etc.
        // Or we might take into account the number of jobs in each priority category. Who knows we'll see...
        // Or we run high priorities when possible. Every 11th iteration we run one mid priority, then every 31st
        // iteration we run one low priority, every 61st iteration we run a background priority etc.
        //let index = getBucketIndex(priority: job.priority)
        _ = workQueue.enqueue(job)
        semaphore.signal()
    }
}

/// Basic serial executor implementation to allow actors to run on custom threads.
/// This executor doesn't take into account the job priority
public final class ManualBasicSerialExecutor: @unchecked Sendable, SerialExecutor, TaskExecutor {
    @usableFromInline
    internal let semaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal let workQueue = MPSCQueue<ExecutorJob>()
    
    public init() {}
    
    /// Drains the executor of any jobs that it might have.
    /// If the executor is detached, this will be a no-op
    @discardableResult
    public func loopOnce() -> Bool {
        var ranJobs = false
        while let job = workQueue.dequeue() {
            job.runSynchronously(on: asUnownedSerialExecutor())
            ranJobs = true
        }
        return ranJobs
    }
    
    /// Parks the current thread and runs jobs indefinitely until the program is terminated.
    /// Note: You cannot drain a detached `BasicSerialExecutor`.
    public func loop() -> Never {
        while true {
            semaphore.wait()
            if let job = workQueue.dequeue() {
                job.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }
    
    @inlinable
    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob) {
        //TODO: Once the custom executor proposal lands, we have to take into account the priority of the job
        // We might have 3 or 4 different queues for different priorities. Then we run them by for example
        // running 61 high priority, 2 mid priority, 3 high priority, 1 low priority, etc.
        // Or we might take into account the number of jobs in each priority category. Who knows we'll see...
        // Or we run high priorities when possible. Every 11th iteration we run one mid priority, then every 31st
        // iteration we run one low priority, every 61st iteration we run a background priority etc.
        //let index = getBucketIndex(priority: job.priority)
        
        _ = workQueue.enqueue(job)
        semaphore.signal()
    }
}
