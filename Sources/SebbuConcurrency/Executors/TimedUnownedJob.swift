//
//  TimedUnownedJob.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

@usableFromInline
internal struct TimedUnownedJob: Comparable {
    @usableFromInline
    let job: UnownedJob
    
    @usableFromInline
    let deadline: UInt64
    
    @inlinable
    internal init(job: UnownedJob, deadline: UInt64) {
        self.job = job
        self.deadline = deadline
    }
    
    @usableFromInline
    internal static func < (lhs: TimedUnownedJob, rhs: TimedUnownedJob) -> Bool {
        lhs.deadline < rhs.deadline
    }
    
    @usableFromInline
    internal static func == (lhs: TimedUnownedJob, rhs: TimedUnownedJob) -> Bool {
        lhs.deadline == rhs.deadline
    }
}
