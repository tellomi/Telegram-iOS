#ifndef GCDAsyncSocketStreamClose_h
#define GCDAsyncSocketStreamClose_h

#include <stdbool.h>

// Order of tearing down the CFStream pair inside closeWithError.
// Clear both clients, leave the run loop, then close the write stream and
// the read stream. A second call while *closing is set does nothing: a
// CFStream callback that arrives during this sequence must not enter
// closeWithError again.
enum {
    GCDAsyncSocketStreamCloseClearReadClient = 1,
    GCDAsyncSocketStreamCloseClearWriteClient = 2,
    GCDAsyncSocketStreamCloseRemoveFromRunLoop = 3,
    GCDAsyncSocketStreamCloseCloseWrite = 4,
    GCDAsyncSocketStreamCloseCloseRead = 5
};

// On the first call, sets *closing and writes five steps into ops.
// On re-entry (*closing already set), writes nothing and returns false.
bool GCDAsyncSocketPlanStreamClose(int *closing, int *ops, int capacity, int *count);

#endif
