#import <XCTest/XCTest.h>

#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

#import "GCDAsyncSocket.h"
#import "GCDAsyncSocketCFSocketRelease.h"

static const int kClosedSocket = -1;

@interface GCDAsyncSocketFDProbe : GCDAsyncSocket
- (int)probedFD;
@end

@implementation GCDAsyncSocketFDProbe

- (int)probedFD {
    if (socket4FD != kClosedSocket) {
        return socket4FD;
    }
    return socket6FD;
}

@end

@interface GCDAsyncSocketCloseTests : XCTestCase <GCDAsyncSocketDelegate>
@property (nonatomic, strong) XCTestExpectation *connected;
@property (nonatomic, strong) XCTestExpectation *disconnected;
@property (nonatomic, strong) NSError *disconnectError;
@property (nonatomic) int connectedFD;
@end

@implementation GCDAsyncSocketCloseTests

- (void)setUp {
    [super setUp];
    self.connected = nil;
    self.disconnected = nil;
    self.disconnectError = nil;
    self.connectedFD = kClosedSocket;
}

- (void)armConnectionExpectations {
    self.connected = [self expectationWithDescription:@"connected"];
    self.disconnected = [self expectationWithDescription:@"disconnected"];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    self.connectedFD = [(GCDAsyncSocketFDProbe *)sock probedFD];
    [self.connected fulfill];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    self.disconnectError = err;
    [self.disconnected fulfill];
}

- (int)countOpenDescriptors {
    int count = 0;
    int limit = (int)sysconf(_SC_OPEN_MAX);
    if (limit < 0 || limit > 4096) {
        limit = 1024;
    }
    for (int fd = 0; fd < limit; fd++) {
        if (fcntl(fd, F_GETFD) >= 0) {
            count += 1;
        }
    }
    return count;
}

- (int)listenOnLoopback:(uint16_t *)port {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    XCTAssertGreaterThanOrEqual(fd, 0);
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    XCTAssertEqual(bind(fd, (struct sockaddr *)&address, sizeof(address)), 0);
    XCTAssertEqual(listen(fd, 4), 0);
    socklen_t length = sizeof(address);
    XCTAssertEqual(getsockname(fd, (struct sockaddr *)&address, &length), 0);
    *port = ntohs(address.sin_port);
    return fd;
}

- (int)acceptFrom:(int)listenFD {
    __block int accepted = kClosedSocket;
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        accepted = accept(listenFD, NULL, NULL);
        dispatch_semaphore_signal(ready);
    });
    XCTAssertEqual(dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)), 0);
    XCTAssertGreaterThanOrEqual(accepted, 0);
    return accepted;
}

- (GCDAsyncSocketFDProbe *)connectToPort:(uint16_t)port {
    dispatch_queue_t queue = dispatch_queue_create("GCDAsyncSocketCloseTests", DISPATCH_QUEUE_SERIAL);
    GCDAsyncSocketFDProbe *socket = [[GCDAsyncSocketFDProbe alloc] initWithDelegate:self delegateQueue:queue];
    NSError *error = nil;
    XCTAssertTrue([socket connectToHost:@"127.0.0.1" onPort:port error:&error], @"%@", error);
    [self waitForExpectations:@[self.connected] timeout:5];
    XCTAssertGreaterThanOrEqual(self.connectedFD, 0);
    return socket;
}

- (void)waitUntilDescriptorClosed:(int)fd {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([deadline timeIntervalSinceNow] > 0) {
        if (fcntl(fd, F_GETFD) < 0 && errno == EBADF) {
            return;
        }
        usleep(10000);
    }
    XCTFail(@"descriptor %d was not closed", fd);
}

- (int)occupyClosedDescriptor:(int)wanted extras:(int *)extras count:(int *)count {
    *count = 0;
    for (int index = 0; index < 128; index++) {
        int fd = open("/dev/null", O_RDONLY);
        if (fd < 0) {
            return kClosedSocket;
        }
        if (fd == wanted) {
            return fd;
        }
        if (fd > wanted) {
            close(fd);
            return kClosedSocket;
        }
        extras[*count] = fd;
        *count += 1;
    }
    return kClosedSocket;
}

- (void)closeExtras:(int *)extras count:(int)count {
    for (int index = 0; index < count; index++) {
        close(extras[index]);
    }
}

- (void)discardOneConnection {
    [self armConnectionExpectations];
    uint16_t port = 0;
    int listenFD = [self listenOnLoopback:&port];
    GCDAsyncSocketFDProbe *socket = [self connectToPort:port];
    int accepted = [self acceptFrom:listenFD];
    int fd = self.connectedFD;
    [socket disconnect];
    [self waitForExpectations:@[self.disconnected] timeout:5];
    [self waitUntilDescriptorClosed:fd];
    close(accepted);
    close(listenFD);
    socket = nil;
    TellomiFlushDeferredCFSocketReleases();
}

// The first CFStream connection closes one process descriptor on the next
// connection. Do that before the count. The equality stays exact.
- (void)primeDescriptorBaseline {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @autoreleasepool {
            [self discardOneConnection];
            [self discardOneConnection];
        }
    });
}

