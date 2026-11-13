#import "GCDAsyncSocketCFSocketRelease.h"

#import <stdatomic.h>

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

CFTypeRef TellomiRetainSocketStream(CFTypeRef stream) {
    // Apple's socket stream stores this CFReadStream/CFWriteStream as the
    // CFSocket context and releases it with CFRelease inside
    // CFSocketInvalidate, while that call still holds the socket lock.
    // One more CFRetain on the pointer we already own keeps the destructor
    // off that stack. The same CFRetain runs on arm64 and arm64e: it does
    // not read or write a function pointer.
    if (stream == NULL) {
        return NULL;
    }
    TellomiEnsureReleaseQueue();
    CFRetain(stream);
    atomic_fetch_add_explicit(&gDeferredCFSocketReleaseCount, 1, memory_order_relaxed);
    return stream;
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
