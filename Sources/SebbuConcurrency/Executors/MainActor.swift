//
//  MainActor.swift
//  
//
//  Created by Sebastian Toivonen on 21.1.2023.
//

/// Reimplementing MainActor to work around https://github.com/apple/swift/issues/63104
// FIXME: Delete this once the mainExecutorHook is fixed so that it is called by the runtime
@globalActor
public final actor MainActor: GlobalActor, SerialExecutor {
    public static let shared: MainActor = MainActor()
    
    @inlinable
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        asUnownedSerialExecutor()
    }

    @inlinable
    public nonisolated func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        // This way we actually call the hook if it is set
        _enqueueMainExecutor(job)
    }

    @inlinable
    public nonisolated func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
