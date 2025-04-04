import XCTest
import SebbuConcurrency
import Foundation
import SebbuTSDS

final class SebbuConcurrencyTests: XCTestCase, @unchecked Sendable {
    
    func testParallelMap() {
        let range = (0..<1_000_000)
        let array = Array(range)
        let mapped = range.map { $0 * $0 }
        
        let rangeParallelMapped1 = range.parallelMap { $0 * $0 }
        let rangeParallelMapped2 = range.parallelMap(parallelism: 2) { $0 * $0 }
        let rangeParallelMapped3 = range.parallelMap(blockSize: .random(in: 2...10)) { $0 * $0 }
        let rangeParallelMapped4 = range.parallelMap(parallelism: 3, blockSize: .random(in: 2...10)) { $0 * $0 }
        XCTAssertEqual(mapped, rangeParallelMapped1)
        XCTAssertEqual(mapped, rangeParallelMapped2)
        XCTAssertEqual(mapped, rangeParallelMapped3)
        XCTAssertEqual(mapped, rangeParallelMapped4)
        
        let arrayParallelMapped1 = array.parallelMap { $0 * $0 }
        let arrayParallelMapped2 = array.parallelMap(parallelism: 2) { $0 * $0 }
        XCTAssertEqual(mapped, arrayParallelMapped1)
        XCTAssertEqual(mapped, arrayParallelMapped2)
        
        let slice = array[0..<1_000]
        let sliceParallelMapped1 = slice.parallelMap { $0 * $0 }
        let sliceParallelMapped2 = slice.parallelMap(parallelism: 2) { $0 * $0 }
        XCTAssertEqual(slice.map { $0 * $0 }, sliceParallelMapped1)
        XCTAssertEqual(slice.map { $0 * $0 }, sliceParallelMapped2)
        
    }
    
    func testRateLimiter() async throws {
        let rateLimiter = RateLimiter(permits: 5000, perInterval: .seconds(1), maxPermits: 30000)
        let start = Date()
        var remainingCount = 30000
        while remainingCount > 0 {
            let nextPermitCount = Int.random(in: 2...30000)
            remainingCount -= nextPermitCount
            do {
                try rateLimiter.acquire(permits: nextPermitCount)
            } catch {
                remainingCount += nextPermitCount
            }
        }
        let end = Date()
        XCTAssertGreaterThanOrEqual(start.distance(to: end), 5)
        try await Task.sleep(for: .seconds(1.1))
        XCTAssertNoThrow(try rateLimiter.acquire(permits: 5000))
    }
    
    func testRepeatingTimer() {
        let repeatingTimer = RepeatingTimer(delta: 1 / 100.0, queue: .main)
        var counter = 0
        repeatingTimer.eventHandler = {
            counter += 1
        }
        repeatingTimer.resume()
        for _ in 0..<100 {
            let _ = RunLoop.main.run(mode: .default, before: .distantFuture)
        }
        XCTAssert(counter == 99 || counter == 100)
    }
    
    func testTurnScheduler() async {
        let scheduler = TurnScheduler(amount: 10, interval: 1)
        let start = Date()
        for _ in 0..<10 {
            await scheduler.wait()
        }
        let end = Date()
        XCTAssert(start.distance(to: end) >= 0.9)
    }
    
    func testChannelOneWriter() async throws {
        let channel = AsyncChannel<Int>()
        let writeCount = 100000
        let reader = Task.detached {
            return await channel.reduce(0, +)
        }
        for _ in 0..<writeCount {
            await channel.send(1)
        }
        channel.close()
        let readValue = await reader.value
        XCTAssertEqual(writeCount, readValue)
    }
    
    func testThrowingChannelOneWriter() async throws {
        let channel = AsyncThrowingChannel<Int>()
        let writeCount = 100000
        let reader = Task.detached {
            return await channel.reduce(0, +)
        }
        for _ in 0..<writeCount {
            try await channel.send(1)
        }
        channel.close()
        let readValue = await reader.value
        XCTAssertEqual(writeCount, readValue)
    }
    
    func testChannelMultipleWritersMultipleReaders() async throws {
        let writeCount = 1000
        for writerCount in 1...10 {
            for readerCount in 1...10 {
                let channel = AsyncChannel<Int>()
                let readers = (0..<readerCount).map {_ in
                    Task<Int, Never> {
                        return await channel.reduce(0, +)
                    }
                }
                let writers = (0..<writerCount).map {_ in
                    Task<Void, Error> {
                        for _ in 0..<writeCount {
                            await channel.send(1)
                        }
                    }
                }
                for writer in writers {
                    let _ = try await writer.value
                }
                channel.close()
                var totalSum = 0
                for reader in readers {
                    totalSum += await reader.value
                }
                XCTAssertEqual(writerCount * writeCount, totalSum)
                XCTAssertNil(channel.tryReceive())
            }
        }
        
    }
    
