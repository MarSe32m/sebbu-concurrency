//
//  ConcurrencyRuntimeShims.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

@_exported import ConcurrencyRuntimeC

@_silgen_name("swift_task_getCurrentExecutor")
@inlinable
public func _getCurrentExecutor() -> UnownedSerialExecutor

@_silgen_name("swift_task_enqueueMainExecutor")
@inlinable
public func _enqueueMainExecutor(_ job: UnownedJob) -> Void
