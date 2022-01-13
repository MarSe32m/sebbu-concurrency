//
//  Channel.swift
//  
//
//  Created by Sebastian Toivonen on 2.1.2022.
//

import SebbuTSDS
import DequeModule

/// Channel is an object that can be used to communicate between tasks. Unlike AsyncStream,
/// multiple tasks can send and receive items from the Channel.
public struct Channel<Element>: @unchecked Sendable {
    public enum BufferingStrategy {
        /// Add the items to the buffer at no limit.
        case unbounded
        
        /// When the buffer is full, the oldest item will be removed to make room for the new one
        case dropOldest(maxCapacity: Int)
        
        /// When the buffer is full, the newest item (the item that is just being sent) will be dropped to preserve the buffer size
        case dropNewest(maxCapacity: Int)
    }
    
    public enum SendResult {
        /// The channel successfully enqueued the item. The remainingCapacity is an indication of how much room there is left.
        /// It might happen that there are many tasks enqueueing items so the capacity might be lower.
        case enqueued(remainingCapacity: Int)
        
        /// The stream didn't enqueue the item because the underlying buffer was full.
        case dropped(Element)
        
        /// The item wasn't enqueued because the channel was closed
        case closed
    }
    
    @usableFromInline
    internal let _storage: _ChannelStorage
    
    /// Indicates wheter the channel has been closed.
    public var isClosed: Bool {
        _storage.isClosed
    }
    
    /// The amount of items that the buffer is storing at the moment.
    public var count: Int {
        _storage.count
    }
    
    /// The amount of consumer tasks that are waiting to receive items.
    public var consumerCount: Int {
        _storage.consumerCount
    }
    
    public init(bufferingStrategy: BufferingStrategy = .unbounded) {
        _storage = _ChannelStorage(bufferingStrategy: bufferingStrategy)
    }
    
    /// Send an item to the channel. Depending on the buffering strategy and the amount of items in the buffer,
    /// the element might or might not be enqueued.
    @inlinable
    @discardableResult
    public func send(_ value: Element) -> SendResult {
        _storage.send(value)
    }
    
    /// Try to receive an item. If the buffer is empty then `nil` will be returned.
    @inlinable
    public func tryReceive() -> Element? {
        _storage.tryReceive()
    }
    
    /// Receive an item. This method might suspend or return immediately.
    /// If the buffer is not empty, then the first item will be returned without suspending.
    /// If the buffer is empty and the channel hasn't been closed, this method suspends until
    /// an item is sent to this channel. If the channel has been closed and the buffer is empty,
    /// then this method will return `nil` immediately.
    @inlinable
    public func receive() async -> Element? {
        await _storage.receive()
    }
    
    /// Close the channel. After this all items sent will be rejected.
    @inlinable
    public func close() {
        _storage.close()
    }
}

extension Channel: AsyncSequence {
    public struct Iterator: Sendable, AsyncIteratorProtocol {
        let _channelStorage: _ChannelStorage
        
        mutating public func next() async -> Element? {
            await _channelStorage.receive()
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(_channelStorage: _storage)
    }
}

extension Channel {
    @usableFromInline
    internal final class _ChannelStorage: @unchecked Sendable {
        //TODO: Give the ability to specify if the users wants to use a spinlock, since in all benchmarking I have done show that it is much faster than the lock, even for the os_unfair_lock implementation
        //#if canImport(Atomics)
        //@usableFromInline
        //internal let _lock = Spinlock()
        //#else
        
        @usableFromInline
        internal let _lock = Lock()

        @usableFromInline
        internal var _buffer = Deque<Element>()

        @usableFromInline
        internal var _consumers = Deque<(id: UInt64, continuation: UnsafeContinuation<Element?, Never>)>()

        @usableFromInline
        internal var _currentId: UInt64 = 0

        @usableFromInline
        internal var _isClosed: Bool = false

        public let bufferingStrategy: BufferingStrategy

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

        public init(bufferingStrategy: BufferingStrategy = .unbounded) {
            self.bufferingStrategy = bufferingStrategy
            if case .dropOldest(let maxCapacity) = bufferingStrategy {
                _buffer.reserveCapacity(maxCapacity)
            } else if case .dropNewest(let maxCapacity) = bufferingStrategy {
                _buffer.reserveCapacity(maxCapacity)
            }
        }

        @inlinable
        @discardableResult
        public final func send(_ value: Element) -> SendResult {
            _lock.lock()
            if _isClosed {
                _lock.unlock()
                return SendResult.closed
            }
            var result: SendResult
            if let consumer = _consumers.popFirst() {
                switch bufferingStrategy {
                case .unbounded:
                    _lock.unlock()
                    result = .enqueued(remainingCapacity: .max)
                case .dropOldest(let maxCapacity):
                    _lock.unlock()
                    result = .enqueued(remainingCapacity: maxCapacity)
                case .dropNewest(let maxCapacity):
                    _lock.unlock()
                    result = .enqueued(remainingCapacity: maxCapacity)
                }
                consumer.continuation.resume(returning: value)
                return result
            } else {
                switch bufferingStrategy {
                case .unbounded:
                    _buffer.append(value)
                    _lock.unlock()
                    return .enqueued(remainingCapacity: .max)
                case .dropOldest(let maxCapacity):
                    let count = _buffer.count
                    if count < maxCapacity {
                        _buffer.append(value)
                        _lock.unlock()
                        return .enqueued(remainingCapacity: maxCapacity - count - 1)
                    } else {
                        let removedItem = _buffer.removeFirst()
                        _buffer.append(value)
                        _lock.unlock()
                        return .dropped(removedItem)
                    }
                case .dropNewest(let maxCapacity):
                    let count = _buffer.count
                    if count < maxCapacity {
                        _buffer.append(value)
                        _lock.unlock()
                        return .enqueued(remainingCapacity: maxCapacity - count - 1)
                    } else {
                        _lock.unlock()
                        return .dropped(value)
                    }
                }
            }
        }

        @inlinable
        public final func tryReceive() -> Element? {
            _lock.withLock {
                _buffer.popFirst()
            }
        }

        public final func receive() async -> Element? {
            _lock.lock()
            if let value = _buffer.popFirst() {
                _lock.unlock()
                return value
            }
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
                // This way we ensure that the operation is perfomed before the cancel block.
                // But this happens only on cancellation (which should be rare / not happen 1000 times per second)
                // so I think this is a fine approach for now.
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

}
