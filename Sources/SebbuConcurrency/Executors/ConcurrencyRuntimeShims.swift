//
//  ConcurrencyRuntimeShims.swift
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//

import ConcurrencyRuntimeC

@_silgen_name("swift_job_run")
@usableFromInline
internal func _swiftJobRun(_ job: UnownedJob,_ executor: UnownedSerialExecutor) -> ()

@_silgen_name("swift_task_getCurrentExecutor")
@usableFromInline
internal func _getCurrentExecutor() -> UnownedSerialExecutor
