#import "GCDAsyncSocketCFSocketRelease.h"

#import <mach/mach.h>
#import <sys/socket.h>
#import <unistd.h>

static int gDeferredCFSocketReleaseCount = 0;
static dispatch_queue_t gDeferredCFSocketReleaseQueue;

static void TellomiDeferredCFRelease(const void *info) {
    if (info == NULL) {
        return;
    }
    dispatch_async(gDeferredCFSocketReleaseQueue, ^{
        CFRelease((CFTypeRef)info);
    });
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

static uintptr_t TellomiCFSocketISA(void) {
    static uintptr_t isa = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int fds[2] = {-1, -1};
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) {
            return;
        }
        CFSocketContext context = {0, NULL, NULL, NULL, NULL};
        CFSocketRef socket = CFSocketCreateWithNative(kCFAllocatorDefault, fds[0], 0, NULL, &context);
        if (socket != NULL) {
            memcpy(&isa, socket, sizeof(isa));
            CFRelease(socket);
        }
        if (fds[0] >= 0) {
            close(fds[0]);
        }
        if (fds[1] >= 0) {
            close(fds[1]);
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

static void TellomiPatchSocket(const void *socket) {
    const size_t bytes = 512;
    if (!TellomiBytesReadable(socket, bytes)) {
        return;
    }
    const uint8_t *base = (const uint8_t *)socket;
    for (size_t offset = 0; offset + sizeof(CFIndex) + 4 * sizeof(void *) <= bytes; offset += sizeof(void *)) {
        CFIndex version = 0;
        void *info = NULL;
        void *release = NULL;
        memcpy(&version, base + offset, sizeof(version));
        if (version != 0) {
            continue;
        }
        memcpy(&info, base + offset + sizeof(CFIndex), sizeof(info));
        memcpy(&release, base + offset + sizeof(CFIndex) + 2 * sizeof(void *), sizeof(release));
        if (info == NULL || release != (void *)CFRelease) {
            continue;
        }
        void (**releaseSlot)(const void *) = (void (**)(const void *))(base + offset + sizeof(CFIndex) + 2 * sizeof(void *));
        *releaseSlot = TellomiDeferredCFRelease;
        gDeferredCFSocketReleaseCount += 1;
        return;
    }
}

static const void *TellomiFindSocket(const void *object, size_t words, uintptr_t socketISA) {
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
            return (const void *)value;
        }
    }
    return NULL;
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

void TellomiDeferCFSocketContextRelease(CFTypeRef stream) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gDeferredCFSocketReleaseQueue = dispatch_queue_create("tellomi.cfsocket.release", DISPATCH_QUEUE_SERIAL);
    });
    uintptr_t socketISA = TellomiCFSocketISA();
    if (stream == NULL || socketISA == 0) {
        return;
    }
    const void *socket = TellomiFindSocket(stream, 32, socketISA);
    if (socket == NULL) {
        const uintptr_t *slots = (const uintptr_t *)stream;
        if (!TellomiBytesReadable(stream, 16 * sizeof(uintptr_t))) {
            return;
        }
        for (size_t index = 0; index < 16 && socket == NULL; index++) {
            uintptr_t value = slots[index];
            if (value < 0x10000 || !TellomiBytesReadable((const void *)value, 8 * sizeof(uintptr_t))) {
                continue;
            }
            socket = TellomiFindSocket((const void *)value, 48, socketISA);
        }
    }
    if (socket != NULL) {
        TellomiPatchSocket(socket);
    }
}
