import Dispatch
import Foundation
import SebbuTSDS
import Synchronization
import HeapModule

public final class MultiThreadedTaskExecutor: @unchecked Sendable, TaskExecutor {
    @usableFromInline
    internal let _running: Atomic<Bool> = Atomic(false)

    public var running: Bool {
        _running.load(ordering: .relaxed)
    }

    public let numberOfThreads: Int

    @usableFromInline
    internal var workers: UnsafeMutableBufferPointer<Worker>

    @usableFromInline
    internal let roundRobinIndex: Atomic<Int> = Atomic(0)

    @usableFromInline
    internal var delayedJobs: Heap<DelayedJob> = Heap()

    @usableFromInline
    internal let unprocessedDelayedJobs: MPSCQueue<DelayedJob> = MPSCQueue(cacheSize: 128)

    @usableFromInline
    internal let delayedWorkProcessLock: Atomic<Bool> = Atomic(false)

    public init(numberOfThreads: Int) {
        precondition(numberOfThreads > 0, "There must be atleast one thread!")
        self.numberOfThreads = numberOfThreads
        self.workers = .allocate(capacity: numberOfThreads)
        start()
    }

    deinit {
        shutdown()
        workers.deallocate()
    }

    public func start() {
        if running { return }
        _running.store(true, ordering: .sequentiallyConsistent)
        for i in 0..<numberOfThreads {
            let worker = Worker(executor: self, id: i)
            workers.initializeElement(at: i, to: worker)
        }
        for worker in workers {
            Thread.detachNewThread { worker.run() }
        }
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        precondition(_running.load(ordering: .relaxed), "Tried enqueue jobs on a shutdown MultiThreadedExecutor")
        let (workerIndex, _) = roundRobinIndex.wrappingAdd(1, ordering: .relaxed)
        if workerIndex < 0 {
            roundRobinIndex.store(1, ordering: .relaxed)
            workers[0].enqueue(job)
        } else {
            workers[workerIndex % numberOfThreads].enqueue(job)
        }
    }

    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob, delay: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        let delayedJob = DelayedJob(job: job, deadline: now + delay)
        _ = unprocessedDelayedJobs.enqueue(delayedJob)
        workers[0].semaphore.signal()
    }

    @usableFromInline
    internal func processTimedJobs() -> UInt64? {
        if delayedWorkProcessLock.exchange(true, ordering: .acquiring) { return nil }
        defer { delayedWorkProcessLock.store(false, ordering: .releasing) }
        let now = DispatchTime.now().uptimeNanoseconds
        while let job = unprocessedDelayedJobs.dequeue() {
            if job.deadline <= now {
                enqueue(ExecutorJob(job.executorJob))
            } else {
                delayedJobs.insert(job)
            }
        }
        while !delayedJobs.isEmpty && delayedJobs.max!.deadline <= now {
            let job = delayedJobs.removeMax()
            enqueue(ExecutorJob(job.executorJob))
        }
        return delayedJobs.max?.deadline
    }

    public func shutdown() {
        if !_running.exchange(false, ordering: .sequentiallyConsistent) {
            return
        }
        for worker in workers {
            worker.shutdown()
        }
        workers.deinitialize()
    }
}

extension MultiThreadedTaskExecutor {
    @usableFromInline
    final class Worker: @unchecked Sendable {
        public let running: Atomic<Bool> = Atomic(true)

        public let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)

        public let queues: UnsafeMutableBufferPointer<MPSCQueue<ExecutorJob>>
        public let stealQueues: UnsafeMutableBufferPointer<SPMCBoundedQueue<ExecutorJob>>

        unowned let executor: MultiThreadedTaskExecutor

        public let id: Int

        public init(executor: MultiThreadedTaskExecutor, id: Int) {
            self.executor = executor
            self.id = id
            self.queues = UnsafeMutableBufferPointer<MPSCQueue<ExecutorJob>>.allocate(capacity: 5)
            self.stealQueues = UnsafeMutableBufferPointer<SPMCBoundedQueue<ExecutorJob>>.allocate(capacity: 5)
            for i in 0...4 {
                queues.initializeElement(at: i, to: .init(cacheSize: 2048))
                stealQueues.initializeElement(at: i, to: .init(size: 128))
            }
        }

        deinit {
            queues.deinitialize()
            queues.deallocate()
            stealQueues.deinitialize()
            stealQueues.deallocate()
        }

        public func enqueue(_ job: consuming ExecutorJob) {
            let queueIndex = getQueueIndex(priority: job.priority)
            _ = queues[queueIndex].enqueue(job)
            semaphore.signal()
        }

        public func run() {
            outer: while running.load(ordering: .relaxed) {
                var nextTimedWorkDeadline: UInt64?
                for queueIndex in 0..<queues.count {
                    nextTimedWorkDeadline = executor.processTimedJobs()
                    // Process higher priority work
                    for index in 0..<queueIndex {
                        processQueue(index: index)
                    }

                    // Process current priority
                    processQueue(index: queueIndex)

                    // Process again higher priority work
                    for index in 0..<queueIndex {
                        processQueue(index: index)
                    }

                    // Steal from other workers of current priority
                    stealOtherWorkersWork(queueIndex: queueIndex)
                }

                if let nextTimedWorkDeadline {
                    _ = semaphore.wait(timeout: .init(uptimeNanoseconds: nextTimedWorkDeadline))
                } else {
                    semaphore.wait()
                }
            }
        }

        @usableFromInline
        internal func processQueue(index: Int) {
            let queue = queues[index]
            let stealQueue = stealQueues[index]
            let iterations = getDrainIterations(queueIndex: index)
            // Move jobs to steal queues and run the one that doesn't fit
            for _ in 0..<iterations {
                if let job = queue.dequeue() {
                    if let job = stealQueue.enqueue(job) {
                        job.runSynchronously(on: executor.asUnownedTaskExecutor())
                        break
                    }
                } else {
                    break
                }
            }

            // Run most recent jobs (for the 2x size of the stealQueue)
            for _ in 0..<2*128 {
                queue.dequeue()?.runSynchronously(on: executor.asUnownedTaskExecutor())
            }

            // Drain the stealQueue
            for _ in 0..<min(iterations, 128) {
                if let job = stealQueue.dequeue() {
                    job.runSynchronously(on: executor.asUnownedTaskExecutor())
                } else {
                    break
                }
            }
        }

        @usableFromInline
        internal func stealOtherWorkersWork(queueIndex: Int) {
            for i in 0..<executor.numberOfThreads where i != id {
                let worker = executor.workers[i]
                for queueIndex in 0..<stealQueues.count {
                    let stealQueue = worker.stealQueues[queueIndex]
                    for _ in 0..<getStealIterations(queueIndex: queueIndex) {
                        if let job = stealQueue.dequeue() {
                            job.runSynchronously(on: executor.asUnownedTaskExecutor())
                        } else { break }
                    }
                }
            }
        }

        public func shutdown() {
            running.store(false, ordering: .relaxed)
            semaphore.signal()
        }
    }
}