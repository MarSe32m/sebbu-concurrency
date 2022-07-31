//
//  TaskGroupExtensions.swift
//  
//
//  Created by Sebastian Toivonen on 1.2.2022.
//

public extension TaskGroup {
    /// Waits for the semaphore before the task is enqueued to the TaskGroup.
    mutating func addTask(with semaphore: AsyncSemaphore, priority: TaskPriority? = nil, operation: @escaping @Sendable () async -> ChildTaskResult) async {
        await semaphore.wait()
        addTask(priority: priority) {
            defer { semaphore.signal() }
            return await operation()
        }
    }
}

public extension ThrowingTaskGroup {
    /// Waits for the semaphore before the task is enqueued to the ThrowingTaskGroup
    mutating func addTask(with semaphore: AsyncSemaphore, priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> ChildTaskResult) async {
        await semaphore.wait()
        addTask(priority: priority) {
            defer { semaphore.signal() }
            return try await operation()
        }
    }
}
