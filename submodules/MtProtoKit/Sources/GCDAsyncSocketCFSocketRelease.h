#ifndef GCDAsyncSocketCFSocketRelease_h
#define GCDAsyncSocketCFSocketRelease_h

#include <CoreFoundation/CoreFoundation.h>

// How many SocketStreams were retained across a close. The iOS test uses
// this to show close found the object CFSocketInvalidate would CFRelease.
int TellomiDeferredCFSocketReleaseCount(void);

// Blocks until TellomiReleaseSocketStreamLater has run.
void TellomiFlushDeferredCFSocketReleases(void);

// Build 90 died inside one CFStreamClose:
//   CFSocketInvalidate
//   SocketStream::~SocketStream
//   CFSocketInvalidate
//   SocketStream::close
//   _CFStreamClose
// CFSocketInvalidate CFReleases the SocketStream stored in its context
// while it still holds the os_unfair_lock. The destructor invalidates that
// same socket. The stream callbacks only dispatch_async onto the socket
// queue, so they are not this re-entry. CocoaAsyncSocket issue 803 and
// Telegram-iOS issue 2306 show the same stack. Rewriting context.release
// is not used: the crash device is arm64e, and a function pointer stored
// there is signed.
//
// This retains that SocketStream through the public CFSocketGetContext
// before CFStreamClose, so the CFRelease inside CFSocketInvalidate cannot
// drop the last retain. The destructor therefore cannot run until the
// later CFRelease, which is after CFStreamClose has returned. No private
// function pointer is written.
//
// When release is CFRelease, TellomiRetainIfCFRelease always CFRetains
// info. Any other release function is not called, and the result is NULL.
// Calling it was one release too many.
//
// An arm64e (pointer-authenticated) build does not do this. Nothing here
// has been shown to be valid under pointer authentication: the simulator
// is arm64. TellomiRetainSocketStream returns NULL there, and the streams
// close as they did before.
CFTypeRef TellomiRetainIfCFRelease(const void *info, void (*release)(const void *));
CFTypeRef TellomiRetainSocketStream(CFTypeRef stream);

// CFRelease on the queue used to keep the destructor off the close stack.
void TellomiReleaseSocketStreamLater(CFTypeRef object);

#endif
