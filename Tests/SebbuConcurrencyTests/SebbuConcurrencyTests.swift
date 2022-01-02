import XCTest
@testable import SebbuConcurrency
import Foundation

final class SebbuConcurrencyTests: XCTestCase {
    func testRepeatingTimer() {
        let repeatingTimer = RepeatingTimer(delta: 1 / 100.0, queue: .main)
        var counter = 0
        repeatingTimer.eventHandler = {
            counter += 1
        }
        repeatingTimer.resume()
        for _ in 0..<100 {
            RunLoop.main.run(mode: .default, before: .distantFuture)
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
        let channel = Channel<Int>()
        let writeCount = 100000
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
    
    func testChannel10Writers10Readers() async throws {
        let channel = Channel<Int>()
        let writeCount = 100000
        let writerCount = 10
        let readers = (0..<10).map {_ in
            Task<Int, Never> {
                return await channel.reduce(0, +)
            }
        }
        let writers = (0..<10).map {_ in
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
    }
}
