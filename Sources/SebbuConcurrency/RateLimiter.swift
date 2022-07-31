//
//  RateLimiter.swift
//  
//
//  Created by Sebastian Toivonen on 23.1.2022.
//
#if canImport(Atomics)
import SebbuTSDS
import Atomics
import DequeModule

//TODO: Reimplement. This should be a ratelimiter, not a turn scheduler. If there are no permits left, just throw an error or return false etc. 
public class RateLimiter: @unchecked Sendable {
    internal struct Waiter {
        var permits: Int
        let continuation: UnsafeContinuation<Void, Never>
        
        init(permits: Int, continuation: UnsafeContinuation<Void,Never>) {
            self.permits = permits
            self.continuation = continuation
        }
    }
    
    public let permitsPerSecond: Double
    
    private let timeInterval: Double
    private var permits: ManagedAtomic<Int>
    
    private var firstWaiter: Waiter?
    private let queue = MPSCQueue<Waiter>()
    
    private let timer: RepeatingTimer
    
    public init(permits: Int, per interval: Double) {
        self.timeInterval = interval
        self.permits = .init(permits)
        self.permitsPerSecond = Double(permits) / interval
        
        let delta = max(0.01, interval / Double(permits))
        let permitsPerEvent = Int(permitsPerSecond * delta)
        self.timer = RepeatingTimer(delta: delta)
        timer.eventHandler = { [weak self] in
            guard let self = self else { return }
            var permitsLeft = permitsPerEvent
            if self.firstWaiter == nil {
                self.firstWaiter = self.queue.dequeue()
            }
            while permitsLeft > 0 {
                guard self.firstWaiter != nil else { break }
                self.firstWaiter!.permits += permitsLeft
                if self.firstWaiter!.permits > 0 {
                    permitsLeft = self.firstWaiter!.permits
                    self.firstWaiter!.continuation.resume()
                    self.firstWaiter = self.queue.dequeue()
                } else {
                    permitsLeft = 0
                }
            }
            
            self.permits.wrappingIncrement(by: permitsPerEvent, ordering: .relaxed)
        }
        timer.resume()
    }
    
    public func acquire() async {
        await acquire(permits: 1)
    }
    
    public func acquire(permits _permits: Int) async {
        if permits.wrappingDecrementThenLoad(by: _permits, ordering: .relaxed) > 0 {
            return
        }
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            let waiter = Waiter(permits: -_permits, continuation: continuation)
            queue.enqueue(waiter)
        }
    }
    
    deinit {
        timer.eventHandler = nil
        timer.suspend()
        queue.dequeueAll { $0.continuation.resume() }
    }
}
#endif
