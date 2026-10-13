#import "SKGreeting.h"

@implementation SKGreeting
+ (NSString *)greetingFor:(NSString *)name
{
  return [NSString stringWithFormat:@"Hello, %@", name];
}
@end
