// make check: the library does what it says.
#import <Foundation/Foundation.h>
#import "SKGreeting.h"

int main(void)
{
  @autoreleasepool {
    NSString *greeting = [SKGreeting greetingFor:@"sample"];
    if (![greeting isEqualToString:@"Hello, sample"]) {
      fprintf(stderr, "check: FAIL: %s\n", greeting.UTF8String);
      return 1;
    }
    printf("check: passed\n");
  }
  return 0;
}
