//
//  Task+synchronously.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 18.2.2026.
//

import Dispatch
import Synchronization
import SebbuTSDS

public extension Task {
    /// Run asynchronous closure synchronously on the current thread. This function cannot be called from an asynchronous context,
    /// even if you are currently in a synchronous function.
    @available(*, noasync)
    static func synchronouslyDetached(_ body: @escaping @Sendable () async throws(Failure) -> Success) throws(Failure) -> Success {
        withUnsafeCurrentTask {
            precondition($0 == nil, "Running Task.synchronouslyDetached inside a Task")
        }
        let executor = _SynchronousExecutor<Success, Failure>()
        let _ = Task<Void, Never>.detached(executorPreference: executor) {
            do {
                let result = try await body()
                executor.result.load(ordering: .sequentiallyConsistent).initialize(to: (result, .none))
            } catch let error as Failure {
                executor.result.load(ordering: .sequentiallyConsistent).initialize(to: (.none, error))
            } catch {
                fatalError("Unreachable")
            }
            executor.finish()
        }
        executor.run()
        let (value, error) = executor.result.load(ordering: .sequentiallyConsistent).move()
        if let value {
            return value
        }
        if let error {
            throw error
        }
        fatalError("Unreachable")
    }
}

@usableFromInline
internal final class _SynchronousExecutor<T, E: Error>: @unchecked Sendable, TaskExecutor {
    @usableFromInline
    let semaphore: DispatchSemaphore = .init(value: 0)
    @usableFromInline
    let queue: MPSCQueue<ExecutorJob> = .init()
    @usableFromInline
    let running: Atomic<Bool> = .init(true)
    @usableFromInline
    let result: Atomic<UnsafeMutablePointer<(T?, E?)>> = .init(.allocate(capacity: 1))
    
    init() {}
    
    deinit {
        result.load(ordering: .sequentiallyConsistent).deallocate()
    }
    
    @inlinable
    func enqueue(_ job: consuming ExecutorJob) {
        let _job = queue.enqueue(job)
        precondition(_job == nil, "Failed to enqueue job to queue")
        semaphore.signal()
    }
    
    @inlinable
    func run() {
        while running.load(ordering: .relaxed) {
            semaphore.wait()
            if let job = queue.dequeue() {
                job.runSynchronously(on: asUnownedTaskExecutor())
            }
        }
    }
    
    @inlinable
    func finish() {
        running.store(false, ordering: .sequentiallyConsistent)
        semaphore.signal()
    }
}
