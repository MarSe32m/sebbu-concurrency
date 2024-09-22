@inlinable
@inline(__always)
internal func getQueueIndex(priority: JobPriority) -> Int {
    let taskPrio = TaskPriority(priority) ?? .medium
    if taskPrio.rawValue >=  TaskPriority.high.rawValue {
        return 0
    } else if taskPrio.rawValue >= TaskPriority.medium.rawValue {
        return 1
    } else if taskPrio.rawValue >= TaskPriority.low.rawValue {
        return 2
    } else if taskPrio.rawValue >= TaskPriority.background.rawValue {
        return 3
    } else { 
        return 4
    }
}

@inlinable
@inline(__always)
internal func getDrainIterations(queueIndex: Int) -> Int {
    switch queueIndex {
        case 0: .max // high
        case 1: 128 // medium
        case 2: 2 // low
        default : 1 // background and lower
    }
}

@inlinable
@inline(__always)
internal func getStealIterations(queueIndex: Int) -> Int {
    switch queueIndex {
        case 0: 16 // high
        case 1: 8 // medium
        case 2: 1 // low
        default : 1 // background and lower
    }
}

@usableFromInline
internal struct DelayedJob: Comparable {
    @usableFromInline
    let executorJob: UnownedJob

    @usableFromInline
    let deadline: UInt64

    init(job: consuming ExecutorJob, deadline: UInt64) {
        self.executorJob = UnownedJob(job)
        self.deadline = deadline
    }

    @usableFromInline
    static func < (lhs: DelayedJob, rhs: DelayedJob) -> Bool {
        lhs.deadline > rhs.deadline
    }

    @usableFromInline
    static func ==(lhs: DelayedJob, rhs: DelayedJob) -> Bool {
        lhs.deadline == rhs.deadline
    }
}