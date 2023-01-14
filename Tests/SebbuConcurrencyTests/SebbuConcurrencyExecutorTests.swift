//
//  SebbuConcurrencyExecutorTests.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//
import XCTest
import SebbuConcurrency
import Foundation
import SebbuTSDS

final class SebbuConcurrencyExecutorTests: XCTestCase {
    private func executorTests() {
        //TODO: Test MainActor enqueueing as well...
        Task {
            let task1 = Task {
                let value = await withTaskGroup(of: Int.self) { group in
                    for i in 0..<10_000 {
                        group.addTask {
                            try! await Task.sleep(nanoseconds: 1_000_000_000)
                            await Task.yield()
                            return i + 1
                        }
                    }
                    return await group.reduce(0, +)
                }
                XCTAssertEqual(value, (0..<10_000).reduce(0, +) + 10_000)
            }
            let task2 = Task {
                let tasks = (0..<10_000).map { i in
                    Task.detached {
                        return i * i
                    }
                }
                var sum = 0
                for (i, task) in tasks.enumerated() {
                    sum += i * i
                    sum -= await task.value
                }
                XCTAssertEqual(sum, 0)
            }
            let task3 = Task {
                await withUnsafeContinuation { continuation in
                    Task.detached {
                        continuation.resume()
                    }
                }
            }
            let _ = await (task1.value, task2.value, task3.value)
            MultiThreadedGlobalExecutor.shared.reset()
        }
    }
    
    func testSingleThreadedExecutor() {
        SingleThreadedGlobalExecutor.shared.setup()
        defer { SingleThreadedGlobalExecutor.shared.reset() }
        executorTests()
        SingleThreadedGlobalExecutor.shared.run()
    }
    
    
    func testMultiThreadedGlobalExecutor() {
        MultiThreadedGlobalExecutor.shared.setup()
        defer { MultiThreadedGlobalExecutor.shared.reset() }
        executorTests()
        MultiThreadedGlobalExecutor.shared.run()
    }
}
