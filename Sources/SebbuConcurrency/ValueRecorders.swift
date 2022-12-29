//
//  ValueRecorders.swift
//  
//
//  Created by Sebastian Toivonen on 29.12.2022.
//

#if canImport(Atomics)
import Atomics
public final class MinValueRecorder<T: AtomicInteger> {
    @usableFromInline
    internal let currentValue: UnsafeAtomic<T> = .create(.zero)
    
    public var value: T {
        currentValue.load(ordering: .relaxed)
    }
    
    public init() {}
    
    deinit { currentValue.destroy() }
    
    @inlinable
    public final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue <= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue <= newValue { return }
        }
    }
    
    @inlinable
    public final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

public final class MaxValueRecorder<T: AtomicInteger> {
    @usableFromInline
    internal let currentValue: UnsafeAtomic<T> = .create(.zero)
    
    public var value: T {
        currentValue.load(ordering: .relaxed)
    }
    
    public init() {}
    
    deinit { currentValue.destroy() }
    
    @inlinable
    public final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue >= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue >= newValue { return }
        }
    }
    
    @inlinable
    public final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}
#endif
