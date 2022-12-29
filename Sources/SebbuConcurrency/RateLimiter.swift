//
//  RateLimiter.swift
//  
//
//  Created by Sebastian Toivonen on 23.1.2022.
//
#if canImport(Atomics)
import Atomics

public class RateLimiter: @unchecked Sendable {
    
    internal struct Waiter {
        var permits: Int
        let continuation: UnsafeContinuation<Void, Never>
        
        init(permits: Int, continuation: UnsafeContinuation<Void,Never>) {
            self.permits = permits
            self.continuation = continuation
        }
    }
    
    public struct PermitsExhaustedError: Error {
        public let permitsOverLimit: Int
    }
    
    public let permitsPerSecond: Double
    public let maxPermits: Int
    
    private let timeInterval: Double
    private var permits: ManagedAtomic<Int>
    
    
    private let timer: RepeatingTimer
    
    public init(permits: Int, per interval: Double, maxPermits: Int) {
        self.timeInterval = interval
        self.permits = .init(permits)
        self.permitsPerSecond = Double(permits) / interval
        self.maxPermits = maxPermits
        
        let delta = max(0.01, interval / Double(permits))
        let permitsPerEvent = max(Int(permitsPerSecond * delta), 1)
        self.timer = RepeatingTimer(delta: delta)
        timer.eventHandler = { [weak self] in
            guard let self = self else { return }
            let currentPermits = self.permits.wrappingIncrementThenLoad(by: permitsPerEvent, ordering: .relaxed)
            self.permits.wrappingDecrement(by: max(0, currentPermits - maxPermits), ordering: .relaxed)
        }
        timer.resume()
    }
    
    public func acquire() throws {
        try acquire(permits: 1)
    }
    
    public func acquire(permits _permits: Int) throws {
        let currentPermits = permits.wrappingDecrementThenLoad(by: _permits, ordering: .relaxed)
        if currentPermits > 0 { return }
        permits.wrappingIncrement(by: _permits, ordering: .relaxed)
        throw PermitsExhaustedError(permitsOverLimit: -currentPermits)
    }
    
    deinit {
        timer.suspend()
        timer.eventHandler = nil
    }
}
#endif
