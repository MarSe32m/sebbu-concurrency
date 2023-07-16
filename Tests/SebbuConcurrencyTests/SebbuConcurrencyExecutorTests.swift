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
        Task { @MainActor in
            let task1 = Task.detached {
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
            let task2 = Task.detached {
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
            let task3 = Task.detached {
                await withUnsafeContinuation { continuation in
                    Task.detached {
                        continuation.resume()
                    }
                }
            }
            let task1Main = Task { @MainActor in
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
            let task2Main = Task { @MainActor in
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
            let task3Main = Task { @MainActor in
                await withUnsafeContinuation { continuation in
                    Task.detached {
                        continuation.resume()
                    }
                }
            }
            let _ = await (task1.value, task2.value, task3.value, task1Main.value, task2Main.value, task3Main.value)
            MultiThreadedGlobalExecutor.shared.reset()
        }
    }
    
    func testSingleThreadedGlobalExecutor() {
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
    
    func testBasicSerialExecutor() async {
        actor ExecutorActor {
            static let basicSerialExecutor = BasicSerialExecutor.withDetachedThread()
            nonisolated var unownedExecutor: UnownedSerialExecutor {
                ExecutorActor.basicSerialExecutor.asUnownedSerialExecutor()
            }
            
            var state: Int = 0
            
            func increment() {
                state += 1
            }
            
        }
        let exec1 = ExecutorActor()
        let exec2 = ExecutorActor()
        await exec1.increment()
        await exec2.increment()
        let exec1State = await exec1.state
        let exec2State = await exec2.state
        XCTAssertEqual(exec1State, 1)
        XCTAssertEqual(exec2State, 1)
    }
}
