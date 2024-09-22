//
//  ContinuationContainer.swift
//  
//
//  Created by Sebastian Toivonen on 16.7.2023.
//

import Synchronization

//TODO: Documentation
public final class ContinuationContainer<T, E>: @unchecked Sendable where E: Error {
    @usableFromInline
    enum ContinuationState: UInt8, AtomicRepresentable {
        case notInitialized
        case initializedAndWaitingForResume
        case resumePending
        case resumed
    }
    
    @usableFromInline
    var continuation: UnsafeContinuation<T, E>?
    
    @usableFromInline
    let state: Atomic<ContinuationState> = Atomic(.notInitialized)
    
    @usableFromInline
    var value: T?
    
    @usableFromInline
    var failure: E?
    
    public init() {}
    
    @inlinable
    public func set(_ continuation: UnsafeContinuation<T, E>) {
        assert(self.continuation == nil)
        self.continuation = continuation
        let (exchanged, currentState) = state.compareExchange(expected: .notInitialized, desired: .initializedAndWaitingForResume, ordering: .acquiring)
        // If we exchanged, it means that we are waiting on call to `resume` here, so nothing to do here
        if exchanged { return }
        // Otherwise the resume already happened so we just resume the passed continuation
        assert(currentState == .resumePending)
        state.store(.resumed, ordering: .releasing)
        if let value = value {
            continuation.resume(returning: value)
        } else if let failure = failure {
            continuation.resume(throwing: failure)
        } else {
            fatalError("Neither value nor failure were set before resuming ")
        }
        // We nil out the results to avoid keeping a possible reference to an object
        self.continuation = nil
        self.value = nil
        self.failure = nil
    }
    
    @inlinable
    public func resume(returning value: sending T) {
        self.value = value
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
        self.continuation?.resume(returning: value)
        self.continuation = nil
    }
    
    @inlinable
    public func resume(throwing failure: E) {
        self.failure = failure
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
        self.continuation?.resume(throwing: failure)
        self.continuation = nil
    }
    
    @inlinable
    public func reset() {
        self.state.store(.notInitialized, ordering: .relaxed)
        self.continuation = nil
        self.value = nil
        self.failure = nil
    }
    
    deinit {
        precondition(continuation == nil, "Continuation wasn't resumed before deinitializing the container...")
    }
}

extension ContinuationContainer where T == Void {
    @inline(__always)
    func resume() {
        resume(returning: ())
    }
}
