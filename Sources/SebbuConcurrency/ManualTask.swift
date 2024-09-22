//
//  ManualTask.swift
//  
//
//  Created by Sebastian Toivonen on 31.7.2022.
//

import Synchronization

/// A unit of asynchronous work, similar to Task but ManualTasks are started manually
///
/// If the task is never started, it will remain forever in the waiting state, which will be a **memory leak**!
public struct ManualTask<Success: Sendable, Failure: Error>: Sendable {
    private let storage: ManualTaskStorage<Success, Failure>
}

public extension ManualTask {
    /// Starts the task
    func start() {
        storage.start()
    }
    
    /// Cancels the task
    func cancel() {
        storage.cancel()
    }
    
    /// The result or error from a throwing manual task, after it completes.
    var value: Success {
        get async throws {
            try await storage.value
        }
    }
    
    var result: Result<Success, Failure> {
        get async {
            do {
                return .success(try await value)
            } catch {
                return .failure(error as! Failure)
            }
        }
    }
}

public extension ManualTask where Failure == Never {
    /// Initializes a new `ManualTask` and inherits the current a actor context
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///     Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - operation: The operation to perform.
    init(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async -> Success) {
        self.storage = ManualTaskStorage(priority: priority, operation)
    }
    
    /// Creates a new detached `ManualTask`
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    static func detached(priority: TaskPriority? = nil, operation: @escaping @Sendable () async -> Success) -> ManualTask<Success, Failure> {
        ManualTask(storage: ManualTaskStorage.detached(priority: priority, operation))
    }
    
    /// The result from a nonthrowing manual task, after it completes.
    var value: Success {
        get async {
            await storage.value
        }
    }
}

extension ManualTask where Failure == Error {
    /// Initializes a new `ManualTask` and inherits the current a actor context
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///     Pass `nil` to use the priority from `Task.currentPriority`.
    ///   - operation: The operation to perform.
    init(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async throws -> Success) {
        self.storage = ManualTaskStorage(priority: priority, operation)
    }
    
    /// Creates a new detached `ManualTask`
    ///
    /// - Parameters:
    ///   - priority: The priority of the task.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    static func detached(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async throws -> Success) -> ManualTask<Success, Failure> {
        ManualTask(storage: ManualTaskStorage.detached(priority: priority, operation))
    }
}

internal final class ManualTaskStorage<Success: Sendable, Failure: Error>: Sendable {
    private let task: Task<Success, Failure>
    private let continuationContainer: ContinuationContainer
    
    private init(continuationContainer: ContinuationContainer, task: Task<Success, Failure>) {
        self.continuationContainer = continuationContainer
        self.task = task
    }
    
    // Starts the operation
    public func start() {
        continuationContainer.resume()
    }

    // Cancels the operation
    public func cancel() {
        task.cancel()
    }
}

extension ManualTaskStorage {
    var value: Success {
        get async throws {
            try await task.value
        }
    }
}

extension ManualTaskStorage where Failure == Never {
    convenience init(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async -> Success) {
        let continuationContainer = ContinuationContainer()
        let task = Task<Success, Failure>(priority: priority) {
            await withUnsafeContinuation { continuationContainer.set($0) }
            return await operation()
        }
        self.init(continuationContainer: continuationContainer, task: task)
    }
    
    static func detached(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async -> Success) -> ManualTaskStorage<Success, Failure> {
        let continuationContainer = ContinuationContainer()
        let task = Task<Success, Failure>.detached(priority: priority) {
            await withUnsafeContinuation { continuationContainer.set($0) }
            return await operation()
        }
        return ManualTaskStorage(continuationContainer: continuationContainer, task: task)
    }
    
    var value: Success {
        get async {
            await task.value
        }
    }
}

extension ManualTaskStorage where Failure == Error {
    convenience init(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async throws -> Success) {
        let continuationContainer = ContinuationContainer()
        let task = Task<Success, Failure>(priority: priority) {
            await withUnsafeContinuation { continuationContainer.set($0) }
            return try await operation()
        }
        self.init(continuationContainer: continuationContainer, task: task)
    }
    
    static func detached(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async throws -> Success) -> ManualTaskStorage<Success, Failure> {
        let continuationContainer = ContinuationContainer()
        let task = Task<Success, Failure>.detached(priority: priority) {
            await withUnsafeContinuation { continuationContainer.set($0) }
            return try await operation()
        }
        return ManualTaskStorage(continuationContainer: continuationContainer, task: task)
    }
}

extension ManualTaskStorage {
    private final class ContinuationContainer: @unchecked Sendable {
        enum ContinuationState: UInt8, AtomicRepresentable {
            case notInitialized
            case initializedAndWaitingForResume
            case resumePending
            case resumed
        }
        
        var continuation: UnsafeContinuation<Void, Never>?
        let state: Atomic<ContinuationState> = Atomic(.notInitialized)
        
        func set(_ continuation: UnsafeContinuation<Void, Never>) {
            assert(self.continuation == nil)
            self.continuation = continuation
            let (exchanged, currentState) = state.compareExchange(expected: .notInitialized, desired: .initializedAndWaitingForResume, ordering: .acquiring)
            // If we exchanged, it means that we are waiting on the start operation so nothing to do here
            if exchanged { return }
            // Otherwise the 'start' already happened so we just resume
            assert(currentState == .resumePending)
            state.store(.resumed, ordering: .releasing)
            continuation.resume()
            self.continuation = nil
        }
        
        func resume() {
            var (exchanged, currentState) = state.compareExchange(expected: .notInitialized, desired: .resumePending, ordering: .acquiring)
            // If the exchange succeeds, we will just wait for the continuation and they will immediately resume it
            // It can happen that resume was called by multiple users, so just return
            // If the continuation was already resumed, then again just return
            if exchanged || currentState == .resumePending || currentState == .resumed { return }
            // The continuation is waiting to be resumed
            assert(currentState == .initializedAndWaitingForResume)
            currentState = state.exchange(.resumed, ordering: .releasing)
            // If the original state was already .resumed, then someone else exchanged first,
            // so we will just return since they will resume the continuation
            if currentState == .resumed {
                return
            }
            assert(continuation != nil)
            self.continuation?.resume()
            self.continuation = nil
        }
        
        deinit {
            assert(continuation == nil, "Continuation wasn't resumed before deinitializing the container...")
        }
    }
}
