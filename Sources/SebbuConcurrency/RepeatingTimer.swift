//
//  RepeatingTimer.swift
//
//  Created by Sebastian Toivonen on 12.5.2020.
//
//  Copyright © 2021 Sebastian Toivonen. All rights reserved.

import Dispatch

/// RepeatingTimer mimics the API of DispatchSourceTimer but in a way that prevents
/// crashes that occur from calling resume multiple times on a timer that is
/// already resumed
public final class RepeatingTimer {
    public let timeInterval: DispatchTimeInterval
    
    public var eventHandler: (() -> Void)?
    
    private let queue: DispatchQueue?
    private let timer: DispatchSourceTimer

    private var state: State = .suspended
    private enum State {
        case suspended
        case resumed
    }

    /// Delta in seconds
    public init(delta: Double, queue: DispatchQueue? = nil) {
        self.timeInterval = DispatchTimeInterval.nanoseconds(Int(delta * 1_000_000_000.0))
        self.queue = queue
        self.timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + self.timeInterval, repeating: self.timeInterval)
        timer.setEventHandler { [weak self] in
            self?.eventHandler?()
        }
    }
    
    public init(timeInterval:  DispatchTimeInterval, queue: DispatchQueue? = nil) {
        self.timeInterval = timeInterval
        self.queue = queue
        self.timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + self.timeInterval, repeating: self.timeInterval)
        timer.setEventHandler { [weak self] in
            self?.eventHandler?()
        }
    }
    
    /// Resume the timer
    public func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }

    /// Suspend / pause the timer
    public func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
    
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        resume()
        eventHandler = nil
    }
}
