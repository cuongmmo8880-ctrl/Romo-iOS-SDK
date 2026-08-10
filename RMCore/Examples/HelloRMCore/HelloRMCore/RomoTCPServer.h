#import <Foundation/Foundation.h>

@class RMCoreRobot;

@interface RomoTCPServer : NSObject

- (instancetype)initWithRobotProvider:(RMCoreRobot *(^)(void))robotProvider;
- (void)start;
- (void)stop;

@end
