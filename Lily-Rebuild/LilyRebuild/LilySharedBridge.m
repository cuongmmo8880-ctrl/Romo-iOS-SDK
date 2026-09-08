#import "LilySharedBridge.h"
#import <objc/message.h>

@implementation LilySharedBridge

+ (BOOL)initializeSharedWithAPIKey:(NSString *)apiKey
                             wsURL:(NSString *)wsURL
                            otaURL:(NSString *)otaURL
{
    Class cls = NSClassFromString(@"SharedIosModuleKt");
    if (!cls) {
        NSLog(@"[Lily] SharedIosModuleKt not found");
        return NO;
    }

    SEL sel = NSSelectorFromString(@"doInitKoinApiEncryptionKey:wsUrl:otaUrl:");
    if (![cls respondsToSelector:sel]) {
        NSLog(@"[Lily] selector %@ not found", NSStringFromSelector(sel));
        return NO;
    }

    typedef void (*InitFn)(id, SEL, NSString *, NSString *, NSString *);
    InitFn fn = (InitFn)objc_msgSend;
    fn(cls, sel, apiKey, wsURL, otaURL);
    NSLog(@"[Lily] Shared Koin initialization invoked");
    return YES;
}

+ (UIViewController *)mainViewController
{
    Class cls = NSClassFromString(@"SharedAppKt");
    if (!cls) {
        NSLog(@"[Lily] SharedAppKt not found");
        return nil;
    }

    SEL sel = NSSelectorFromString(@"MainViewController");
    if (![cls respondsToSelector:sel]) {
        NSLog(@"[Lily] MainViewController selector not found");
        return nil;
    }

    typedef UIViewController *(*MainFn)(id, SEL);
    MainFn fn = (MainFn)objc_msgSend;
    UIViewController *vc = fn(cls, sel);
    NSLog(@"[Lily] MainViewController returned: %@", vc);
    return vc;
}

@end
