//
//  TurnScheduler.swift
//
//  Created by Sebastian Toivonen on 27.12.2021.
//

import SebbuTSDS

public final class TurnScheduler: @unchecked Sendable {
    private let timer: RepeatingTimer
    private let timeInterval: Double
    private let amount: Int
    
    public var turnsPerSecond: Double {
        Double(amount) / timeInterval
    }
    
    @usableFromInline
    internal let queue = MPSCQueue<UnsafeContinuation<Void, Never>>(cacheSize: 128)
    
    public init(amount: Int, interval: Double) {
        self.timeInterval = interval
        self.amount = amount
        self.timer = RepeatingTimer(delta: interval / Double(amount))
        
        timer.eventHandler = { [weak self] in
            guard let self = self else { return }
            self.queue.dequeue()?.resume()
        }
        timer.resume()
    }
    
    @inlinable
    public func wait() async {
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            queue.enqueue(continuation)
        }
    }
    
    deinit {
        queue.dequeueAll { continuation in
            continuation.resume()
        }
        timer.suspend()
    }
}
