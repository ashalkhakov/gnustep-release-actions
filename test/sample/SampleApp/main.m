// The sample application, the same source on GNUstep and macOS: a window with
// a greeting. With --self-test it shows the window, checks it, and exits 0.
#import <AppKit/AppKit.h>
#import "SKGreeting.h"

@interface SADelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property BOOL selfTest;
@end

@implementation SADelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 320, 120)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                              backing:NSBackingStoreBuffered defer:NO];
  self.window.title = @"Sample";
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 280, 24)];
  label.stringValue = [SKGreeting greetingFor:@"world"];
  label.editable = NO;
  [self.window.contentView addSubview:label];
  [self.window makeKeyAndOrderFront:nil];
  if (self.selfTest) {
    BOOL ok = [label.stringValue isEqualToString:@"Hello, world"] && self.window.isVisible;
    printf("self-test: %s\n", ok ? "passed" : "FAILED");
    exit(ok ? 0 : 1);
  }
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end

int main(int argc, const char **argv)
{
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    SADelegate *delegate = [SADelegate new];
    delegate.selfTest = [[NSProcessInfo processInfo].arguments containsObject:@"--self-test"];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
