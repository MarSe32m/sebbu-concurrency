//
//  SingleThreadedGlobalExecutor.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

import ConcurrencyRuntimeC
import Foundation

/// A single threaded cooperative global executor implementation for Swift Concurrency.
/// It is specifically useful when testing that your application plays by the rules of the
/// Swift Concurrency runtime contract of forward progress, ie. don't block threads.
///
/// To override the default global concurrent executor:
/// ```swift
/// SingleThreadedGlobalExecutor.shared.setup()
/// Task {
///     print("Hello world!")
///     try await Task.sleep(nanoseconds: 1_000_000_000)
///     print("Hello again!")
/// }
/// ```
/// So there are two things to remember. You need to call `SingleThreadedGlobalExecutor.shared.setup()`
/// and then you need to drain the queue of work either as shown above or by using repeatedly the `runOnce()` method
/// to only process one job at a time. When the main queue draining hook is supported, you just need to setup the executor
/// and it will automatically drain the queue for you.
///
public final class SingleThreadedGlobalExecutor: @unchecked Sendable, SerialExecutor, TaskExecutor {
    public static let shared = SingleThreadedGlobalExecutor()
    
    @usableFromInline
    internal let executor: SingleThreadedExecutor = SingleThreadedExecutor()

    internal init() {}
    
    public func setup() {
        swift_task_enqueueGlobal_hook = { job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            SingleThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueMainExecutor_hook = { job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            SingleThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueGlobalWithDelay_hook = { delay, job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            SingleThreadedGlobalExecutor.shared.enqueue(job, delay: delay)
        }

        swift_task_enqueueGlobalWithDeadline_hook = { sec, nsec, tsec, tnsec, clock, job, _ in
            let job = ExecutorJob(unsafeBitCast(job, to: UnownedJob.self))
            //TODO: Do something about threshold values tsec, tnsec
            let deadline = sec * 1_000_000_000 + nsec
            var seconds: Int64 = 0
            var nanoseconds: Int64 = 0
            _getTime(&seconds, &nanoseconds, clock)
            let now = seconds * 1_000_000_000 + nanoseconds
            let delay = now.distance(to: deadline)
            if delay <= 0 {
                SingleThreadedGlobalExecutor.shared.enqueue(job)
            } else {
                SingleThreadedGlobalExecutor.shared.enqueue(job, delay: UInt64(delay.magnitude))
            }

            //print(delay)
            //print(deadline, sec, nsec, tsec, tnsec, clock)
            //print(seconds, nanoseconds)
            //let now = DispatchTime.now().uptimeNanoseconds
            //print(now)
            //if deadline <= 0 || now.distance(to: UInt64(deadline)) < 0 {
            //    SingleThreadedGlobalExecutor.shared.enqueue(job)
            //} else {
            //    let delay = Int64(now.distance(to: UInt64(deadline)))
            //    print("Hook deadline, delay:", delay)
            //    SingleThreadedGlobalExecutor.shared.enqueue(job, delay: delay.magnitude)
            //}
        }
        Thread.detachNewThread {
            SingleThreadedGlobalExecutor.shared.run()
        }
        //swift_task_asyncMainDrainQueue_hook = { original, `override` in
        //    SingleThreadedGlobalExecutor.shared.run()
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
    
    /// This function will drain the jobs for as long as there is no work left.
    /// This means that in the case of only delayed jobs the thread will sleep until
    /// it can process the work.
    @inlinable
    internal func run() {
        executor.run()
    }
    
    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob) {
        executor.enqueue(job)
    }
    
    @inline(__always)
    internal func enqueue(_ job: consuming ExecutorJob, delay: UInt64) {
        executor.enqueue(job, delay: delay)
    }
}
