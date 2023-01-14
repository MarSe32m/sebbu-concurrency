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

#if canImport(Atomics)
import Atomics

@usableFromInline
internal final class Queue {
    @usableFromInline
    let workQueue: MPSCQueue<UnownedJob>
    
    @usableFromInline
    let processing: ManagedAtomic<Bool>
    
    init(cacheSize: Int = 4096) {
        self.workQueue = MPSCQueue(cacheSize: cacheSize)
        self.processing = ManagedAtomic(false)
    }
    
    @inlinable
    @inline(__always)
    func dequeue() -> UnownedJob? {
        for _ in 0..<32 {
            if !processing.exchange(true, ordering: .acquiring) {
                defer { processing.store(false, ordering: .releasing) }
                return workQueue.dequeue()
            }
            HardwareUtilities.pause()
        }
        return nil
    }
    
    @inline(__always)
    @usableFromInline
    func enqueue(_ work: UnownedJob) {
        workQueue.enqueue(work)
    }
}

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
public final class MultiThreadedGlobalExecutor: @unchecked Sendable, Executor {
    @usableFromInline
    internal let queues: [Queue]
    
    @usableFromInline
    internal let numberOfQueues: Int
    
    @usableFromInline
    internal let mainQueue: Queue = Queue(cacheSize: 2048)
    
    @usableFromInline
    internal let timedWorkQueue: MPSCQueue<TimedUnownedJob> = MPSCQueue<TimedUnownedJob>(cacheSize: 1024)
    
    @usableFromInline
    internal var workers: [Worker] = []
    
    @usableFromInline
    internal var timedWork: Heap<TimedUnownedJob> = Heap()
    
    @usableFromInline
    internal let workerIndex: ManagedAtomic<Int> = ManagedAtomic(0)
    
    @usableFromInline
    internal let handlingTimedWork: ManagedAtomic<Bool> = ManagedAtomic(false)
    
    @usableFromInline
    internal let queueIndex: ManagedAtomic<Int> = ManagedAtomic(0)
    
    @usableFromInline
    internal let workCount: ManagedAtomic<Int> = ManagedAtomic(0)
    
    @usableFromInline
    internal let nextTimedWorkDeadline: ManagedAtomic<UInt64> = ManagedAtomic(0)
    
    @usableFromInline
    internal let semaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal let mainSemaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal let started: ManagedAtomic<Bool> = ManagedAtomic(false)
    
    public static let shared = MultiThreadedGlobalExecutor()
    
    internal init() {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount - 1 > 0 ? ProcessInfo.processInfo.activeProcessorCount - 1 : 1
        self.queues = (0..<coreCount).map { _ in Queue(cacheSize: 1024) }
        self.numberOfQueues = coreCount
    }
    