    func testThrowingChannelMultipleWritersMultipleReaders() async throws {
        let writeCount = 1000
        for writerCount in 1...10 {
            for readerCount in 1...10 {
                let channel = AsyncThrowingChannel<Int>()
                let readers = (0..<readerCount).map {_ in
                    Task<Int, Never> {
                        return await channel.reduce(0, +)
                    }
                }
                let writers = (0..<writerCount).map {_ in
                    Task<Void, Error> {
                        for _ in 0..<writeCount {
                            try await channel.send(1)
                        }
                    }
                }
                for writer in writers {
                    let _ = try await writer.value
                }
                channel.close()
                var totalSum = 0
                for reader in readers {
                    totalSum += await reader.value
                }
                XCTAssertEqual(writerCount * writeCount, totalSum)
                XCTAssertNil(channel.tryReceive())
            }
        }
        
    }
    
    func testThrowingChannelUnboundedBufferingStrategy() async throws {
        let channel = AsyncThrowingChannel<Int>(bufferingStrategy: .unbounded)
        for _ in 0..<1_00 {
            try await channel.send(1)
        }
        channel.close()
        do {
            try await channel.send(1)
        } catch {
            XCTAssertTrue(error is AsyncThrowingChannel<Int>.SendError)
        }
        XCTAssertFalse(channel.trySend(1))
    }
    
    func testThrowingChannelBoundedBufferingStrategy() async throws {
        let channel = AsyncThrowingChannel<Int>(bufferingStrategy: .bounded(50))
        for _ in 0..<50 {
            XCTAssertTrue(channel.trySend(1))
        }
        for _ in 0..<50 {
            XCTAssertFalse(channel.trySend(1))
        }
        channel.close()
        do {
            try await channel.send(1)
        } catch {
            XCTAssertTrue(error is AsyncThrowingChannel<Int>.SendError)
        }
        XCTAssertFalse(channel.trySend(1))
    }
    
    func testAsyncSemaphore() async throws {
        let semaphore = AsyncSemaphore()
        var aquiredSemaphore = await semaphore.wait(for: 1_000_000)
        XCTAssertFalse(aquiredSemaphore)
        let tasks = (0..<10).map { _ in
            Task<Void, Never> {
                for _ in 0..<1000 {
                    await semaphore.wait()
                }
            }
        }
        for _ in 0..<10 * 1000 {
            semaphore.signal()
        }
        for task in tasks {
            await task.value
        }
        aquiredSemaphore = await semaphore.wait(for: 1_000_000)
        XCTAssertFalse(aquiredSemaphore)
        
        semaphore.signal()
        aquiredSemaphore = await semaphore.wait(for: 1_000_000)
        XCTAssertTrue(aquiredSemaphore)
    }
    
    func testAsyncSemaphoreCancellation() async throws {
        let semaphore = AsyncSemaphore()
        var testTask = Task {
            try await semaphore.waitUnlessCancelled()
            return true
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        testTask.cancel()
        do {
            let _ = try await testTask.value
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        
        testTask = Task {
            try await semaphore.waitUnlessCancelled(for: 1_000_000_000)
        }
        let didAquireSemaphore = try await testTask.value
        XCTAssertFalse(didAquireSemaphore)
        
        testTask = Task {
            try await semaphore.waitUnlessCancelled(for: 10_000_000_000)
        }
        testTask.cancel()
        do {
            let _ = try await testTask.value
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        
        testTask = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            try await semaphore.waitUnlessCancelled()
            return true
        }
        do {
            let _ = try await testTask.value
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
    
    func testTaskGroupExtensions() async throws {
        // Run 10 tasks at a time        
        let semaphore = AsyncSemaphore(count: 10)
        let result = await withTaskGroup(of: Int.self, returning: Int.self, body: { group in
            for i in 0..<10000 {
                await group.addTask(with: semaphore) {
                    i
                }
            }
            for i in 0..<10000 {
                await group.addTask(with: semaphore) {
                    -i
                }
            }
            return await group.reduce(0, +)
        })
        XCTAssertEqual(result, 0)
    }
    
    func testManualTask() async throws {
        do {
            let task = ManualTask {
                return 1
            }
            task.start()
            let value1 = await task.value
            XCTAssertEqual(1, value1)
        }
        
        do {
            var tasks = [ManualTask<Int, Never>]()
            for i in 0..<100 {
                tasks.append(ManualTask {
                    return i
                })
            }
            for (i, task) in tasks.enumerated() {
                for _ in 0..<100 {
                    Task.detached {
                        let value = await task.value
                        XCTAssertEqual(i, value)
                    }
                }
            }
            tasks.forEach { $0.start() }
        }
        
        do {
            var tasks = [ManualTask<Bool, Never>]()
            for _ in 0..<100 {
                tasks.append(ManualTask {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        return true
                    }
                    return false
                })
            }
            for task in tasks {
                for _ in 0..<100 {
                    Task.detached {
                        let value = await task.value
                        XCTAssertTrue(value)
                    }
                }
            }
            tasks.forEach {
                $0.cancel()
                $0.start()
            }
            for task in tasks {
                let isCancelled = await task.value
                XCTAssertTrue(isCancelled)
            }
        }
    }
}