// connectToPort returns an autoreleased socket. Its last retain, and the
// deferred SocketStream release, drop after this pool drains. A descriptor
// still open two seconds later is a leak: the equality is unchanged.
- (void)assertNoDescriptorsLeftSince:(int)openBefore {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([deadline timeIntervalSinceNow] > 0) {
        if ([self countOpenDescriptors] == openBefore) {
            return;
        }
        usleep(20000);
    }
    XCTAssertEqual([self countOpenDescriptors], openBefore);
}

- (void)testNormalDisconnectClosesTheDescriptorOnce {
    [self primeDescriptorBaseline];
    [self armConnectionExpectations];
    int openBefore = [self countOpenDescriptors];
    @autoreleasepool {
    int deferredBefore = TellomiDeferredCFSocketReleaseCount();
    uint16_t port = 0;
    int listenFD = [self listenOnLoopback:&port];
    GCDAsyncSocketFDProbe *socket = [self connectToPort:port];
    int accepted = [self acceptFrom:listenFD];
    int fd = self.connectedFD;

    [socket disconnect];
    [self waitForExpectations:@[self.disconnected] timeout:5];
    [self waitUntilDescriptorClosed:fd];
#if TARGET_OS_IPHONE
    XCTAssertGreaterThan(TellomiDeferredCFSocketReleaseCount(), deferredBefore);
#else
    (void)deferredBefore;
#endif

    int extras[128];
    int extraCount = 0;
    int holder = [self occupyClosedDescriptor:fd extras:extras count:&extraCount];
    XCTAssertEqual(holder, fd);
    [socket disconnect];
    XCTAssertGreaterThanOrEqual(fcntl(holder, F_GETFD), 0);

    close(holder);
    [self closeExtras:extras count:extraCount];
    close(accepted);
    close(listenFD);
    socket = nil;
    TellomiFlushDeferredCFSocketReleases();
    }
    [self assertNoDescriptorsLeftSince:openBefore];
}

- (void)testReadErrorClosesTheDescriptorOnce {
    [self primeDescriptorBaseline];
    [self armConnectionExpectations];
    int openBefore = [self countOpenDescriptors];
    @autoreleasepool {
    int deferredBefore = TellomiDeferredCFSocketReleaseCount();
    uint16_t port = 0;
    int listenFD = [self listenOnLoopback:&port];
    GCDAsyncSocketFDProbe *socket = [self connectToPort:port];
    int accepted = [self acceptFrom:listenFD];
    int fd = self.connectedFD;
    [socket readDataWithTimeout:5 tag:1];
    close(accepted);
    accepted = kClosedSocket;

    [self waitForExpectations:@[self.disconnected] timeout:5];
    XCTAssertNotNil(self.disconnectError);
    [self waitUntilDescriptorClosed:fd];
#if TARGET_OS_IPHONE
    XCTAssertGreaterThan(TellomiDeferredCFSocketReleaseCount(), deferredBefore);
#else
    (void)deferredBefore;
#endif

    int extras[128];
    int extraCount = 0;
    int holder = [self occupyClosedDescriptor:fd extras:extras count:&extraCount];
    XCTAssertEqual(holder, fd);
    close(holder);
    [self closeExtras:extras count:extraCount];
    close(listenFD);
    socket = nil;
    TellomiFlushDeferredCFSocketReleases();
    }
    [self assertNoDescriptorsLeftSince:openBefore];
}

- (void)testDisconnectTwiceDoesNotCloseAReusedDescriptor {
    [self primeDescriptorBaseline];
    [self armConnectionExpectations];
    int openBefore = [self countOpenDescriptors];
    @autoreleasepool {
    uint16_t port = 0;
    int listenFD = [self listenOnLoopback:&port];
    GCDAsyncSocketFDProbe *socket = [self connectToPort:port];
    int accepted = [self acceptFrom:listenFD];
    int fd = self.connectedFD;
    [socket disconnect];
    [self waitForExpectations:@[self.disconnected] timeout:5];
    [self waitUntilDescriptorClosed:fd];

    int extras[128];
    int extraCount = 0;
    int holder = [self occupyClosedDescriptor:fd extras:extras count:&extraCount];
    XCTAssertEqual(holder, fd);
    [socket disconnect];
    XCTAssertGreaterThanOrEqual(fcntl(holder, F_GETFD), 0);

    close(holder);
    [self closeExtras:extras count:extraCount];
    close(accepted);
    close(listenFD);
    socket = nil;
    TellomiFlushDeferredCFSocketReleases();
    }
    [self assertNoDescriptorsLeftSince:openBefore];
}