    public func setup() {
        swift_task_enqueueGlobal_hook = { job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            MultiThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueMainExecutor_hook = { job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            MultiThreadedGlobalExecutor.shared.enqueueMain(job)
        }
        
        swift_task_enqueueGlobalWithDelay_hook = { delay, job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            MultiThreadedGlobalExecutor.shared.enqueue(job, delay: delay)
        }
        
        swift_task_enqueueGlobalWithDeadline_hook = { sec, nsec, tsec, tnsec, clock, job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            //TODO: Do something about threshold values tsec, tnsec
            let deadline = sec * 1_000_000_000 + nsec
            if deadline <= 0 {
                MultiThreadedGlobalExecutor.shared.enqueue(job)
            } else {
                MultiThreadedGlobalExecutor.shared.enqueue(job, deadline: deadline.magnitude)
            }
        }
        start()
    }
    
    /// Reset the Swift Concurrency runtime hooks
    public func reset() {
        swift_task_enqueueGlobal_hook = nil
        swift_task_enqueueMainExecutor_hook = nil
        swift_task_enqueueGlobalWithDelay_hook = nil
        swift_task_enqueueGlobalWithDeadline_hook = nil
        stop()
    }
    
    internal func start() {
        if started.exchange(true, ordering: .relaxed) { return }
        for (index, _) in queues.enumerated() {
            let worker = Worker(executor: self)
            let thread = Thread {
                worker.run()
            }
            thread.name = "SebbuConcurrency-cooperative-thread-\(index + 1)"
            workers.append(worker)
            thread.start()
        }
    }
    
    /// Drains the main queue
    public func run() {
        while started.load(ordering: .relaxed) {
            if let job = mainQueue.dequeue() {
                job._runSynchronously(on: _getCurrentExecutor())
                //_swiftJobRun(job, _getCurrentExecutor())
            }
            mainSemaphore.wait()
        }
        // Drain the last work
        while let job = mainQueue.dequeue() {
            job._runSynchronously(on: _getCurrentExecutor())
        }
    }
    
    /// Processes one job on the main queue and returns if something was processed
    @discardableResult
    public func runOnce() -> Bool {
        if let job = mainQueue.dequeue() {
            job._runSynchronously(on: _getCurrentExecutor())
            //_swiftJobRun(job, _getCurrentExecutor())
            return true
        }
        return false
    }
    
    @inlinable
    public func enqueue(_ job: UnownedJob) {
        precondition(started.load(ordering: .relaxed), "The ThreadPool wasn't started before blocks were submitted")
        assert(!workers.isEmpty)
        let index = getNextIndex()
        let queue = queues[index % numberOfQueues]
        queue.enqueue(job)
        workCount.wrappingIncrement(ordering: .acquiringAndReleasing)
        semaphore.signal()
    }
    
    @inline(__always)
    internal func enqueueMain(_ job: UnownedJob) {
        mainQueue.enqueue(job)
        mainSemaphore.signal()
    }
        
    @inline(__always)
    internal func enqueue(_ job: UnownedJob, delay: UInt64) {
        let deadline = DispatchTime.now().uptimeNanoseconds + delay
        enqueue(job, deadline: deadline)
    }
    
    @inline(__always)
    internal func enqueue(_ job: UnownedJob, deadline: UInt64) {
        let timedJob = TimedUnownedJob(job: job, deadline: deadline)
        timedWorkQueue.enqueue(timedJob)
        semaphore.signal()
    }

    @inlinable
    internal func handleTimedWork() {
        if handlingTimedWork.exchange(true, ordering: .acquiring) { return }
        defer { handlingTimedWork.store(false, ordering: .releasing) }
        
        // Move the enqueued work into the priority queue
        for work in timedWorkQueue {
            timedWork.insert(work)
        }
        
        // Process the priority queue
        let currentTime = DispatchTime.now().uptimeNanoseconds
        while let timedJob = timedWork.max() {
            if timedJob.deadline > currentTime {
                nextTimedWorkDeadline.store(timedJob.deadline, ordering: .relaxed)
                return
            }
            let timedJob = timedWork.removeMax()
            // Enqueue the work to a worker thread
            enqueue(timedJob.job)
        }
    }
    
    internal func stop() {
        workers.forEach { $0.stop() }
        workers.removeAll()
        started.store(false, ordering: .releasing)
        mainSemaphore.signal()
    }
    
    @inlinable
    internal final func getNextIndex() -> Int {
        let index = workerIndex.loadThenWrappingIncrement(ordering: .relaxed)
        if _slowPath(index < 0) {
            workerIndex.store(0, ordering: .relaxed)
            return 0
        }
        return index
    }
    
    @inlinable
    internal final func getQueueIndex() -> Int {
        let index = queueIndex.loadThenWrappingIncrement(ordering: .relaxed)
        if _slowPath(index < 0) {
            queueIndex.store(0, ordering: .relaxed)
            return 0
        }
        return index
    }
}

@usableFromInline
final class Worker {
    @usableFromInline
    let running: ManagedAtomic<Bool> = ManagedAtomic(false)
    
    @usableFromInline
    let executor: MultiThreadedGlobalExecutor
    
    @usableFromInline
    let numberOfQueues: Int
    
    init(executor: MultiThreadedGlobalExecutor) {
        self.executor = executor
        self.numberOfQueues = executor.queues.count
    }
    
