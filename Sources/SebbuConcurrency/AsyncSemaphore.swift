//
//  AsyncSemaphore.swift
//  
//
//  Created by Sebastian Toivonen on 6.1.2022.
//

import DequeModule
import SebbuTSDS

/// A semaphore that corresponds to a counting semaphore in the synchronous world.
/// This one is safe to call from multiple tasks. It doesn't block them, only suspends so the system as
/// a whole can make progress
public struct AsyncSemaphore: Sendable {
    @usableFromInline
    internal let _semaphore: _async_semaphore
    
    public init(count: Int = 0) {
        _semaphore = _async_semaphore(count: count)
    }
    
    /// Waits for or decrements the semaphore. In the case of waiting, this function
    /// suspends the current task and doesn't block the underlying thread.
    public func wait() async {
        await _semaphore.wait()
    }
    
    /// Wait for a certain amount of nanoseconds for the semaphore, or possibly decrement it.
    /// In the case of waiting, this function suspends the current task and doesn't block the
    /// underlying thread.
    public func wait(for nanoseconds: UInt64) async -> Bool {
        await _semaphore.wait(for: nanoseconds)
    }
    
    /// Signal the semaphore.
    public func signal(count: Int = 1) {
        _semaphore.signal(count: count)
    }
}

extension AsyncSemaphore {
    @usableFromInline
    internal final class _async_semaphore: @unchecked Sendable {
        var count: Int
        var waitingTasks = Deque<(id: Int, continuation: UnsafeContinuation<Bool,Never>)>()
        var id = 0
        let lock = Lock()
        
        init(count: Int) {
            self.count = count
        }
        
        final func wait() async {
            lock.lock()
            count -= 1
            if count >= 0 {
                lock.unlock()
                return
            }
            self.id += 1
            let id = self.id
            let _ = await withUnsafeContinuation { (cont: UnsafeContinuation<Bool, Never>) in
                waitingTasks.append((id, cont))
                lock.unlock()
            }
        }
        
        final func wait(for nanoseconds: UInt64) async -> Bool {
            lock.lock()
            count -= 1
            if count >= 0 {
                lock.unlock()
                return true
            }
            self.id += 1
            let id = self.id
            return  await withUnsafeContinuation { (cont: UnsafeContinuation<Bool, Never>) in
                waitingTasks.append((id, cont))
                lock.unlock()
                
                Task {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    lock.withLock {
                        waitingTasks.removeAll { (identifier, cont) in
                            if id == identifier {
                                cont.resume(returning: false)
                                self.count += 1
                                return true
                            }
                            return false
                        }
                    }
                }
            }
        }
        
        final func signal(count: Int = 1) {
            assert(count > 0)
            lock.withLock {
                self.count += count
                for _ in 0..<count {
                    if let continuation = waitingTasks.popFirst()?.continuation {
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }
}
