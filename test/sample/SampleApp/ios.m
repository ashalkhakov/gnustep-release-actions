// The sample application on iOS: a window with the greeting.
#import <UIKit/UIKit.h>
#import "SKGreeting.h"

@interface SAAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SAAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UIViewController *root = [UIViewController new];
  UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 280, 30)];
  label.text = [SKGreeting greetingFor:@"world"];
  [root.view addSubview:label];
  root.view.backgroundColor = UIColor.systemBackgroundColor;
  self.window.rootViewController = root;
  [self.window makeKeyAndVisible];
  return YES;
}
@end

int main(int argc, char *argv[])
{
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([SAAppDelegate class]));
  }
}
