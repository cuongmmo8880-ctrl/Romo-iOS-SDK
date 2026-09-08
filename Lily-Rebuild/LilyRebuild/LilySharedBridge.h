#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LilySharedBridge : NSObject
+ (BOOL)initializeSharedWithAPIKey:(NSString *)apiKey
                             wsURL:(NSString *)wsURL
                            otaURL:(NSString *)otaURL;
+ (nullable UIViewController *)mainViewController;
@end

NS_ASSUME_NONNULL_END
