//
//  ConcurrencyRuntimeC.h
//  
//
//  Created by Sebastian Toivonen on 13.1.2023.
//
#include <stdint.h>

#if !defined(__has_feature)
#define __has_feature(x) 0
#endif

#if !defined(__has_attribute)
#define __has_attribute(x) 0
#endif

#if !defined(__has_builtin)
#define __has_builtin(builtin) 0
#endif

#if !defined(__has_cpp_attribute)
#define __has_cpp_attribute(attribute) 0
#endif

// TODO: These macro definitions are duplicated in BridgedSwiftObject.h. Move
// them to a single file if we find a location that both Visibility.h and
// BridgedSwiftObject.h can import.
#if __has_feature(nullability)
// Provide macros to temporarily suppress warning about the use of
// _Nullable and _Nonnull.
# define SWIFT_BEGIN_NULLABILITY_ANNOTATIONS                        \
  _Pragma("clang diagnostic push")                                  \
  _Pragma("clang diagnostic ignored \"-Wnullability-extension\"")
# define SWIFT_END_NULLABILITY_ANNOTATIONS                          \
  _Pragma("clang diagnostic pop")

#else
// #define _Nullable and _Nonnull to nothing if we're not being built
// with a compiler that supports them.
# define _Nullable
# define _Nonnull
# define SWIFT_BEGIN_NULLABILITY_ANNOTATIONS
# define SWIFT_END_NULLABILITY_ANNOTATIONS
#endif

#define SWIFT_MACRO_CONCAT(A, B) A ## B
#define SWIFT_MACRO_IF_0(IF_TRUE, IF_FALSE) IF_FALSE
#define SWIFT_MACRO_IF_1(IF_TRUE, IF_FALSE) IF_TRUE
#define SWIFT_MACRO_IF(COND, IF_TRUE, IF_FALSE) \
  SWIFT_MACRO_CONCAT(SWIFT_MACRO_IF_, COND)(IF_TRUE, IF_FALSE)

// Define the appropriate attributes for sharing symbols across
// image (executable / shared-library) boundaries.
//
// SWIFT_ATTRIBUTE_FOR_EXPORTS will be placed on declarations that
// are known to be exported from the current image.  Typically, they
// are placed on header declarations and then inherited by the actual
// definitions.
//
// SWIFT_ATTRIBUTE_FOR_IMPORTS will be placed on declarations that
// are known to be exported from a different image.  This never
// includes a definition.
//
// Getting the right attribute on a declaratioon can be pretty awkward,
// but it's necessary under the C translation model.  All of this
// ceremony is familiar to Windows programmers; C/C++ programmers
// everywhere else usually don't bother, but since we have to get it
// right for Windows, we have everything set up to get it right on
// other targets as well, and doing so lets the compiler use more
// efficient symbol access patterns.
#if defined(__MACH__) || defined(__wasi__)

// On Mach-O and WebAssembly, we use non-hidden visibility.  We just use
// default visibility on both imports and exports, both because these
// targets don't support protected visibility but because they don't
// need it: symbols are not interposable outside the current image
// by default.
# define SWIFT_ATTRIBUTE_FOR_EXPORTS __attribute__((__visibility__("default")))
# define SWIFT_ATTRIBUTE_FOR_IMPORTS __attribute__((__visibility__("default")))

#elif defined(__ELF__)

// On ELF, we use non-hidden visibility.  For exports, we must use
// protected visibility to tell the compiler and linker that the symbols
// can't be interposed outside the current image.  For imports, we must
// use default visibility because protected visibility guarantees that
// the symbol is defined in the current library, which isn't true for
// an import.
//
// The compiler does assume that the runtime and standard library can
// refer to each other's symbols as DSO-local, so it's important that
// we get this right or we can get linker errors.
# define SWIFT_ATTRIBUTE_FOR_EXPORTS __attribute__((__visibility__("protected")))
# define SWIFT_ATTRIBUTE_FOR_IMPORTS __attribute__((__visibility__("default")))

#elif defined(__CYGWIN__)

// For now, we ignore all this on Cygwin.
# define SWIFT_ATTRIBUTE_FOR_EXPORTS
# define SWIFT_ATTRIBUTE_FOR_IMPORTS

// FIXME: this #else should be some sort of #elif Windows
#else // !__MACH__ && !__ELF__

// On PE/COFF, we use dllimport and dllexport.
# define SWIFT_ATTRIBUTE_FOR_EXPORTS __declspec(dllexport)
# define SWIFT_ATTRIBUTE_FOR_IMPORTS __declspec(dllimport)

#endif

