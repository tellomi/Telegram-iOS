#import "GCDAsyncSocketCFSocketRelease.h"

#import <fcntl.h>
#import <mach/mach.h>
#import <netinet/in.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <sys/socket.h>
#import <unistd.h>

#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

static _Atomic int gDeferredCFSocketReleaseCount = 0;
static dispatch_queue_t gDeferredCFSocketReleaseQueue;

static BOOL TellomiBytesReadable(const void *address, size_t size) {
    if (address == NULL || size == 0 || size > 4096) {
        return NO;
    }
    char buffer[4096];
    vm_size_t copied = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(), (vm_address_t)address, (vm_size_t)size, (vm_address_t)buffer, &copied);
    return result == KERN_SUCCESS && copied == size;
}

static BOOL TellomiFunctionIs(void *function, void *expected) {
    if (function == NULL || expected == NULL) {
        return NO;
    }
#if __has_feature(ptrauth_calls)
    void *got = ptrauth_strip(function, ptrauth_key_function_pointer);
    void *want = ptrauth_strip(expected, ptrauth_key_function_pointer);
    return got == want;
#else
    return function == expected;
#endif
}

static BOOL TellomiReleaseIsCFRelease(void (*release)(const void *)) {
    return TellomiFunctionIs((void *)release, (void *)CFRelease);
}

// CFSocketCreate owns the descriptors it allocates. CFRelease is not a
// close: create does not set close-on-invalidate, and on iOS 27 the socket
// plus its run-loop descriptors stay open. Closing only CFSocketGetNative
// left the others. A socketpair plus CFSocketCreateWithNative would close
// the caller's descriptor twice when invalidation also closes it.
static void TellomiCloseDescriptorsOpenedSince(const char *openBefore, int limit) {
    for (int fd = 0; fd < limit; fd++) {
        if (!openBefore[fd] && fcntl(fd, F_GETFD) >= 0) {
            close(fd);
        }
    }
}

static uintptr_t TellomiCFSocketISA(void) {
    static uintptr_t isa = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int limit = (int)sysconf(_SC_OPEN_MAX);
        if (limit < 0 || limit > 4096) {
            limit = 1024;
        }
        char *openBefore = calloc((size_t)limit, 1);
        if (openBefore == NULL) {
            return;
        }
        for (int fd = 0; fd < limit; fd++) {
            if (fcntl(fd, F_GETFD) >= 0) {
                openBefore[fd] = 1;
            }
        }
        CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
        if (socket != NULL) {
            memcpy(&isa, socket, sizeof(isa));
            CFRelease(socket);
        }
        TellomiCloseDescriptorsOpenedSince(openBefore, limit);
        free(openBefore);
    });
    return isa;
}

static BOOL TellomiIsLiveCFSocket(const void *pointer, uintptr_t socketISA) {
    if (pointer == NULL || socketISA == 0) {
        return NO;
    }
    uintptr_t isa = 0;
    if (!TellomiBytesReadable(pointer, sizeof(isa))) {
        return NO;
    }
    memcpy(&isa, pointer, sizeof(isa));
    if (isa != socketISA) {
        return NO;
    }
    return CFGetTypeID((CFTypeRef)pointer) == CFSocketGetTypeID();
}

static CFSocketRef TellomiFindSocket(const void *object, size_t words, uintptr_t socketISA) {
    if (!TellomiBytesReadable(object, words * sizeof(uintptr_t))) {
        return NULL;
    }
    const uintptr_t *slots = (const uintptr_t *)object;
    for (size_t index = 0; index < words; index++) {
        uintptr_t value = slots[index];
        if (value < 0x10000) {
            continue;
        }
        if (TellomiIsLiveCFSocket((const void *)value, socketISA)) {
            return (CFSocketRef)value;
        }
    }
    return NULL;
}

static CFSocketRef TellomiSocketInStream(CFTypeRef stream) {
    uintptr_t socketISA = TellomiCFSocketISA();
    if (stream == NULL || socketISA == 0) {
        return NULL;
    }
    CFSocketRef socket = TellomiFindSocket(stream, 32, socketISA);
    if (socket != NULL) {
        return socket;
    }
    if (!TellomiBytesReadable(stream, 16 * sizeof(uintptr_t))) {
        return NULL;
    }
    const uintptr_t *slots = (const uintptr_t *)stream;
    for (size_t index = 0; index < 16; index++) {
        uintptr_t value = slots[index];
        if (value < 0x10000 || !TellomiBytesReadable((const void *)value, 8 * sizeof(uintptr_t))) {
            continue;
        }
        socket = TellomiFindSocket((const void *)value, 48, socketISA);
        if (socket != NULL) {
            return socket;
        }
    }
    return NULL;
}

static void TellomiEnsureReleaseQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDeferredCFSocketReleaseQueue = dispatch_queue_create("tellomi.cfsocket.release", DISPATCH_QUEUE_SERIAL);
    });
}

int TellomiDeferredCFSocketReleaseCount(void) {
    return atomic_load_explicit(&gDeferredCFSocketReleaseCount, memory_order_relaxed);
}

CFTypeRef TellomiRetainIfCFRelease(const void *info, void (*release)(const void *)) {
    // CFSocketGetContext copies the context. It does not leave an extra
    // retain for us to undo. Calling context.release here dropped the
    // object's last retain: one release too many. A release function that
    // is not CFRelease is left untouched, and the caller closes the
    // streams the way it did before this workaround.
    if (info == NULL || !TellomiReleaseIsCFRelease(release)) {
        return NULL;
    }
    CFRetain((CFTypeRef)info);
    atomic_fetch_add_explicit(&gDeferredCFSocketReleaseCount, 1, memory_order_relaxed);
    return (CFTypeRef)info;
}

void TellomiFlushDeferredCFSocketReleases(void) {
    if (gDeferredCFSocketReleaseQueue == NULL) {
        return;
    }
    dispatch_sync(gDeferredCFSocketReleaseQueue, ^{});
}

CFTypeRef TellomiRetainSocketStream(CFTypeRef stream) {
#if defined(__arm64e__)
    // This workaround reads a CFSocket out of a stream and compares its
    // release function. No arm64e run has shown that is valid under
    // pointer authentication. The simulator is arm64 and cannot show it
    // either. An arm64e build therefore does not retain anything and
    // closeWithError closes the streams as it did before.
    (void)stream;
    return NULL;
#else
    TellomiEnsureReleaseQueue();
    CFSocketRef socket = TellomiSocketInStream(stream);
    if (socket == NULL) {
        return NULL;
    }
    CFSocketContext context = {0};
    CFSocketGetContext(socket, &context);
    // Do not CFRelease context.info here. GetContext does not leave an
    // extra retain on this OS, and releasing the stream's object before
    // CFStreamClose is a bus error. A release callback other than
    // CFRelease is not called.
    return TellomiRetainIfCFRelease(context.info, context.release);
#endif
}

void TellomiReleaseSocketStreamLater(CFTypeRef object) {
    if (object == NULL) {
        return;
    }
    TellomiEnsureReleaseQueue();
    dispatch_async(gDeferredCFSocketReleaseQueue, ^{
        CFRelease(object);
    });
}