    @inlinable
    public func run() {
        running.store(true, ordering: .relaxed)
        while running.load(ordering: .relaxed) {
            executor.handleTimedWork()
            drainQueues()
            // By exchanging only one thread will sleep
            let deadline = executor.nextTimedWorkDeadline.exchange(0, ordering: .relaxed)
            if _slowPath(deadline > 0) {
                _ = executor.semaphore.wait(timeout: .init(uptimeNanoseconds: deadline))
            } else {
                executor.semaphore.wait()
            }
        }
        // Drain the queues one last time
        drainQueues()
    }
    
    @inline(__always)
    @usableFromInline
    internal func drainQueues() {
        repeat {
            let queueIndex = executor.getQueueIndex()
            for i in 0..<numberOfQueues {
                let queue = executor.queues[(queueIndex + i) % numberOfQueues]
                while let job = queue.dequeue() {
                    executor.workCount.wrappingDecrement(ordering: .relaxed)
                    job._runSynchronously(on: _getCurrentExecutor())
                    //_swiftJobRun(job, _getCurrentExecutor())
                    executor.handleTimedWork()
                }
            }
        } while executor.workCount.load(ordering: .relaxed) > 0
    }
    
    public func stop() {
        running.store(false, ordering: .relaxed)
        executor.semaphore.signal()
    }
    
    deinit {
        stop()
    }
}
#else
public final class MultiThreadedGlobalExecutor: @unchecked Sendable, Executor {
    @usableFromInline
    internal let globalQueue: LockedQueue<UnownedJob> = LockedQueue(cacheSize: 1024)
    
    @usableFromInline
    internal let mainQueue: MPSCQueue<UnownedJob> = MPSCQueue(cacheSize: 1024)
    
    @usableFromInline
    internal let timedWorkQueue: MPSCQueue<TimedUnownedJob> = MPSCQueue<TimedUnownedJob>(cacheSize: 1024)
    
    @usableFromInline
    internal var workers: [Worker] = []
    
    @usableFromInline
    internal var timedWork: Heap<TimedUnownedJob> = Heap()
    
    @usableFromInline
    internal let timedWorkHandlingLock: Lock = Lock()
    
    @usableFromInline
    internal let semaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal let mainSemaphore = DispatchSemaphore(value: 0)
    
    @usableFromInline
    internal var started: Bool = false
    
    @usableFromInline
    internal let startedLock: Lock = Lock()
    
    @usableFromInline
    internal let numberOfThreads: Int
    
    public static let shared = MultiThreadedGlobalExecutor()
    
    internal init() {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount - 1 > 0 ? ProcessInfo.processInfo.activeProcessorCount - 1 : 1
        self.numberOfThreads = coreCount
    }
    
    public func setup() {
        swift_task_enqueueGlobal_hook = { job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            MultiThreadedGlobalExecutor.shared.enqueue(job)
        }
        
        swift_task_enqueueMainExecutor_hook = { job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            MultiThreadedGlobalExecutor.shared.enqueueMain(job)
        }
        
        swift_task_enqueueGlobalWithDelay_hook = { delay, job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            MultiThreadedGlobalExecutor.shared.enqueue(job, delay: delay)
        }
        
        swift_task_enqueueGlobalWithDeadline_hook = { sec, nsec, tsec, tnsec, clock, job, _ in
            let job = unsafeBitCast(job, to: UnownedJob.self)
            //TODO: Do something about threshold values tsec, tnsec
            let deadline = sec * 1_000_000_000 + nsec
            if deadline <= 0 {
                MultiThreadedGlobalExecutor.shared.enqueue(job)
            } else {
                MultiThreadedGlobalExecutor.shared.enqueue(job, deadline: deadline.magnitude)
            }
        }
        start()
    }
    
    /// Reset the Swift Concurrency runtime hooks
    public func reset() {
        swift_task_enqueueGlobal_hook = nil
        swift_task_enqueueMainExecutor_hook = nil
        swift_task_enqueueGlobalWithDelay_hook = nil
        swift_task_enqueueGlobalWithDeadline_hook = nil
        stop()
    }
    
