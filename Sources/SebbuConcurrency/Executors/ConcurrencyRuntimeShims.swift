//
//  ConcurrencyRuntimeShims.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

@_exported import ConcurrencyRuntimeC

@_silgen_name("swift_task_enqueueMainExecutor")
@inlinable
public func _enqueueMainExecutor(_ job: UnownedJob) -> Void

@_silgen_name("swift_task_enqueueGlobal")
@inlinable
public func _enqueueGlobal(_ job: UnownedJob) -> Void

@_silgen_name("swift_get_time")
@inlinable
public func _getTime(_ seconds: UnsafeMutablePointer<Int64>, _ nanoseconds: UnsafeMutablePointer<Int64>, _ clock_id: Int32)