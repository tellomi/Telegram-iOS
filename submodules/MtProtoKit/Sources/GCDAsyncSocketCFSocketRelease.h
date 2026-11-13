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
// The object CFSocketInvalidate releases is CFSocket context.info, the
// SocketStream. That is not the CFReadStream/CFWriteStream the caller
// holds. CFStreamClose already runs while those wrappers are alive, so an
// extra CFRetain on the wrapper does not stop ~SocketStream from running
// inside the lock. TellomiRetainSocketStream CFRetains context.info when
// its release function is CFRelease. The function pointer is compared
// after stripping its signature and is never called or stored back.
// arm64e signs each isa with a different signature; the class pointer is
// compared after that signature is stripped, so the same lookup runs on
// the arm64e phones that crashed. The extra retain is released on another
// queue after CFStreamClose returns, when the socket lock is no longer held.
//
// The SocketStream found for a stream, or NULL. Not retained.
CFTypeRef TellomiSocketStreamContextInfo(CFTypeRef stream);
CFTypeRef TellomiRetainIfCFRelease(const void *info, void (*release)(const void *));
CFTypeRef TellomiRetainSocketStream(CFTypeRef stream);

// CFRelease on the queue used to keep the destructor off the close stack.
void TellomiReleaseSocketStreamLater(CFTypeRef object);

#endif
