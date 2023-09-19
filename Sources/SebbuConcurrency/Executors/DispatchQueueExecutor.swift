//
//  DispatchQueueExecutor.swift
//  
//
//  Created by Sebastian Toivonen on 11.3.2023.
//

import Foundation
import Dispatch

#if swift(>=5.10)
#warning("Remove these since they are implemented in Dispatch")
#endif
extension DispatchQueue: @unchecked Sendable, SerialExecutor {
    /// If the queue is not serial, it breaks the serial executor requirements!
    @inlinable
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        async {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
    
    @inlinable
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
