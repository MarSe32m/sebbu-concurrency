//
//  AsyncStreamExtensions.swift
//  
//
//  Created by Sebastian Toivonen on 6.1.2022.
//

extension AsyncStream {
    public static func pipe(_ bufferingPolicy: Continuation.BufferingPolicy = .unbounded) -> (consumer: AsyncStream, producer: Continuation) {
        var continuation: Continuation!
        let stream = self.init(bufferingPolicy: bufferingPolicy) { _continuation in
            continuation = _continuation
        }
        return (stream, continuation)
    }
}
