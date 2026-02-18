//
//  Thread+Async.swift
//  sebbu-concurrency
//
//  Created by Sebastian Toivonen on 18.2.2026.
//

import Foundation

public extension Thread {
    /// Run the given closure in a new thread
    static func detachNewThread(_ body: @escaping @Sendable () async -> Void) {
        detachNewThread { Task.synchronouslyDetached(body) }
    }
}