    internal func start() {
        startedLock.lock()
        if started {
            startedLock.unlock()
            return
        }
        self.started = true
        startedLock.unlock()
        
        for index in 1...numberOfThreads {
            let worker = Worker(executor: self)
            let thread = Thread {
                worker.run()
            }
            thread.name = "SebbuConcurrency-cooperative-thread-\(index)"
            workers.append(worker)
            thread.start()
        }
    }
    
    /// Drains the main queue
    public func run() {
        while true {
            let started = startedLock.withLock {
                self.started
            }
            if !started { break }
            if let job = mainQueue.dequeue() {
                job._runSynchronously(on: _getCurrentExecutor())
                //_swiftJobRun(job, _getCurrentExecutor())
            }
            mainSemaphore.wait()
        }
        // Drain the last work
        while let job = mainQueue.dequeue() {
            job._runSynchronously(on: _getCurrentExecutor())
        }
    }
    
    /// Processes one job on the main queue and returns if something was processed
    @discardableResult
    public func runOnce() -> Bool {
        if let job = mainQueue.dequeue() {
            job._runSynchronously(on: _getCurrentExecutor())
            //_swiftJobRun(job, _getCurrentExecutor())
            return true
        }
        return false
    }
    
    @inlinable
    public func enqueue(_ job: UnownedJob) {
        assert({startedLock.withLock { self.started }}(), "The ThreadPool wasn't started before blocks were submitted!")
        assert(!workers.isEmpty)
        globalQueue.enqueue(job)
        semaphore.signal()
    }
    
    @inline(__always)
    internal func enqueueMain(_ job: UnownedJob) {
        mainQueue.enqueue(job)
        mainSemaphore.signal()
    }
        
    @inline(__always)
    internal func enqueue(_ job: UnownedJob, delay: UInt64) {
        let deadline = DispatchTime.now().uptimeNanoseconds + delay
        enqueue(job, deadline: deadline)
    }
    
    @inline(__always)
    internal func enqueue(_ job: UnownedJob, deadline: UInt64) {
        let timedJob = TimedUnownedJob(job: job, deadline: deadline)
        timedWorkQueue.enqueue(timedJob)
        semaphore.signal()
    }

    @inlinable
    @discardableResult
    internal func handleTimedWork() -> UInt64 {
        if !timedWorkHandlingLock.tryLock() { return 0 }
        defer { timedWorkHandlingLock.unlock() }
        
        // Move the enqueued work into the priority queue
        for work in timedWorkQueue {
            timedWork.insert(work)
        }
        
        // Process the priority queue
        let currentTime = DispatchTime.now().uptimeNanoseconds
        while let timedJob = timedWork.max() {
            if timedJob.deadline > currentTime {
                return timedJob.deadline
            }
            let timedJob = timedWork.removeMax()
            // Enqueue the work to a worker thread
            enqueue(timedJob.job)
        }
        return 0
    }
    
    internal func stop() {
        startedLock.withLock {
            self.started = false
        }
        workers.forEach { $0.stop() }
        workers.removeAll()
        mainSemaphore.signal()
    }
}

@usableFromInline
final class Worker {
    @usableFromInline
    var running: Bool = false
    
    @usableFromInline
    let runningLock: Lock = Lock()
    
    @usableFromInline
    let executor: MultiThreadedGlobalExecutor
    
    init(executor: MultiThreadedGlobalExecutor) {
        self.executor = executor
    }
    
    @inlinable
    public func run() {
        runningLock.withLock {
            running = true
        }
        
        while true {
            if !runningLock.withLock({
                running
            }) { break }
            drainQueues()
            let deadline = executor.handleTimedWork()
            if _slowPath(deadline > 0) {
                _ = executor.semaphore.wait(timeout: .init(uptimeNanoseconds: deadline))
            } else {
                executor.semaphore.wait()
            }
        }
        // Drain the queues one last time
        drainQueues()
    }
    
    @inline(__always)
    @usableFromInline
    internal func drainQueues() {
        while let job = executor.globalQueue.dequeue() {
            job._runSynchronously(on: _getCurrentExecutor())
            executor.handleTimedWork()
        }
    }
    
    public func stop() {
        runningLock.withLock {
            running = false
        }
        executor.semaphore.signal()
    }
    
    deinit {
        stop()
    }
}
#endif
