#import <Foundation/Foundation.h>

// The whole of the sample library: something an app and a test can call.
@interface SKGreeting : NSObject
+ (NSString *)greetingFor:(NSString *)name;
@end
