//
//  MultiThreadedGlobalExecutor.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//
//TODO: Create your own threads etc.
import Foundation
import Dispatch
import HeapModule
import SebbuTSDS
import ConcurrencyRuntimeC
import Synchronization

// New logic:
// Once a worker has gotten work, the decrement the workerIndex, this way
// if only single items of work is enqueued one after the other, the same thread
// will run them. This way we eliminate unnecessary thread switching in cases
// when one thread is enough to do the work

/// A multi threaded cooperative global executor implementation for Swift Concurrency.
/// Spawns cores - 1 threads. If the systems has only one core, then one thread will be spawned.
///
/// To override the default global concurrent executor:
///
///     MultiThreadedGlobalExecutor.shared.setup()
///     Task {
///         print("Hello world!")
///         try await Task.sleep(nanoseconds: 1_000_000_000)
///         print("Hello again!")
///     }
///     // This will run indefinitely unless reset() is called which will stop the executor.
///     MultiThreadedGlobalExecutor.shared.run()
///
/// So there are two things to remember. You need to call `MultiThreadedGlobalExecutor.shared.setup()`
/// and then you need to drain the queue of work either as shown above or by using repeatedly the `runOnce()` method
/// to only process one job in the main queue at a time.
///
/// Note: Currently this implementation has very bad integrability with TaskGroups.
public final class MultiThreadedGlobalExecutor: @unchecked Sendable, Executor {
    @usableFromInline
    internal let executor: MultiThreadedTaskExecutor

    @usableFromInline
    internal let mainExecutor: SingleThreadedExecutor

    public static let shared = MultiThreadedGlobalExecutor()
    
    internal init(numberOfThreads: Int? = nil) {
        let coreCount = numberOfThreads ?? ProcessInfo.processInfo.activeProcessorCount - 1 > 0 ? ProcessInfo.processInfo.activeProcessorCount - 1 : 1
        self.executor = MultiThreadedTaskExecutor(numberOfThreads: coreCount)
        self.mainExecutor = SingleThreadedExecutor()
    }
    
    public func setup(numberOfThreads: Int? = nil) {
        swift_task_enqueueGlobal_hook = { job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            MultiThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueMainExecutor_hook = { job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            MultiThreadedGlobalExecutor.shared.enqueueMain(job)
        }
        
        swift_task_enqueueGlobalWithDelay_hook = { delay, job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            MultiThreadedGlobalExecutor.shared.enqueue(job, delay: delay)
        }
        
        swift_task_enqueueGlobalWithDeadline_hook = { sec, nsec, tsec, tnsec, clock, job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            //TODO: Do something about threshold values tsec, tnsec
            //let deadline = sec * 1_000_000_000 + nsec
            //let now = DispatchTime.now().uptimeNanoseconds
            //if deadline <= 0 || now.distance(to: UInt64(deadline)) < 0 {
            //    MultiThreadedGlobalExecutor.shared.enqueue(job)
            //} else {
            //    let delay = Int64(now.distance(to: UInt64(deadline)))
            //    MultiThreadedGlobalExecutor.shared.enqueue(job, deadline: delay.magnitude)
            //}
            let deadline = sec * 1_000_000_000 + nsec
            var seconds: Int64 = 0
            var nanoseconds: Int64 = 0
            _getTime(&seconds, &nanoseconds, clock)
            let now = seconds * 1_000_000_000 + nanoseconds
            let delay = now.distance(to: deadline)
            if delay <= 0 {
                MultiThreadedGlobalExecutor.shared.enqueue(job)
            } else {
                MultiThreadedGlobalExecutor.shared.enqueue(job, delay: UInt64(delay.magnitude))
            }
        }
        
        //TODO: Use the hook below to run the exectuor once the MainActor executor hook is fixed...
        Thread.detachNewThread {
            self.mainExecutor.run()
        }
        //swift_task_asyncMainDrainQueue_hook = { _, _ in
        //    MultiThreadedGlobalExecutor.shared.run()
        //}
    }
    
    /// Reset the Swift Concurrency runtime hooks
    public func reset() {
        swift_task_enqueueGlobal_hook = nil
        swift_task_enqueueMainExecutor_hook = nil
        swift_task_enqueueGlobalWithDelay_hook = nil
        swift_task_enqueueGlobalWithDeadline_hook = nil
        //swift_task_asyncMainDrainQueue_hook = nil
    }
    
    @inlinable
    public func enqueue(_ job: consuming ExecutorJob) {
        executor.enqueue(job)
    }
    
    @inline(__always)
    internal func enqueueMain(_ job: consuming ExecutorJob) {
        mainExecutor.enqueue(job)
    }
        
    @inline(__always)
    internal func enqueue(_ job: consuming ExecutorJob, delay: UInt64) {
        executor.enqueue(job, delay: delay)
    }
}