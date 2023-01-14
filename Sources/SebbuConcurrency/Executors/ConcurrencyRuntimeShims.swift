//
//  ConcurrencyRuntimeShims.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

@_exported import ConcurrencyRuntimeC

@_silgen_name("swift_task_getCurrentExecutor")
public func _getCurrentExecutor() -> UnownedSerialExecutor
