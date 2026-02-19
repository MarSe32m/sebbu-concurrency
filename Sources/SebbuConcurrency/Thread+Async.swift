//
//  Thread+Async.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 18.2.2026.
//

import Foundation

public extension Thread {
    /// Run the given `operation` in a new detached thread
    static func detachNewThread(operation: @escaping @Sendable () async -> Void) {
        detachNewThread { Task.synchronouslyDetached(operation: operation) }
    }
    
    /// Creates a new `Thread` with a given `operation`.
    ///
    /// Start the thread after creation with `Thread.start()`
    convenience init(operation: @escaping @Sendable () async -> Void) {
        self.init {
            Task.synchronouslyDetached(operation: operation)
        }
    }
}
