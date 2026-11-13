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
// Apple's CFSocketStream stores the CFReadStream/CFWriteStream as the
// CFSocket context. CFSocketInvalidate CFReleases that object while it
// still holds the socket's os_unfair_lock. If that release is the last
// one, ~SocketStream runs inside the lock and calls CFSocketInvalidate
// again. TellomiRetainSocketStream CFRetains the stream pointer close
// already owns, before CFStreamClose. The invalidate's CFRelease is then
// not the last one, so the destructor waits until TellomiReleaseSocketStreamLater
// runs on another queue, after CFStreamClose has returned and dropped the
// lock. The same CFRetain is used on arm64 and arm64e. It does not read
// or write a function pointer, so pointer authentication does not change it.
//
// TellomiRetainIfCFRelease is the older helper kept for the test that a
// foreign release function is not called. The close path does not use it.
CFTypeRef TellomiRetainIfCFRelease(const void *info, void (*release)(const void *));
CFTypeRef TellomiRetainSocketStream(CFTypeRef stream);

// CFRelease on the queue used to keep the destructor off the close stack.
void TellomiReleaseSocketStreamLater(CFTypeRef object);

#endif
