//
//  DispatchQueueExecutor.swift
//  
//
//  Created by Sebastian Toivonen on 11.3.2023.
//

import Foundation
import Dispatch

#if swift(>=5.9)
#warning("Remove these since they are implemented in Dispatch")
#endif
extension DispatchQueue: @unchecked Sendable, SerialExecutor {
    /// If the queue is not serial, it breaks the serial executor requirements!
    @inlinable
    public func enqueue(_ job: UnownedJob) {
        async {
            job._runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
    
    @inlinable
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

public final class DispatchQueueExecutor: Sendable, SerialExecutor {
    @usableFromInline
    let queue: DispatchQueue
    
    public init(name: String) {
        queue = DispatchQueue(label: "fi.sebbu-concurrency.dispatch-queue-executor.\(name)")
    }
    
    /// The passed in queue must be a **serial** dispatch queue
    public init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    
    //TODO: Switch to enqueue(job: Job) and run them using `job.runSynchronously(on: self.asUnownedSerialExecutor())`
    @inlinable
    public func enqueue(_ job: UnownedJob) {
        queue.async {
            job._runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
    
    @inlinable
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
