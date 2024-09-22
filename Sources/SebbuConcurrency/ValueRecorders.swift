//
//  ValueRecorders.swift
//  
//
//  Created by Sebastian Toivonen on 29.12.2022.
//

import Synchronization

public typealias AtomicInteger = AtomicRepresentable & FixedWidthInteger

public final class MinValueRecorder<T: AtomicInteger> {
    @usableFromInline
    internal let currentValue: Atomic<T> = .init(.zero)
    
    public init() {}
}

// 8 bit representation
public extension MinValueRecorder where T.AtomicRepresentation == _Atomic8BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    @inline(__always)
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue <= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue <= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 16 bit representation
public extension MinValueRecorder where T.AtomicRepresentation == _Atomic16BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    @inline(__always)
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue <= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue <= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 32 bit representation
public extension MinValueRecorder where T.AtomicRepresentation == _Atomic32BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    @inline(__always)
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue <= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue <= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 64 bit representation
public extension MinValueRecorder where T.AtomicRepresentation == _Atomic64BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    @inline(__always)
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue <= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue <= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 128 bit representation
public extension MinValueRecorder where T.AtomicRepresentation == _Atomic128BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    @inline(__always)
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue <= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue <= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}


public final class MaxValueRecorder<T: AtomicInteger> {
    @usableFromInline
    internal let currentValue: Atomic<T> = .init(.zero)
    
    public init() {}
}

// 8 bit representation
public extension MaxValueRecorder where T.AtomicRepresentation == _Atomic8BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue >= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue >= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 16 bit representation
public extension MaxValueRecorder where T.AtomicRepresentation == _Atomic16BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue >= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue >= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 32 bit representation
public extension MaxValueRecorder where T.AtomicRepresentation == _Atomic32BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue >= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue >= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 64 bit representation
public extension MaxValueRecorder where T.AtomicRepresentation == _Atomic64BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue >= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue >= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}

// 128 bit representation
public extension MaxValueRecorder where T.AtomicRepresentation == _Atomic128BitStorage {
    var value: T { currentValue.load(ordering: .relaxed) }

    @inlinable
    final func update(_ newValue: T) {
        let currentValue = currentValue.load(ordering: .acquiring)
        if currentValue >= newValue { return }
        while true {
            let (exchanged, currentValue) = self.currentValue.compareExchange(expected: currentValue, desired: newValue, ordering: .acquiringAndReleasing)
            if exchanged || currentValue >= newValue { return }
        }
    }
    
    @inlinable
    @inline(__always)
    final func reset(_ value: T) {
        currentValue.store(value, ordering: .sequentiallyConsistent)
    }
}