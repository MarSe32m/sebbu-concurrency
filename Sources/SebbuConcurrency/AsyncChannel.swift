//
//  AsyncChannel.swift
//  
//
//  Created by Sebastian Toivonen on 2.1.2022.
//

import SebbuTSDS
import DequeModule

/// Channel is an object that can be used to communicate between tasks. Unlike AsyncStream,
/// multiple tasks can send and receive items from the Channel.
public struct AsyncChannel<Element>: @unchecked Sendable {
    public enum BufferingStrategy {
        /// Add the items to the buffer at no limit.
        case unbounded
        
        /// Bounded
        case bounded(capacity: Int)
    }
    
    public enum SendError: Error {
        /// The channel has been closed
        case closed
    }
    
    @usableFromInline
    internal let _storage: _AsyncChannelStorage
    
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
    
    /// The amound of producer tasks that are waiting to send items.
    public var producerCount: Int {
        _storage.producerCount
    }
    
    public init(bufferingStrategy: BufferingStrategy = .unbounded) {
        _storage = _AsyncChannelStorage(bufferingStrategy: bufferingStrategy)
    }
    
    /// Try to send an item to the channel. Depending on the buffering strategy and the amount of items in the buffer,
    /// the element might or might not be enqueued.
    @inlinable
    @discardableResult
    public func trySend(_ value: Element) -> Bool {
        _storage.trySend(value)
    }
    
    @inlinable
    public func send(_ value: Element) async throws {
        try await _storage.send(value)
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

extension AsyncChannel: AsyncSequence {
    public struct Iterator: Sendable, AsyncIteratorProtocol {
        let _channelStorage: _AsyncChannelStorage
        
        mutating public func next() async -> Element? {
            await _channelStorage.receive()
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(_channelStorage: _storage)
    }
}

extension AsyncChannel {
    @usableFromInline
    internal final class _AsyncChannelStorage: @unchecked Sendable {
        @usableFromInline
        internal let _lock = Lock()

        @usableFromInline
        internal var _buffer = Deque<Element>()

        @usableFromInline
        internal var _consumers = Deque<(id: UInt64, continuation: UnsafeContinuation<Element?, Never>)>()
        
        @usableFromInline
        internal var _producers = Deque<(id: UInt64, continuation: UnsafeContinuation<Void, Error>, value: Element)>()

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

        public var producerCount: Int {
            _lock.withLock {
                _producers.count
            }
        }
        
        public init(bufferingStrategy: BufferingStrategy = .unbounded) {
            self.bufferingStrategy = bufferingStrategy
            if case .bounded(let maxCapacity) = bufferingStrategy {
                _buffer.reserveCapacity(maxCapacity)
            }
        }

        @inlinable
        @discardableResult
        public final func trySend(_ value: Element) -> Bool {
            _lock.lock()
            if _isClosed {
                _lock.unlock()
                return false
            }
            if let consumer = _consumers.popFirst() {
                _lock.unlock()
                consumer.continuation.resume(returning: value)
                return true
            }
            defer { _lock.unlock() }
            switch bufferingStrategy {
            case .unbounded:
                _buffer.append(value)
                return true
            case .bounded(let maxCapacity):
                let count = _buffer.count
                if count < maxCapacity {
                    _buffer.append(value)
                }
                return count < maxCapacity
            }
        }

        @inlinable
        public final func send(_ value: Element) async throws {
            _lock.lock()
            if _isClosed {
                _lock.unlock()
                throw SendError.closed
            }
            if let consumer = _consumers.popFirst() {
                _lock.unlock()
                consumer.continuation.resume(returning: value)
                return
            }
            switch bufferingStrategy {
            case .unbounded:
                _buffer.append(value)
                _lock.unlock()
                return
            case .bounded(let maxCapacity):
                let count = _buffer.count
                if count < maxCapacity {
                    _buffer.append(value)
                    _lock.unlock()
                    return
                }
                let id = _currentId + 1
                _currentId += 1
                
                try await withTaskCancellationHandler(operation: {
                    try await withUnsafeThrowingContinuation({ (continuation: UnsafeContinuation<Void, Error>) in
                        _producers.append((id: id, continuation: continuation, value: value))
                        _lock.unlock()
                    })
                }, onCancel: {
                    // This way we ensure that the operation above is perfomed before the cancel block.
                    // But this happens only on cancellation (which should be rare/not happen 1000 times per second)
                    // so I think this is a fine approach for now.
                    Task {
                        _lock.withLock {
                            _producers.removeAll { (identifier, continuation, _) in
                                if id == identifier {
                                    continuation.resume(throwing: CancellationError())
                                    return true
                                }
                                return false
                            }
                        }
                    }
                })
            }
        }
        
        @inlinable
        public final func tryReceive() -> Element? {
            _lock.withLock {
                if let value = _buffer.popFirst() {
                    if let (_, continuation, producerValue) = _producers.popFirst() {
                        _buffer.append(producerValue)
                        continuation.resume()
                    }
                    return value
                }
                return nil
            }
        }

        public final func receive() async -> Element? {
            _lock.lock()
            if let value = _buffer.popFirst() {
                if let (_, continuation, producerValue) = _producers.popFirst() {
                    _buffer.append(producerValue)
                    continuation.resume()
                }
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
                    // This is fine, since it is guaranteed that this closure is executed in the same context as the calling function and thus this doesn't switch threads.
                    _lock.unlock()
                }
            } onCancel: {
                // This way we ensure that the operation above is perfomed before the cancel block.
                // But this happens only on cancellation (which should be rare/not happen 1000 times per second)
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
                while let (_, continuation) = _consumers.popFirst() {
                    continuation.resume(returning: nil)
                }
                while let (_, continuation, _) = _producers.popFirst() {
                    continuation.resume(throwing: SendError.closed)
                }
            }
        }
    }

}
