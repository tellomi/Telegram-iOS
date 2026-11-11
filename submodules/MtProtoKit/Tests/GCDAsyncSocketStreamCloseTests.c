#include <stdio.h>
#include <stdlib.h>

#include "GCDAsyncSocketStreamClose.h"

static int g_failures = 0;

static void expect(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", message);
        g_failures++;
    }
}

static void test_order(void) {
    int closing = 0;
    int ops[8];
    int count = 0;
    expect(GCDAsyncSocketPlanStreamClose(&closing, ops, 8, &count), "first plan");
    expect(closing == 1, "marked closing");
    expect(count == 5, "five steps");
    expect(ops[0] == GCDAsyncSocketStreamCloseClearReadClient, "clear read client first");
    expect(ops[1] == GCDAsyncSocketStreamCloseClearWriteClient, "clear write client");
    expect(ops[2] == GCDAsyncSocketStreamCloseRemoveFromRunLoop, "leave the run loop before close");
    expect(ops[3] == GCDAsyncSocketStreamCloseCloseWrite, "close write after detach");
    expect(ops[4] == GCDAsyncSocketStreamCloseCloseRead, "close read last");
}

static int g_executed[6];
static int g_closing = 0;

static void execute(int op) {
    int nested_ops[8];
    int nested_count = -1;
    g_executed[op]++;
    // A CFStream/CFSocket callback during close must not start another close.
    expect(!GCDAsyncSocketPlanStreamClose(&g_closing, nested_ops, 8, &nested_count), "re-entry refused");
    expect(nested_count == 0, "re-entry performs no steps");
}

static void test_reentry_during_each_step(void) {
    int ops[8];
    int count = 0;
    int i;
    for (i = 0; i < 6; i++) {
        g_executed[i] = 0;
    }
    g_closing = 0;
    expect(GCDAsyncSocketPlanStreamClose(&g_closing, ops, 8, &count), "outer plan");
    for (i = 0; i < count; i++) {
        execute(ops[i]);
    }
    expect(g_executed[GCDAsyncSocketStreamCloseClearReadClient] == 1, "read client once");
    expect(g_executed[GCDAsyncSocketStreamCloseClearWriteClient] == 1, "write client once");
    expect(g_executed[GCDAsyncSocketStreamCloseRemoveFromRunLoop] == 1, "run loop once");
    expect(g_executed[GCDAsyncSocketStreamCloseCloseWrite] == 1, "write close once");
    expect(g_executed[GCDAsyncSocketStreamCloseCloseRead] == 1, "read close once");
}

static void test_finished_close_can_run_again(void) {
    int closing = 0;
    int ops[8];
    int count = 0;
    expect(GCDAsyncSocketPlanStreamClose(&closing, ops, 8, &count), "first");
    closing = 0;
    count = 0;
    expect(GCDAsyncSocketPlanStreamClose(&closing, ops, 8, &count), "after the flag is cleared");
    expect(count == 5, "full plan again");
}

int main(void) {
    test_order();
    test_reentry_during_each_step();
    test_finished_close_can_run_again();
    if (g_failures != 0) {
        fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    return 0;
}
