#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LilySharedBridge : NSObject
+ (BOOL)initializeSharedWithAPIKey:(NSString *)apiKey
                             wsURL:(NSString *)wsURL
                            otaURL:(NSString *)otaURL;
@end

NS_ASSUME_NONNULL_END
