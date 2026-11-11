#include "GCDAsyncSocketStreamClose.h"

bool GCDAsyncSocketPlanStreamClose(int *closing, int *ops, int capacity, int *count) {
    if (closing == 0 || ops == 0 || count == 0 || capacity < 5) {
        return false;
    }
    if (*closing) {
        *count = 0;
        return false;
    }
    *closing = 1;
    ops[0] = GCDAsyncSocketStreamCloseClearReadClient;
    ops[1] = GCDAsyncSocketStreamCloseClearWriteClient;
    ops[2] = GCDAsyncSocketStreamCloseRemoveFromRunLoop;
    ops[3] = GCDAsyncSocketStreamCloseCloseWrite;
    ops[4] = GCDAsyncSocketStreamCloseCloseRead;
    *count = 5;
    return true;
}
