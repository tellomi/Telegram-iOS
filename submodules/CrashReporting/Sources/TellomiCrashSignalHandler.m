#import <Foundation/Foundation.h>
#import <CrashSignalHandler/TellomiCrashSignalHandler.h>

#import <execinfo.h>
#import <fcntl.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/utsname.h>
#import <time.h>
#import <unistd.h>

static char appVersionField[128];
static char buildVersionField[64];
static char osVersionField[64];
static char deviceTypeField[128];
static char architectureField[32];
static char incomingDirectory[768];
static uint8_t alternateStack[65536];
static volatile sig_atomic_t handling = 0;
static NSUncaughtExceptionHandler *previousExceptionHandler = NULL;
static int handlersInstalled = 0;

static void copy_field(char *destination, size_t capacity, NSString *value) {
    if (capacity == 0) {
        return;
    }
    destination[0] = '\0';
    if (value.length == 0) {
        return;
    }
    NSString *clean = [[value componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    const char *utf8 = clean.UTF8String;
    if (utf8 == NULL) {
        return;
    }
    strlcpy(destination, utf8, capacity);
}

static void write_all(int fd, const void *bytes, size_t length) {
    const char *cursor = bytes;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t wrote = write(fd, cursor, remaining);
        if (wrote <= 0) {
            return;
        }
        cursor += wrote;
        remaining -= (size_t)wrote;
    }
}

static void write_text(int fd, const char *text) {
    if (text == NULL) {
        return;
    }
    write_all(fd, text, strlen(text));
}

static void write_number(int fd, long long value) {
    char buffer[32];
    int count = 0;
    unsigned long long magnitude;
    if (value < 0) {
        write_text(fd, "-");
        magnitude = (unsigned long long)(-(value + 1)) + 1ULL;
    } else {
        magnitude = (unsigned long long)value;
    }
    if (magnitude == 0) {
        write_text(fd, "0");
        return;
    }
    while (magnitude > 0 && count < (int)sizeof(buffer)) {
        buffer[count++] = (char)('0' + (magnitude % 10ULL));
        magnitude /= 10ULL;
    }
    while (count > 0) {
        count -= 1;
        write_all(fd, &buffer[count], 1);
    }
}

static void write_metadata(int fd) {
    write_text(fd, "app=");
    write_text(fd, appVersionField);
    write_text(fd, "\nbuild=");
    write_text(fd, buildVersionField);
    write_text(fd, "\nos=");
    write_text(fd, osVersionField);
    write_text(fd, "\ndevice=");
    write_text(fd, deviceTypeField);
    write_text(fd, "\narch=");
    write_text(fd, architectureField);
    write_text(fd, "\n");
}

static const char *signal_name(int sig) {
    switch (sig) {
        case SIGABRT: return "SIGABRT";
        case SIGSEGV: return "SIGSEGV";
        case SIGBUS: return "SIGBUS";
        case SIGILL: return "SIGILL";
        case SIGFPE: return "SIGFPE";
        case SIGTRAP: return "SIGTRAP";
        default: return "SIG";
    }
}

static void resume_crash(int sig) {
    signal(sig, SIG_DFL);
    // The crashing signal is blocked while this handler runs. Unblock it so the
    // default action is delivered and MetricKit still sees the crash.
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, sig);
    sigprocmask(SIG_UNBLOCK, &set, NULL);
    raise(sig);
    _exit(128 + sig);
}

static void append_text(char *destination, int *used, int capacity, const char *text) {
    if (text == NULL) {
        return;
    }
    while (*text && *used < capacity - 1) {
        destination[*used] = *text;
        *used += 1;
        text += 1;
    }
    destination[*used] = '\0';
}

static void append_number(char *destination, int *used, int capacity, unsigned long long value) {
    char digits[32];
    int count = 0;
    if (value == 0) {
        digits[count++] = '0';
    }
    while (value > 0 && count < (int)sizeof(digits)) {
        digits[count++] = (char)('0' + (value % 10ULL));
        value /= 10ULL;
    }
    while (count > 0 && *used < capacity - 1) {
        count -= 1;
        destination[*used] = digits[count];
        *used += 1;
    }
    destination[*used] = '\0';
}