// CMake conventionally passes -DlibraryName_EXPORTS when building
// code that goes into libraryName.  This isn't the best macro name,
// but it's conventional.  We do have to pass it explicitly in a few
// places in the build system for a variety of reasons.
//
// Unfortunately, defined(D) is a special function you can use in
// preprocessor conditions, not a macro you can use anywhere, so we
// need to manually check for all the libraries we know about so that
// we can use them in our condition below.s
#if defined(swiftCore_EXPORTS)
#define SWIFT_IMAGE_EXPORTS_swiftCore 1
#else
#define SWIFT_IMAGE_EXPORTS_swiftCore 0
#endif
#if defined(swift_Concurrency_EXPORTS)
#define SWIFT_IMAGE_EXPORTS_swift_Concurrency 1
#else
#define SWIFT_IMAGE_EXPORTS_swift_Concurrency 0
#endif
#if defined(swift_Distributed_EXPORTS)
#define SWIFT_IMAGE_EXPORTS_swift_Distributed 1
#else
#define SWIFT_IMAGE_EXPORTS_swift_Distributed 0
#endif
#if defined(swift_Differentiation_EXPORTS)
#define SWIFT_IMAGE_EXPORTS_swift_Differentiation 1
#else
#define SWIFT_IMAGE_EXPORTS_swift_Differentiation 0
#endif

#define SWIFT_EXPORT_FROM_ATTRIBUTE(LIBRARY)                          \
  SWIFT_MACRO_IF(SWIFT_IMAGE_EXPORTS_##LIBRARY,                       \
                 SWIFT_ATTRIBUTE_FOR_EXPORTS,                         \
                 SWIFT_ATTRIBUTE_FOR_IMPORTS)

// SWIFT_EXPORT_FROM(LIBRARY) declares something to be a C-linkage
// entity exported by the given library.
//
// SWIFT_RUNTIME_EXPORT is just SWIFT_EXPORT_FROM(swiftCore).
//
// TODO: use this in shims headers in overlays.
#if defined(__cplusplus)
#define SWIFT_EXPORT_FROM(LIBRARY) extern "C" SWIFT_EXPORT_FROM_ATTRIBUTE(LIBRARY)
#define SWIFT_EXPORT extern "C"
#else
#define SWIFT_EXPORT extern
#define SWIFT_EXPORT_FROM(LIBRARY) SWIFT_EXPORT_FROM_ATTRIBUTE(LIBRARY)
#endif
#define SWIFT_RUNTIME_EXPORT SWIFT_EXPORT_FROM(swiftCore)

// Define mappings for calling conventions.

// Annotation for specifying a calling convention of
// a runtime function. It should be used with declarations
// of runtime functions like this:
// void runtime_function_name() SWIFT_CC(swift)
#define SWIFT_CC(CC) SWIFT_CC_##CC

// SWIFT_CC(c) is the C calling convention.
#define SWIFT_CC_c

// SWIFT_CC(swift) is the Swift calling convention.
// FIXME: the next comment is false.
// Functions outside the stdlib or runtime that include this file may be built
// with a compiler that doesn't support swiftcall; don't define these macros
// in that case so any incorrect usage is caught.
#if __has_attribute(swiftcall)
#define SWIFT_CC_swift __attribute__((swiftcall))
#define SWIFT_CONTEXT __attribute__((swift_context))
#define SWIFT_ERROR_RESULT __attribute__((swift_error_result))
#define SWIFT_INDIRECT_RESULT __attribute__((swift_indirect_result))
#else
#define SWIFT_CC_swift
#define SWIFT_CONTEXT
#define SWIFT_ERROR_RESULT
#define SWIFT_INDIRECT_RESULT
#endif

#if !defined(__swift__) && __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#ifndef __ptrauth_objc_isa_pointer
#define __ptrauth_objc_isa_pointer
#endif

#include <inttypes.h>
#include <stdbool.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef SWIFT_CC
#define SWIFT_CC(x)     SWIFT_CC_##x
#define SWIFT_CC_swift  __attribute__((swiftcall))
#endif

#ifndef SWIFT_RUNTIME_ATTRIBUTE_NORETURN
#define SWIFT_RUNTIME_ATTRIBUTE_NORETURN __attribute__((noreturn))
#endif

// -- C versions of types executors might need ---------------------------------

/// Represents a Swift type
typedef struct SwiftHeapMetadata SwiftHeapMetadata;

/// Jobs have flags, which currently encode a kind and a priority
typedef uint32_t SwiftJobFlags;

typedef size_t SwiftJobKind;
enum {
  SwiftTaskJobKind = 0,

  // Job kinds >= 192 are private to the implementation
  SwiftFirstReservedJobKind = 192,
};

typedef size_t SwiftJobPriority;
enum {
  SwiftUserInteractiveJobPriority = 0x21, /* UI */
  SwiftUserInitiatedJobPriority   = 0x19, /* IN */
  SwiftDefaultJobPriority         = 0x15, /* DEF */
  SwiftUtilityJobPriority         = 0x11, /* UT */
  SwiftBackgroundJobPriority      = 0x09, /* BG */
  SwiftUnspecifiedJobPriority     = 0x00, /* UN */
};

