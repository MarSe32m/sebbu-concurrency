import XCTest
import SebbuConcurrency
import Foundation
import SebbuTSDS

final class SebbuConcurrencyTests: XCTestCase {
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
        XCTAssertEqual(counter, 100)
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
        //FIXME: For some reason Windows crashes with more than 100 written items...
        #if !os(Windows)
        let writeCount = 100000
        #else
        let writeCount = 100
        #endif
        let reader = Task.detached {
            return await channel.reduce(0, +)
        }
        for _ in 0..<writeCount {
            channel.send(1)
        }
        channel.close()
        let readValue = await reader.value
        XCTAssertEqual(writeCount, readValue)
    }
    
    func testChannelMultipleWritersMultipleReaders() async throws {
        //FIXME: For some reason Windows crashes with more than 100 written items per writer...
        #if !os(Windows)
        let writeCount = 100000
        #else
        let writeCount = 100
        #endif
        
        for writerCount in 1...10 {
            for readerCount in 1...10 {
                let channel = AsyncChannel<Int>()
                let readers = (0..<readerCount).map {_ in
                    Task<Int, Never> {
                        return await channel.reduce(0, +)
                    }
                }
                let writers = (0..<writerCount).map {_ in
                    Task<Void, Never> {
                        for _ in 0..<writeCount {
                            channel.send(1)
                        }
                    }
                }
                for writer in writers {
                    let _ = await writer.value
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
    
    func testUnboundedBufferingStrategy() async throws {
        let channel = AsyncChannel<Int>(bufferingStrategy: .unbounded)
        for _ in 0..<1_00 {
            let result = channel.send(1)
            guard case .enqueued(let remainingCapacity) = result else {
                XCTFail("The send result wasn't 'enqueued'")
                return
            }
            XCTAssertEqual(remainingCapacity, Int.max)
        }
        channel.close()
        let result = channel.send(1)
        switch result {
        case .closed:
            return
        default:
            XCTFail("The send result should have been 'closed'.")
        }
    }
    
    func testDropOldestBufferingStrategy() async throws {
        let maximumCapacity = Int.random(in: 50...100)
        let channel = AsyncChannel<Int>(bufferingStrategy: .dropOldest(maxCapacity: maximumCapacity))
        for i in 1...maximumCapacity {
            let result = channel.send(i)
            guard case .enqueued(let remainingCapacity) = result else {
                XCTFail("The send result wasn't 'enqueued'")
                return
            }
            XCTAssertEqual(remainingCapacity, maximumCapacity - i)
        }
        
        for i in 1...maximumCapacity {
            let resultOnFull = channel.send(i)
            switch resultOnFull {
            case .dropped(let value):
                XCTAssertEqual(value, i)
            default:
                XCTFail("The send result wasn't 'dropped'")
            }
        }
        
        for i in 1...maximumCapacity {
            guard let value = channel.tryReceive() else {
                XCTFail("Couldn't receive item...")
                break
            }
            XCTAssertEqual(i, value)
        }
        
        channel.close()
        let result = channel.send(1)
        switch result {
        case .closed:
            return
        default:
            XCTFail("The send result should have been 'closed'.")
        }
    }
    
    func testDropNewestBufferingStrategy() async throws {
        let maximumCapacity = Int.random(in: 50...100)
        let channel = AsyncChannel<Int>(bufferingStrategy: .dropNewest(maxCapacity: maximumCapacity))
        for i in 1...maximumCapacity {
            let result = channel.send(i)
            guard case .enqueued(let remainingCapacity) = result else {
                XCTFail("The send result wasn't 'enqueued'")
                return
            }
            XCTAssertEqual(remainingCapacity, maximumCapacity - i)
        }
        
        for _ in 1...maximumCapacity {
            let item = Int.random(in: 0...10000)
            let resultOnFull = channel.send(item)
            switch resultOnFull {
            case .dropped(let value):
                XCTAssertEqual(value, item)
            default:
                XCTFail("The send result wasn't 'dropped'")
            }
        }
        
        for i in 1...maximumCapacity {
            guard let value = channel.tryReceive() else {
                XCTFail("Couldn't receive item...")
                break
            }
            XCTAssertEqual(i, value)
        }
        
        channel.close()
        let result = channel.send(1)
        switch result {
        case .closed:
            return
        default:
            XCTFail("The send result should have been 'closed'.")
        }
    }
    
    func testAsyncStreamWithPipe() async throws {
        let (consumer, producer) = AsyncStream<Int>.pipe()
        let producerTask = Task<Int, Never> {
            var sum = 0
            for _ in 0..<10000 {
                let value = Int.random(in: -10...10)
                sum += value
                producer.yield(value)
            }
            producer.finish()
            return sum
        }
        var finalSum = 0
        for await value in consumer {
            finalSum += value
        }
        let producerSum = await producerTask.value
        XCTAssertEqual(finalSum, producerSum)
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
    
    func testThreadPool_runAsync() async {
        actor Counter {
            var value: Int = 0
            init() {}
            func increment(by: Int = 1) { value += by }
            func fetch() -> Int { value }
        }
        #if canImport(Atomics)
        let counter = Counter()
        let threadPool = ThreadPool(numberOfThreads: 8)
        let iterations = 100000
        threadPool.start()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    for i in 0..<iterations {
                        await counter.increment(by: threadPool.runAsync {
                            return i
                        })
                    }
                }
            }
        }
        threadPool.stop()
        let finalCount = await counter.fetch()
        XCTAssertEqual(10 * (0..<iterations).reduce(0, +), finalCount)
        #endif
    }
}