static int open_report(const char *prefix) {
    char path[1024];
    int used = 0;
    path[0] = '\0';
    append_text(path, &used, (int)sizeof(path), incomingDirectory);
    append_text(path, &used, (int)sizeof(path), prefix);
    append_text(path, &used, (int)sizeof(path), "-");
    append_number(path, &used, (int)sizeof(path), (unsigned long long)getpid());
    append_text(path, &used, (int)sizeof(path), "-");
    append_number(path, &used, (int)sizeof(path), (unsigned long long)time(NULL));
    append_text(path, &used, (int)sizeof(path), ".txt");
    return open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0644);
}

static void tellomi_signal(int sig) {
    if (handling) {
        resume_crash(sig);
        return;
    }
    handling = 1;
    int fd = open_report("/sig");
    if (fd >= 0) {
        write_text(fd, "source=signal\n");
        write_metadata(fd);
        write_text(fd, "time=");
        write_number(fd, (long long)time(NULL));
        write_text(fd, "\nsignal=");
        write_text(fd, signal_name(sig));
        write_text(fd, "\nstack:\n");
        void *frames[64];
        int count = backtrace(frames, 64);
        if (count > 0) {
            backtrace_symbols_fd(frames, count, fd);
        }
        fsync(fd);
        close(fd);
    }
    resume_crash(sig);
}

static void TellomiUncaughtException(NSException *exception) {
    if (!handling) {
        handling = 1;
        int fd = open_report("/exc");
        if (fd >= 0) {
            NSString *name = exception.name ?: @"NSException";
            NSString *reason = exception.reason ?: @"";
            name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
            reason = [[reason componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
            NSString *stack = [exception.callStackSymbols componentsJoinedByString:@"\n"] ?: @"";
            NSString *body = [NSString stringWithFormat:@"source=exception\napp=%s\nbuild=%s\nos=%s\ndevice=%s\narch=%s\ntime=%lld\nname=%@\nreason=%@\nstack:\n%@",
                appVersionField, buildVersionField, osVersionField, deviceTypeField, architectureField,
                (long long)time(NULL), name, reason, stack];
            NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
            if (data != nil) {
                write_all(fd, data.bytes, data.length);
            }
            fsync(fd);
            close(fd);
        }
    }
    if (previousExceptionHandler != NULL && previousExceptionHandler != TellomiUncaughtException) {
        previousExceptionHandler(exception);
    }
}

void TellomiInstallCrashHandlers(NSString *directoryPath, NSString *applicationVersion, NSString *buildVersion) {
    if (handlersInstalled) {
        return;
    }
    handlersInstalled = 1;
    [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    const char *directory = directoryPath.fileSystemRepresentation;
    if (directory != NULL) {
        strlcpy(incomingDirectory, directory, sizeof(incomingDirectory));
    }
    copy_field(appVersionField, sizeof(appVersionField), applicationVersion);
    copy_field(buildVersionField, sizeof(buildVersionField), buildVersion);

    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *os = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion];
    copy_field(osVersionField, sizeof(osVersionField), os);

    struct utsname systemInfo;
    NSString *device = @"unknown";
    if (uname(&systemInfo) == 0) {
        device = [NSString stringWithUTF8String:systemInfo.machine] ?: device;
    }
    copy_field(deviceTypeField, sizeof(deviceTypeField), device);

#if defined(__arm64__) || defined(__aarch64__)
    copy_field(architectureField, sizeof(architectureField), @"arm64");
#elif defined(__x86_64__)
    copy_field(architectureField, sizeof(architectureField), @"x86_64");
#else
    copy_field(architectureField, sizeof(architectureField), @"unknown");
#endif

    stack_t stack;
    stack.ss_sp = alternateStack;
    stack.ss_size = sizeof(alternateStack);
    stack.ss_flags = 0;
    sigaltstack(&stack, NULL);

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = tellomi_signal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_ONSTACK;
    int signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP };
    for (size_t index = 0; index < sizeof(signals) / sizeof(signals[0]); index++) {
        sigaction(signals[index], &action, NULL);
    }

    previousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&TellomiUncaughtException);
}
