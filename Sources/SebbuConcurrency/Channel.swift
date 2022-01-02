//
//  Channel.swift
//  
//
//  Created by Sebastian Toivonen on 2.1.2022.
//

import SebbuTSDS
import DequeModule
import Dispatch
#if canImport(Atomics)
import Atomics
#endif
import Foundation

public final class Channel<Element>: @unchecked Sendable {
    //TODO: Implement ability to specify buffer size
    
    #if canImport(Atomics)
    @usableFromInline
    internal let _lock = Spinlock()
    #else
    @usableFromInline
    internal let _lock = NSLock()
    #endif
    
    
    @usableFromInline
    internal var _buffer = Deque<Element>()
    
    @usableFromInline
    internal var _consumers = Deque<(id: UInt64, continuation: UnsafeContinuation<Element?, Never>)>()
    
    @usableFromInline
    internal var _currentId: UInt64 = 0
    
    @usableFromInline
    internal var _isClosed: Bool = false
    
    public var isClosed: Bool {
        _lock.withLock {
            _isClosed
        }
    }
    
    public var count: Int {
        _lock.withLock {
            _buffer.count
        }
    }
    
    public var consumerCount: Int {
        _lock.withLock {
            _consumers.count
        }
    }
    
    public init() {}
    
    //TODO: Depending on the buffering strategy, maybe this should return some kind of indication wheter the value was enqueued or not.
    @inlinable
    public final func send(_ value: Element) {
        var continuation: UnsafeContinuation<Element?, Never>? = nil
        _lock.withLock {
            if _isClosed { return }
            if let consumer = _consumers.popFirst() {
                continuation = consumer.continuation
            } else {
                _buffer.append(value)
            }
        }
        continuation?.resume(returning: value)
    }
    
    @inlinable
    public final func tryReceive() -> Element? {
        _lock.withLock {
            _buffer.popFirst()
        }
    }
    
    public final func receive() async -> Element? {
        if let value = tryReceive() {
            return value
        }
        _lock.lock()
        if _isClosed {
            _lock.unlock()
            return nil
        }
        
        let id = _currentId + 1
        _currentId += 1
        
        return await withTaskCancellationHandler {
            return await withUnsafeContinuation { (continuation: UnsafeContinuation<Element?, Never>) in
                _consumers.append((id: id, continuation: continuation))
                _lock.unlock()
            }
        } onCancel: {
            //TODO: This way we ensure that the operation is perfomed before the cancel block.
            Task {
                _lock.withLock {
                    _consumers.removeAll { (identifier, continuation) in
                        if id == identifier {
                            continuation.resume(returning: nil)
                            return true
                        }
                        return false
                    }
                }
            }
        }
    }
    
    @inlinable
    public final func close() {
        _lock.withLock {
            _isClosed = true
            while let continuation = _consumers.popFirst()?.continuation {
                continuation.resume(returning: nil)
            }
        }
    }
}

extension Channel: AsyncSequence {
    public typealias Element = Element
    
    public struct ChannelIterator<Element>: AsyncIteratorProtocol {
        let channel: Channel<Element>
        
        internal init(channel: Channel<Element>) {
            self.channel = channel
        }
        
        mutating public func next() async -> Element? {
            await channel.receive()
        }
    }
    
    public func makeAsyncIterator() -> ChannelIterator<Element> {
        ChannelIterator(channel: self)
    }
}
