#import <UIKit/UIKit.h>

/// Application host for the list-reorder unit tests.
///
/// The PR runner otherwise starts them as a logic test ("the app under test is
/// not given"). In that process `CADisplayLink` comes back nil, and `ListView`
/// stores it in a non-optional implicit unwrap. A real `UIApplication` with a
/// key window is what the shipping app has when it creates the same link.
@interface ListViewReorderHostDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ListViewReorderHostDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    CGRect bounds = UIScreen.mainScreen.bounds;
    if (bounds.size.width < 1.0 || bounds.size.height < 1.0) {
        bounds = CGRectMake(0.0, 0.0, 390.0, 844.0);
    }
    UIWindow *window = [[UIWindow alloc] initWithFrame:bounds];
    window.rootViewController = [[UIViewController alloc] init];
    [window makeKeyAndVisible];
    self.window = window;
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([ListViewReorderHostDelegate class]));
    }
}
