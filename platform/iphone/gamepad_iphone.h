#import <GameController/GameController.h>

@class AppDelegate;

@interface GamepadManager : NSObject

@property(nonatomic, getter=isReady) BOOL ready;

+ (instancetype)sharedManager;

@end