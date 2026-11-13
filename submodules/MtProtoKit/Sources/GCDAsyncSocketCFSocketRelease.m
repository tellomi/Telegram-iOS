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

static void *TellomiStripDataPointer(void *pointer) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(pointer, ptrauth_key_process_independent_data);
#else
    return pointer;
#endif
}

static BOOL TellomiBytesReadable(const void *address, size_t size) {
    if (address == NULL || size == 0 || size > 4096) {
        return NO;
    }
    char buffer[4096];
    vm_size_t copied = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(), (vm_address_t)address, (vm_size_t)size, (vm_address_t)buffer, &copied);
    return result == KERN_SUCCESS && copied == size;
}

// arm64e signs each object's isa. Comparing the raw stored bits fails even
// when both objects are CFSockets. Stripping the signature leaves the class
// pointer, which is the same for every instance, and does not authenticate.
static void *TellomiCFSocketClassPointer(void) {
    static void *classPointer = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int limit = (int)sysconf(_SC_OPEN_MAX);
        if (limit < 0 || limit > 4096) {
            limit = 1024;
        }
        char *openBefore = calloc((size_t)limit, 1);
        if (openBefore != NULL) {
            for (int fd = 0; fd < limit; fd++) {
                if (fcntl(fd, F_GETFD) >= 0) {
                    openBefore[fd] = 1;
                }
            }
        }
        CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
        if (socket != NULL) {
            void *isa = NULL;
            memcpy(&isa, socket, sizeof(isa));
            classPointer = TellomiStripDataPointer(isa);
            CFRelease(socket);
            if (openBefore != NULL) {
                for (int fd = 0; fd < limit; fd++) {
                    if (!openBefore[fd] && fcntl(fd, F_GETFD) >= 0) {
                        close(fd);
                    }
                }
            }
        }
        free(openBefore);
    });
    return classPointer;
}

static BOOL TellomiIsLiveCFSocket(const void *pointer, void *socketClass) {
    if (pointer == NULL || socketClass == NULL || !TellomiBytesReadable(pointer, sizeof(void *))) {
        return NO;
    }
    void *isa = NULL;
    memcpy(&isa, pointer, sizeof(isa));
    if (TellomiStripDataPointer(isa) != socketClass) {
        return NO;
    }
    return CFGetTypeID((CFTypeRef)pointer) == CFSocketGetTypeID();
}

static CFSocketRef TellomiFindSocket(const void *object, size_t words, void *socketClass) {
    if (!TellomiBytesReadable(object, words * sizeof(uintptr_t))) {
        return NULL;
    }
    const uintptr_t *slots = (const uintptr_t *)object;
    for (size_t index = 0; index < words; index++) {
        uintptr_t value = slots[index];
        if (value < 0x10000) {
            continue;
        }
        if (TellomiIsLiveCFSocket((const void *)value, socketClass)) {
            return (CFSocketRef)value;
        }
    }
    return NULL;
}

static CFSocketRef TellomiSocketInStream(CFTypeRef stream) {
    void *socketClass = TellomiCFSocketClassPointer();
    if (stream == NULL || socketClass == NULL) {
        return NULL;
    }
    CFSocketRef socket = TellomiFindSocket(stream, 32, socketClass);
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
        socket = TellomiFindSocket((const void *)value, 48, socketClass);
        if (socket != NULL) {
            return socket;
        }
    }
    return NULL;
}

CFTypeRef TellomiSocketStreamContextInfo(CFTypeRef stream) {
    CFSocketRef socket = TellomiSocketInStream(stream);
    if (socket == NULL) {
        return NULL;
    }
    CFSocketContext context = {0};
    CFSocketGetContext(socket, &context);
    // GetContext does not leave a retain. Do not CFRelease info.
    if (!TellomiReleaseIsCFRelease(context.release)) {
        return NULL;
    }
    return (CFTypeRef)context.info;
}

CFTypeRef TellomiRetainSocketStream(CFTypeRef stream) {
    // CFSocketInvalidate CFReleases context.info (the SocketStream), not the
    // CFReadStream wrapper the caller holds. Retaining the wrapper leaves
    // that SocketStream's last retain inside the lock. This retains info
    // itself, on arm64 and arm64e. The release function is only compared,
    // never called or written.
    CFTypeRef info = TellomiSocketStreamContextInfo(stream);
    if (info == NULL) {
        return NULL;
    }
    TellomiEnsureReleaseQueue();
    CFRetain(info);
    atomic_fetch_add_explicit(&gDeferredCFSocketReleaseCount, 1, memory_order_relaxed);
    return info;
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
