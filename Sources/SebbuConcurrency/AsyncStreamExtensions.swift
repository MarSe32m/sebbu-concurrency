//
//  AsyncStreamExtensions.swift
//  
//
//  Created by Sebastian Toivonen on 6.1.2022.
//

// Standard library provides an implementation starting from 5.9
#if swift(<5.9)
extension AsyncStream {
    public static func makeStream(of elementType: Element.Type = Element.self, bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
        var continuation: AsyncStream<Element>.Continuation!
        let stream = AsyncStream<Element>(bufferingPolicy: limit) { continuation = $0 }
        return (stream: stream, continuation: continuation)
    }
}
#endif