- (void)testReconnectAfterCloseUsesANewConnection {
    [self primeDescriptorBaseline];
    [self armConnectionExpectations];
    int openBefore = [self countOpenDescriptors];
    @autoreleasepool {
    int deferredBefore = TellomiDeferredCFSocketReleaseCount();
    uint16_t port = 0;
    int listenFD = [self listenOnLoopback:&port];

    GCDAsyncSocketFDProbe *socket = [self connectToPort:port];
    int accepted = [self acceptFrom:listenFD];
    int firstFD = self.connectedFD;
    [socket disconnect];
    [self waitForExpectations:@[self.disconnected] timeout:5];
    [self waitUntilDescriptorClosed:firstFD];
    close(accepted);

    self.connected = [self expectationWithDescription:@"reconnected"];
    self.disconnected = [self expectationWithDescription:@"disconnected again"];
    self.connectedFD = kClosedSocket;
    NSError *error = nil;
    XCTAssertTrue([socket connectToHost:@"127.0.0.1" onPort:port error:&error], @"%@", error);
    [self waitForExpectations:@[self.connected] timeout:5];
    int secondFD = self.connectedFD;
    XCTAssertGreaterThanOrEqual(secondFD, 0);
    int acceptedAgain = [self acceptFrom:listenFD];
    [socket disconnect];
    [self waitForExpectations:@[self.disconnected] timeout:5];
    [self waitUntilDescriptorClosed:secondFD];
#if TARGET_OS_IPHONE
    XCTAssertGreaterThanOrEqual(TellomiDeferredCFSocketReleaseCount(), deferredBefore + 2);
#else
    (void)deferredBefore;
#endif

    int extras[128];
    int extraCount = 0;
    int holder = [self occupyClosedDescriptor:secondFD extras:extras count:&extraCount];
    XCTAssertEqual(holder, secondFD);
    close(holder);
    [self closeExtras:extras count:extraCount];
    close(acceptedAgain);
    close(listenFD);
    socket = nil;
    TellomiFlushDeferredCFSocketReleases();
    }
    [self assertNoDescriptorsLeftSince:openBefore];
}

- (void)testPairedStreamCloseLeavesTheSocketStreamAlive {
    int fds[2] = {-1, -1};
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, fds), 0);
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, fds[0], &readStream, &writeStream);
    XCTAssertTrue(readStream != NULL && writeStream != NULL);
    CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanFalse);
    CFWriteStreamSetProperty(writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanFalse);
    XCTAssertTrue(CFReadStreamOpen(readStream));
    XCTAssertTrue(CFWriteStreamOpen(writeStream));

    CFTypeRef heldRead = TellomiRetainSocketStream((CFTypeRef)readStream);
    CFTypeRef heldWrite = TellomiRetainSocketStream((CFTypeRef)writeStream);
    CFTypeRef held = heldRead != NULL ? heldRead : heldWrite;
    XCTAssertTrue(held != NULL);

    CFReadStreamClose(readStream);
    CFWriteStreamClose(writeStream);
    CFRelease(readStream);
    CFRelease(writeStream);

    // CFSocketInvalidate CFReleases this object while holding the lock.
    // The extra retain is why its destructor, and the second
    // CFSocketInvalidate, cannot run until the later release.
    XCTAssertGreaterThanOrEqual(CFGetRetainCount(held), 1);

    TellomiReleaseSocketStreamLater(heldRead);
    TellomiReleaseSocketStreamLater(heldWrite);
    TellomiFlushDeferredCFSocketReleases();

    XCTAssertEqual(close(fds[0]), 0);
    XCTAssertEqual(close(fds[0]), -1);
    XCTAssertEqual(errno, EBADF);
    XCTAssertEqual(close(fds[1]), 0);
}

static int gForeignReleaseCalls = 0;

static void TellomiForeignRelease(const void *info) {
    gForeignReleaseCalls += 1;
    (void)info;
}

- (void)testForeignReleaseIsNotCalledAndDoesNotDropARetain {
    CFStringRef info = CFStringCreateWithCString(NULL, "tellomi-socket", kCFStringEncodingUTF8);
    CFIndex before = CFGetRetainCount(info);
    int deferredBefore = TellomiDeferredCFSocketReleaseCount();
    gForeignReleaseCalls = 0;

    CFTypeRef held = TellomiRetainIfCFRelease(info, TellomiForeignRelease);

    XCTAssertTrue(held == NULL);
    XCTAssertEqual(gForeignReleaseCalls, 0);
    XCTAssertEqual(CFGetRetainCount(info), before);
    XCTAssertEqual(TellomiDeferredCFSocketReleaseCount(), deferredBefore);
    CFRelease(info);
}

- (void)testCFReleaseContextTakesExactlyOneRetain {
    CFStringRef info = CFStringCreateWithCString(NULL, "tellomi-socket", kCFStringEncodingUTF8);
    CFIndex before = CFGetRetainCount(info);
    int deferredBefore = TellomiDeferredCFSocketReleaseCount();

    CFTypeRef held = TellomiRetainIfCFRelease(info, CFRelease);

    XCTAssertTrue(held == info);
    XCTAssertEqual(CFGetRetainCount(info), before + 1);
    XCTAssertEqual(TellomiDeferredCFSocketReleaseCount(), deferredBefore + 1);

    TellomiReleaseSocketStreamLater(held);
    TellomiFlushDeferredCFSocketReleases();
    XCTAssertEqual(CFGetRetainCount(info), before);
    CFRelease(info);
}

@end
