#import <UIKit/UIKit.h>

/// Application host for the list-reorder unit tests.
///
/// xctestrunner waits for the literal "Test Suite" before it considers XCTest
/// started. On head 37990d7418 both targets compiled, then xcodebuild printed
/// "Testing started" and never "Test Suite" (exit 12, three attempts). That
/// host created its window with initWithFrame: inside didFinishLaunching. The
/// window is now attached to the scene xcodebuild connects, and the same
/// object is stored on the delegate so the tests can read it.
@interface ListViewReorderHostDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@interface ListViewReorderHostSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ListViewReorderHostDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

@end

@implementation ListViewReorderHostSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [[UIViewController alloc] init];
    [window makeKeyAndVisible];
    self.window = window;
    ListViewReorderHostDelegate *delegate = (ListViewReorderHostDelegate *)UIApplication.sharedApplication.delegate;
    if ([delegate isKindOfClass:[ListViewReorderHostDelegate class]]) {
        delegate.window = window;
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ListViewReorderHostDelegate class]));
    }
}
