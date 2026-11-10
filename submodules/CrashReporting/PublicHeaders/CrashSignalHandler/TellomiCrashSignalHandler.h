#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs a signal handler and an uncaught-exception handler. Both write a text file into
/// `directoryPath` and then resume the crash. Safe to call once, from the main thread, before login.
void TellomiInstallCrashHandlers(NSString *directoryPath, NSString *applicationVersion, NSString *buildVersion);

NS_ASSUME_NONNULL_END
