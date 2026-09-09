#import "LilySharedBridge.h"
#import <objc/message.h>
#import <Romo/RMCore.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>

static const int kLilyRomoHTTPPort = 5000;

@interface LilyRomoController : NSObject <RMCoreDelegate>
@property (nonatomic, strong) RMCoreRobot *robot;
@property (nonatomic) int serverSocket;
@property (nonatomic) BOOL running;
@end

@implementation LilyRomoController

+ (instancetype)sharedController {
    static LilyRomoController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ controller = [[LilyRomoController alloc] init]; });
    return controller;
}

- (void)start {
    if (self.running) return;
    [RMCore allowBackground:YES];
    [RMCore setDelegate:self];

    for (RMCoreRobot *robot in [RMCore connectedRobots]) {
        if (robot.isDrivable) { self.robot = robot; break; }
    }

    self.running = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self serverLoop];
    });
    NSLog(@"[Lily][Romo] controller started on 127.0.0.1:%d", kLilyRomoHTTPPort);
}

- (void)robotDidConnect:(RMCoreRobot *)robot {
    if (robot.isDrivable) {
        self.robot = robot;
        NSLog(@"[Lily][Romo] robot connected: %@", robot);
    }
}

- (void)robotDidDisconnect:(RMCoreRobot *)robot {
    if (robot == self.robot) {
        self.robot = nil;
        NSLog(@"[Lily][Romo] robot disconnected");
    }
}

- (void)forward {
    RMCoreRobot<DriveProtocol> *romo = (RMCoreRobot<DriveProtocol> *)self.robot;
    if (!romo) { NSLog(@"[Lily][Romo] FORWARD ignored: no robot"); return; }
    [romo driveWithPower:0.5];
    NSLog(@"[Lily][Romo] FORWARD -> driveWithPower:+0.5");
}

- (void)backward {
    RMCoreRobot<DriveProtocol> *romo = (RMCoreRobot<DriveProtocol> *)self.robot;
    if (!romo) { NSLog(@"[Lily][Romo] BACKWARD ignored: no robot"); return; }
    [romo driveWithPower:-0.5];
    NSLog(@"[Lily][Romo] BACKWARD -> driveWithPower:-0.5");
}

- (void)stopDriving {
    RMCoreRobot<DriveProtocol> *romo = (RMCoreRobot<DriveProtocol> *)self.robot;
    if (romo) [romo stopDriving];
}

- (void)sendHTTPResponse:(int)clientSocket status:(const char *)status body:(NSString *)body {
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 %s\r\nContent-Type: application/json; charset=utf-8\r\n"
         "Content-Length: %lu\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n%@",
        status, (unsigned long)bodyData.length, body];
    NSData *responseData = [response dataUsingEncoding:NSUTF8StringEncoding];
    send(clientSocket, responseData.bytes, responseData.length, 0);
}

- (void)handleHTTPClient:(int)clientSocket {
    char buffer[2048];
    ssize_t count = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
    if (count <= 0) return;
    buffer[count] = '\0';

    NSString *request = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)count encoding:NSUTF8StringEncoding];
    NSString *firstLine = [[request componentsSeparatedByString:@"\r\n"] firstObject];
    NSArray *parts = [firstLine componentsSeparatedByString:@" "];
    NSString *path = parts.count >= 2 ? parts[1] : @"";

    if ([path isEqualToString:@"/romo/forward"]) {
        [self forward];
        [self sendHTTPResponse:clientSocket status:"200 OK" body:@"{\"ok\":true,\"action\":\"forward\"}"];
    } else if ([path isEqualToString:@"/romo/backward"]) {
        [self backward];
        [self sendHTTPResponse:clientSocket status:"200 OK" body:@"{\"ok\":true,\"action\":\"backward\"}"];
    } else if ([path isEqualToString:@"/romo/stop"]) {
        [self stopDriving];
        [self sendHTTPResponse:clientSocket status:"200 OK" body:@"{\"ok\":true,\"action\":\"stop\"}"];
    } else if ([path isEqualToString:@"/romo/status"]) {
        NSString *body = [NSString stringWithFormat:@"{\"connected\":%@}", self.robot ? @"true" : @"false"];
        [self sendHTTPResponse:clientSocket status:"200 OK" body:body];
    } else {
        [self sendHTTPResponse:clientSocket status:"404 Not Found" body:@"{\"ok\":false,\"error\":\"unknown path\"}"];
    }
}

- (void)serverLoop {
    self.serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (self.serverSocket < 0) { self.running = NO; return; }

    int yes = 1;
    setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(kLilyRomoHTTPPort);

    if (bind(self.serverSocket, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        listen(self.serverSocket, 4) < 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
        self.running = NO;
        return;
    }

    while (self.running) {
        int clientSocket = accept(self.serverSocket, NULL, NULL);
        if (clientSocket < 0) continue;
        [self handleHTTPClient:clientSocket];
        shutdown(clientSocket, SHUT_RDWR);
        close(clientSocket);
    }
}

@end

@implementation LilySharedBridge

+ (BOOL)initializeSharedWithAPIKey:(NSString *)apiKey wsURL:(NSString *)wsURL otaURL:(NSString *)otaURL {
    Class cls = NSClassFromString(@"SharedIosModuleKt");
    if (!cls) return NO;

    SEL sel = NSSelectorFromString(@"doInitKoinApiEncryptionKey:wsUrl:otaUrl:");
    if (![cls respondsToSelector:sel]) return NO;

    typedef void (*InitFn)(id, SEL, NSString *, NSString *, NSString *);
    InitFn fn = (InitFn)objc_msgSend;
    fn(cls, sel, apiKey, wsURL, otaURL);

    NSLog(@"[Lily] Shared Koin initialization invoked");
    [[LilyRomoController sharedController] start];
    return YES;
}

+ (UIViewController *)mainViewController {
    Class cls = NSClassFromString(@"SharedAppKt");
    if (!cls) return nil;

    SEL sel = NSSelectorFromString(@"MainViewController");
    if (![cls respondsToSelector:sel]) return nil;

    typedef UIViewController *(*MainFn)(id, SEL);
    MainFn fn = (MainFn)objc_msgSend;
    return fn(cls, sel);
}

@end