enum { SwiftJobPriorityBucketCount = 5 };

static inline int swift_priority_getBucketIndex(SwiftJobPriority priority) {
  if (priority > SwiftUserInitiatedJobPriority)
    return 0;
  else if (priority > SwiftDefaultJobPriority)
    return 1;
  else if (priority > SwiftUtilityJobPriority)
    return 2;
  else if (priority > SwiftBackgroundJobPriority)
    return 3;
  else
    return 4;
}

/// Used by the Concurrency runtime to represent a job.  The `schedulerPrivate`
/// field may be freely used by the executor implementation.
typedef struct {
  SwiftHeapMetadata const *_Nonnull __ptrauth_objc_isa_pointer metadata;
  uintptr_t refCounts;
  void *_Nullable schedulerPrivate[2];
  SwiftJobFlags flags;
} __attribute__((aligned(2 * sizeof(void *)))) SwiftJob;


typedef struct SwiftJob* SwiftJobRef;
//typedef struct _Job* JobRef;
typedef struct _Executor ExecutorRef;

//typedef __attribute__((aligned(2 * alignof(void *)))) struct {
//    void *_Nonnull Metadata;
//    int32_t RefCounts;
//    void *_Nullable SchedulerPrivate[2];
//    uint32_t Flags;
//} SwiftJob;


/// A hook to take over global enqueuing.
typedef SWIFT_CC(swift) void (*swift_task_enqueueGlobal_original)(SwiftJobRef _Nonnull job);
__attribute__((swift_attr("nonisolated(unsafe)")))
SWIFT_EXPORT_FROM(swift_Concurrency)
SWIFT_CC(swift) void (* _Nullable swift_task_enqueueGlobal_hook)(
    SwiftJobRef _Nonnull job, swift_task_enqueueGlobal_original _Nonnull original);

/// A hook to take over global enqueuing with delay.
typedef SWIFT_CC(swift) void (*swift_task_enqueueGlobalWithDelay_original)(
    unsigned long long delay, SwiftJobRef _Nonnull job);
__attribute__((swift_attr("nonisolated(unsafe)")))
SWIFT_EXPORT_FROM(swift_Concurrency)
SWIFT_CC(swift) void (* _Nullable swift_task_enqueueGlobalWithDelay_hook)(
    unsigned long long delay, SwiftJobRef _Nonnull job,
    swift_task_enqueueGlobalWithDelay_original _Nonnull original);

typedef SWIFT_CC(swift) void (*swift_task_enqueueGlobalWithDeadline_original)(
    long long sec,
    long long nsec,
    long long tsec,
    long long tnsec,
    int clock, SwiftJobRef _Nonnull job);
__attribute__((swift_attr("nonisolated(unsafe)")))
SWIFT_EXPORT_FROM(swift_Concurrency)
SWIFT_CC(swift) void (* _Nullable swift_task_enqueueGlobalWithDeadline_hook)(
    long long sec,
    long long nsec,
    long long tsec,
    long long tnsec,
    int clock, SwiftJobRef _Nonnull job,
    swift_task_enqueueGlobalWithDeadline_original _Nonnull original);

/// A hook to take over main executor enqueueing.
typedef SWIFT_CC(swift) void (*swift_task_enqueueMainExecutor_original)(SwiftJobRef _Nonnull job);
__attribute__((swift_attr("nonisolated(unsafe)")))
SWIFT_EXPORT_FROM(swift_Concurrency)
SWIFT_CC(swift) void (* _Nullable swift_task_enqueueMainExecutor_hook)(
    SwiftJobRef _Nonnull job, swift_task_enqueueMainExecutor_original _Nonnull original);

/// A hook to take over the main queue draining
typedef SWIFT_CC(swift) void (*swift_task_asyncMainDrainQueue_original)();
typedef SWIFT_CC(swift) void (*swift_task_asyncMainDrainQueue_override)(
 swift_task_asyncMainDrainQueue_original _Nonnull original);
__attribute__((swift_attr("nonisolated(unsafe)")))
SWIFT_EXPORT_FROM(swift_Concurrency)
SWIFT_CC(swift) void (* _Nullable swift_task_asyncMainDrainQueue_hook)(
 swift_task_asyncMainDrainQueue_original _Nonnull original,
 swift_task_asyncMainDrainQueue_override _Nonnull compatOverride);

/// Return the current thread's active executor reference.
//SWIFT_EXPORT_FROM(swift_Concurrency) SWIFT_CC(swift)
//ExecutorRef swift_task_getCurrentExecutor(void);
