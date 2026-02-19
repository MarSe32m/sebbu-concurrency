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
    /// Runs the given operation synchronously
    /// as part of a new _unstructured_ _detached_ top-level task.
    ///
    /// This method cannot be called from an asynchronous context.
    ///
    /// - Parameters:
    ///   - name: Human readable name of the task.
    ///   - taskExecutor: The task executor that the child task should be started on and keep using.
    ///      Explicitly passing `nil` as the executor preference is equivalent to no preference,
    ///      and effectively means to inherit the outer context's executor preference.
    ///      You can also pass the ``globalConcurrentExecutor`` global executor explicitly.
    ///   - priority: The priority of the operation task.
    ///   - operation: The operation to perform.
    /// - Throws: If the `operation` throws an error
    /// - Returns: The value returned by `operation`.
    @available(*, noasync)
    static func synchronouslyDetached(name: String? = nil,
                                      executorPreference taskExecutor: (any TaskExecutor)? = nil,
                                      priority: TaskPriority? = nil,
                                      operation: @escaping @Sendable () async throws(Failure) -> Success) throws(Failure) -> Success {
        withUnsafeCurrentTask {
            precondition($0 == nil, "Running Task.synchronouslyDetached inside a Task")
        }
        let executor = _SynchronousExecutor<Success, Failure>()
        let _ = Task<Void, Never>.detached(name: name, executorPreference: executor, priority: priority) {
            do {
                let result = try await withTaskExecutorPreference(taskExecutor, operation: operation)
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
    
    /// Runs immediately and synchronously the given `operation`.
    ///
    /// This method cannot be called from an asynchronous context.
    ///
    /// - Parameters:
    ///   - name: Human readable name of the task.
    ///   - taskExecutor: The task executor that the child task should be started on and keep using.
    ///      Explicitly passing `nil` as the executor preference is equivalent to no preference,
    ///      and effectively means to inherit the outer context's executor preference.
    ///      You can also pass the ``globalConcurrentExecutor`` global executor explicitly.
    ///   - priority: The priority of the operation task.
    ///   - operation: The operation to perform.
    /// - Throws: If the `operation` throws an error
    /// - Returns: The value returned by `operation`.
    @available(*, noasync)
    @available(macOS 26.0, *)
    static func synchronouslyImmediateDetached(name: String? = nil,
                                      executorPreference taskExecutor: (any TaskExecutor)? = nil,
                                      priority: TaskPriority? = nil,
                                      operation: @escaping @Sendable () async throws(Failure) -> Success) throws(Failure) -> Success {
        withUnsafeCurrentTask {
            precondition($0 == nil, "Running Task.synchronouslyDetached inside a Task")
        }
        let executor = _SynchronousExecutor<Success, Failure>()
        let _ = Task<Void, Never>.immediateDetached(name: name, priority: priority, executorPreference: executor) {
            do {
                let result = try await withTaskExecutorPreference(taskExecutor, operation: operation)
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
