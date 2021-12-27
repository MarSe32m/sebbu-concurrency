//
//  TurnScheduler.swift
//
//  Created by Sebastian Toivonen on 27.12.2021.
//

import SebbuTSDS

public struct TurnScheduler {
    private let timer: RepeatingTimer
    private let timeInterval: Double
    private let amount: Int
    
    public var turnsPerSecond: Double {
        Double(amount) / timeInterval
    }
    
    private var queue = LockedQueue<UnsafeContinuation<Void, Never>>(size: 2, resizeAutomatically: true)
    
    public init(amount: Int, interval: Double) {
        self.timeInterval = interval
        self.amount = amount
        self.timer = RepeatingTimer(delta: interval / Double(amount))
        
        timer.eventHandler = { [weak queue] in
            queue?.dequeue()?.resume()
        }
        timer.resume()
    }
    
    public func wait() async {
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            queue.enqueue(continuation)
        }
    }
}
