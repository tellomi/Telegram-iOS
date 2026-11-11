#import "GCDAsyncSocketCFSocketRelease.h"

#import <mach/mach.h>

#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

static int gDeferredCFSocketReleaseCount = 0;
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

static BOOL TellomiReleaseIsCFRelease(void (*release)(const void *)) {
    if (release == NULL) {
        return NO;
    }
#if __has_feature(ptrauth_calls)
    void *got = ptrauth_strip((void *)release, ptrauth_key_function_pointer);
    void *want = ptrauth_strip((void *)CFRelease, ptrauth_key_function_pointer);
    return got == want;
#else
    return release == CFRelease;
#endif
}

// CFSocketCreate owns the descriptor it allocates. CFRelease is the only
// close. A socketpair plus CFSocketCreateWithNative would close that
// descriptor twice when invalidation also closes it.
static uintptr_t TellomiCFSocketISA(void) {
    static uintptr_t isa = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
        if (socket != NULL) {
            memcpy(&isa, socket, sizeof(isa));
            CFRelease(socket);
        }
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
    return gDeferredCFSocketReleaseCount;
}

void TellomiFlushDeferredCFSocketReleases(void) {
    if (gDeferredCFSocketReleaseQueue == NULL) {
        return;
    }
    dispatch_sync(gDeferredCFSocketReleaseQueue, ^{});
}

CFTypeRef TellomiRetainSocketStream(CFTypeRef stream) {
    TellomiEnsureReleaseQueue();
    CFSocketRef socket = TellomiSocketInStream(stream);
    if (socket == NULL) {
        return NULL;
    }
    CFSocketContext context = {0};
    CFSocketGetContext(socket, &context);
    if (context.info == NULL || !TellomiReleaseIsCFRelease(context.release)) {
        if (context.retain != NULL && context.info != NULL && context.release != NULL) {
            context.release(context.info);
        }
        return NULL;
    }
    if (context.retain == NULL) {
        CFRetain((CFTypeRef)context.info);
    }
    gDeferredCFSocketReleaseCount += 1;
    return (CFTypeRef)context.info;
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
