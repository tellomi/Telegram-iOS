#ifndef GCDAsyncSocketCFSocketRelease_h
#define GCDAsyncSocketCFSocketRelease_h

#include <CoreFoundation/CoreFoundation.h>

// How many CFSocket context.release pointers have been pointed at the
// deferred CFRelease. A test uses this to show the close reached the
// CFSocket inside the stream pair.
int TellomiDeferredCFSocketReleaseCount(void);

// Build 90 died inside one CFStreamClose:
//   CFSocketInvalidate
//   SocketStream::~SocketStream
//   CFSocketInvalidate          <- same os_unfair_lock, same thread
//   SocketStream::close
//   _CFStreamClose
// The stream callbacks in GCDAsyncSocket dispatch_async onto the socket
// queue before they call closeWithError, so they do not re-enter it.
// CFSocketInvalidate's CFRelease of that SocketStream is the frame between
// the two locks (CocoaAsyncSocket issue 803; Telegram-iOS issue 2306).
// This replaces that release with one that runs on another queue, so the
// destructor's CFSocketInvalidate runs after the outer call unlocks.
// The iOS 16 write-up hardcodes field offsets. Those are not used here:
// the socket is recognized by the isa of a live CFSocket, and the context
// is the slot whose release function is CFRelease.
void TellomiDeferCFSocketContextRelease(CFTypeRef stream);

#endif
