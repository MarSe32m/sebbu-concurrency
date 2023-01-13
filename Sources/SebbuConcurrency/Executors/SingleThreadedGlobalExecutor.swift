//
//  SingleThreadedGlobalExecutor.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

import ConcurrencyRuntimeC
import Foundation
import Dispatch
import DequeModule
import HeapModule

/// A single threaded cooperative global executor implementation for Swift Concurrency.
/// It is specifically useful when testing that your application plays by the rules of the
/// Swift Concurrency runtime contract of forward progress, ie. don't block threads.
///
/// To override the default global concurrent executor:
///
///     SingleThreadedGlobalExecutor.shared.setup()
///     Task {
///         print("Hello world!")
///         try await Task.sleep(nanoseconds: 1_000_000_000)
///         print("Hello again!")
///     }
///     // This will run as long as there are jobs to execute
///     SingleThreadedGlobalExecutor.shared.run()
///
/// So there are two things to remember. You need to call `SingleThreadedGlobalExecutor.shared.setup()`
/// and then you need to drain the queue of work either as shown above or by using repeatedly the `runOnce()` method
/// to only process one job at a time.
public final class SingleThreadedGlobalExecutor: @unchecked Sendable, SerialExecutor {
    @usableFromInline
    internal var work = Deque<UnownedJob>()
    
    @usableFromInline
    internal var delayedWork = Heap<TimedUnownedJob>()
    public static let shared = SingleThreadedGlobalExecutor()
    
    internal init() {}
    
    public func setup() {
        swift_task_enqueueGlobal_hook = { job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            SingleThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueMainExecutor_hook = { job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            SingleThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueGlobalWithDelay_hook = { delay, job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            SingleThreadedGlobalExecutor.shared.enqueue(job, delay: delay)
        }
        
        swift_task_enqueueGlobalWithDeadline_hook = { sec, nsec, tsec, tnsec, clock, job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            //TODO: Do something about threshold values tsec, tnsec
            let deadline = sec * 1_000_000_000 + nsec
            if deadline <= 0 {
                SingleThreadedGlobalExecutor.shared.enqueue(job)
            } else {
                SingleThreadedGlobalExecutor.shared.enqueue(job, deadline: deadline.magnitude)
            }
        }
    }
    
    /// Reset the Swift Concurrency runtime hooks
    public func reset() {
        swift_task_enqueueGlobal_hook = nil
        swift_task_enqueueMainExecutor_hook = nil
        swift_task_enqueueGlobalWithDelay_hook = nil
        swift_task_enqueueGlobalWithDeadline_hook = nil
    }
    
    /// This method runs only one job from the queue.
    /// The returned value indicates how long until the next
    /// delayed job can be processed, in nanoseconds. If there is
    /// truly no work left, then the return value is UInt64.max
    @inlinable
    @discardableResult
    public func runOnce() -> UInt64 {
        processTimedJobs()
        processJob()
        return work.isEmpty ? processTimedJobs() : .max
    }
    
    /// This function will drain the jobs for as long as there are no work left.
    /// This means that in the case of only delayed jobs the thread will sleep until
    /// it can process the work.
    @inlinable
    public func run() {
        while true {
            processTimedJobs()
            processJob()
            
            if work.isEmpty {
                let sleepTime = processTimedJobs()
                // The delayed work is also empty so we have no work left
                if sleepTime == .max {
                    return
                }
                Thread.sleep(forTimeInterval: Double(sleepTime) / 1_000_000_000.0)
            }
        }
    }
    
    @inline(__always)
    public func enqueue(_ job: UnownedJob) {
        work.append(job)
    }
    
    @inline(__always)
    internal func enqueue(_ job: UnownedJob, delay: UInt64) {
        let deadline = DispatchTime.now().uptimeNanoseconds + delay
        enqueue(job, deadline: deadline)
    }
    
    @inline(__always)
    internal func enqueue(_ job: UnownedJob, deadline: UInt64) {
        let job = TimedUnownedJob(job: job, deadline: deadline)
        delayedWork.insert(job)
    }
    
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
    
    @inline(__always)
    @usableFromInline
    @discardableResult
    internal func processTimedJobs() -> UInt64 {
        let currentTime = DispatchTime.now().uptimeNanoseconds
        while !delayedWork.isEmpty {
            let first = delayedWork.max()!
            if first.deadline <= currentTime {
                let job = delayedWork.removeMax().job
                enqueue(job)
            } else {
                return first.deadline - currentTime
            }
        }
        return .max
    }
    
    @inline(__always)
    @usableFromInline
    internal func processJob() {
        if let job = work.popFirst() {
            _swiftJobRun(job, asUnownedSerialExecutor())
        }
    }
}

extension SingleThreadedGlobalExecutor {
    @usableFromInline
    internal struct TimedUnownedJob: Comparable {
        @usableFromInline
        let job: UnownedJob
        
        @usableFromInline
        let deadline: UInt64
        
        @inlinable
        internal init(job: UnownedJob, deadline: UInt64) {
            self.job = job
            self.deadline = deadline
        }
        
        @usableFromInline
        internal static func < (lhs: SingleThreadedGlobalExecutor.TimedUnownedJob, rhs: SingleThreadedGlobalExecutor.TimedUnownedJob) -> Bool {
            lhs.deadline < rhs.deadline
        }
        
        @usableFromInline
        internal static func == (lhs: SingleThreadedGlobalExecutor.TimedUnownedJob, rhs: SingleThreadedGlobalExecutor.TimedUnownedJob) -> Bool {
            lhs.deadline == rhs.deadline
        }
    }
}
