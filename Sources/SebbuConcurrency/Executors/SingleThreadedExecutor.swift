import Dispatch
import HeapModule
import SebbuTSDS

public final class SingleThreadedExecutor: @unchecked Sendable, Executor {
    @usableFromInline
    internal let unprocessedDelayedJobs: MPSCQueue<DelayedJob> = MPSCQueue(cacheSize: 128)

    @usableFromInline
    internal var delayedJobs: Heap<DelayedJob> = Heap()

    @usableFromInline
    internal let queues: [MPSCQueue<ExecutorJob>]

    @usableFromInline
    internal let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)

    public init() {
        self.queues = (0...4).map { _ in MPSCQueue(cacheSize: 2048) }
    }

    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob) {
        let index = getQueueIndex(priority: job.priority)
        _ = queues[index].enqueue(job)
        semaphore.signal()
    }

    @inline(__always)
    public func enqueue(_ job: consuming ExecutorJob, delay: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        let delayedJob = DelayedJob(job: job, deadline: now + delay)
        _ = unprocessedDelayedJobs.enqueue(delayedJob)
        semaphore.signal()
    }

    public func run() -> Never {
        while true {
            var nextTimedWorkDeadline: UInt64?
            for queueIndex in 0..<queues.count {
                nextTimedWorkDeadline = processDelayedJobs()
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
            }
            if let nextTimedWorkDeadline {
                _ = semaphore.wait(timeout: .init(uptimeNanoseconds: nextTimedWorkDeadline))
            } else {
                semaphore.wait()
            }
        }
    }

    @inlinable
    internal func processDelayedJobs() -> UInt64? {
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

    @inlinable
    internal func processQueue(index: Int) {
        let queue = queues[index]
        let iterations = getDrainIterations(queueIndex: index)
        for _ in 0..<iterations {
            if let job = queue.dequeue() {
                job.runSynchronously(isolatedTo: asUnownedSerialExecutor(), taskExecutor: asUnownedTaskExecutor())
            } else { break }
        }
    }
}

extension SingleThreadedExecutor: SerialExecutor, TaskExecutor {}