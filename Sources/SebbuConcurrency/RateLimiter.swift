//
//  RateLimiter.swift
//  
//
//  Created by Sebastian Toivonen on 23.1.2022.
//

import SebbuTSDS

public class RateLimiter: @unchecked Sendable {
    public struct PermitsExhaustedError: Error {
        public let permitsOverLimit: Int
    }
    
    public let maxPermits: Int
    
    private let permitsPerInterval: Int
    private let timeInterval: Duration
    private var lastPermitRefill: ContinuousClock.Instant = .now
    private var permits: Int
    
    private let lock = Lock()
    
    public init(permits: Int, perInterval: Duration, maxPermits: Int) {
        self.timeInterval = perInterval
        self.permits = permits
        self.maxPermits = maxPermits
        self.permitsPerInterval = permits
    }
    
    public func acquire() throws {
        try lock.withLock { try _acquire(permits: 1) }
    }
    
    public func acquire(permits: Int) throws {
        try lock.withLock { try _acquire(permits: permits) }
    }
    
    @inline(__always)
    internal func _acquire(permits _permits: Int) throws {
        self.permits -= _permits
        if self.permits >= 0 { return }
        _refill()
        if self.permits <= 0 {
            self.permits += _permits
            throw PermitsExhaustedError(permitsOverLimit: _permits - permits)
        }
    }
    
    @inline(__always)
    internal func _refill() {
        let timeSinceLastRefill = .now - lastPermitRefill
        let newPermits = Int(Double(permitsPerInterval) * (timeSinceLastRefill / timeInterval))
        if newPermits > 0 { lastPermitRefill = .now }
        permits = min(permits + newPermits, maxPermits)
    }
}
