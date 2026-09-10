#import "LilySharedBridge.h"
#import <objc/message.h>
#import <Romo/RMCore.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>
#import <objc/runtime.h>


static void LilyMCPWrite(NSString *line) {
    NSString *documents =
        NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory,
            NSUserDomainMask,
            YES
        ).firstObject;

    if (!documents) {
        return;
    }

    NSString *path =
        [documents stringByAppendingPathComponent:@"LilyMCPDump.txt"];

    NSString *text =
        [line stringByAppendingString:@"\n"];

    NSFileHandle *fh =
        [NSFileHandle fileHandleForWritingAtPath:path];

    if (!fh) {
        [[NSFileManager defaultManager]
            createFileAtPath:path
            contents:nil
            attributes:nil];

        fh =
            [NSFileHandle fileHandleForWritingAtPath:path];
    }

    if (!fh) {
        return;
    }

    [fh seekToEndOfFile];

    NSData *data =
        [text dataUsingEncoding:NSUTF8StringEncoding];

    if (data) {
        [fh writeData:data];
    }

    [fh closeFile];
}


static void LilyDumpMethods(NSString *className) {
    Class cls = NSClassFromString(className);

    NSString *header =
        [NSString stringWithFormat:@"========== MCP DUMP %@ ==========", className];

    NSLog(@"[Lily][MCP-DUMP] %@", header);
    LilyMCPWrite(header);

    NSString *classLine =
        [NSString stringWithFormat:@"CLASS %@ = %@", className, cls];

    NSLog(@"[Lily][MCP-DUMP] %@", classLine);
    LilyMCPWrite(classLine);

    if (!cls) {
        NSString *line =
            [NSString stringWithFormat:@"CLASS %@ NOT FOUND", className];

        NSLog(@"[Lily][MCP-DUMP] %@", line);
        LilyMCPWrite(line);
        return;
    }

    // ============================================================
    // INSTANCE METHODS
    // ============================================================

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);

    NSString *countLine =
        [NSString stringWithFormat:@"INSTANCE METHOD COUNT = %u", count];

    NSLog(@"[Lily][MCP-DUMP] %@", countLine);
    LilyMCPWrite(countLine);

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);

        NSString *selector =
            NSStringFromSelector(sel);

        NSString *line =
            [NSString stringWithFormat:
                @"INSTANCE %@ types=%s",
                selector,
                types ? types : ""];

        NSLog(@"[Lily][MCP-DUMP] %@", line);
        LilyMCPWrite(line);
    }

    free(methods);

    // ============================================================
    // CLASS METHODS
    // ============================================================

    Class meta = object_getClass(cls);
    count = 0;

    methods = class_copyMethodList(meta, &count);

    NSString *classCountLine =
        [NSString stringWithFormat:@"CLASS METHOD COUNT = %u", count];

    NSLog(@"[Lily][MCP-DUMP] %@", classCountLine);
    LilyMCPWrite(classCountLine);

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);

        NSString *selector =
            NSStringFromSelector(sel);

        NSString *line =
            [NSString stringWithFormat:
                @"CLASS %@ types=%s",
                selector,
                types ? types : ""];

        NSLog(@"[Lily][MCP-DUMP] %@", line);
        LilyMCPWrite(line);
    }

    free(methods);

    NSString *footer =
        [NSString stringWithFormat:@"========== END %@ ==========", className];

    NSLog(@"[Lily][MCP-DUMP] %@", footer);
    LilyMCPWrite(footer);
}


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
    [romo driveForwardWithSpeed:0.5];
    NSLog(@"[Lily][Romo] FORWARD -> driveForwardWithSpeed:0.5");
}

- (void)backward {
    RMCoreRobot<DriveProtocol> *romo = (RMCoreRobot<DriveProtocol> *)self.robot;
    if (!romo) { NSLog(@"[Lily][Romo] BACKWARD ignored: no robot"); return; }
    [romo driveBackwardWithSpeed:0.5];
    NSLog(@"[Lily][Romo] BACKWARD -> driveBackwardWithSpeed:0.5");
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

/* ============================================================
   Native Lily MCP -> Romo bridge
   ============================================================ */

static IMP gLilyOriginalAddTool = NULL;
static BOOL gLilyMCPHookInstalled = NO;
static IMP gLilyOriginalRegisterTools = NULL;
static BOOL gLilyRegisterHookInstalled = NO;


static id LilyRomoRemoteCallback(id arguments) {
    NSString *action = nil;

    if ([arguments isKindOfClass:[NSDictionary class]]) {
        id value = [(NSDictionary *)arguments objectForKey:@"action"];
        if ([value isKindOfClass:[NSString class]]) {
            action = (NSString *)value;
        }
    }

    if ([action length] > 0 &&
        ([action caseInsensitiveCompare:@"forward"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"go_forward"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"move_forward"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"tien len"] == NSOrderedSame)) {
        [[LilyRomoController sharedController] forward];
        return @"Romo moved forward";
    }

    if ([action length] > 0 &&
        ([action caseInsensitiveCompare:@"backward"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"back"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"reverse"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"move_backward"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"lui lai"] == NSOrderedSame)) {
        [[LilyRomoController sharedController] backward];
        return @"Romo moved backward";
    }

    if ([action length] > 0 &&
        ([action caseInsensitiveCompare:@"stop"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"halt"] == NSOrderedSame ||
        [action caseInsensitiveCompare:@"dung"] == NSOrderedSame)) {
        [[LilyRomoController sharedController] stopDriving];
        return @"Romo stopped";
    }

    return @"Romo action not recognized. Use action=forward, backward, or stop.";
}

static id LilyCreateRomoReplacementTool(id nativeTool) {
    if (!nativeTool) return nil;

    Class toolClass = NSClassFromString(@"SharedMcpTool");
    if (!toolClass) {
        NSLog(@"[Lily][MCP-ROMO] SharedMcpTool class not found");
        return nil;
    }

    SEL nameSel = NSSelectorFromString(@"name");
    SEL propertiesSel = NSSelectorFromString(@"properties");
    SEL userOnlySel = NSSelectorFromString(@"userOnly");
    SEL initSel = NSSelectorFromString(@"initWithName:description:properties:userOnly:callback:");

    if (![nativeTool respondsToSelector:nameSel] ||
        ![nativeTool respondsToSelector:propertiesSel] ||
        ![nativeTool respondsToSelector:userOnlySel] ||
        ![toolClass instancesRespondToSelector:initSel]) {
        NSLog(@"[Lily][MCP-ROMO] native self.remote.send shape not compatible");
        return nil;
    }

    typedef id (*GetObjectFn)(id, SEL);
    typedef BOOL (*GetBoolFn)(id, SEL);
    GetObjectFn getObject = (GetObjectFn)objc_msgSend;
    GetBoolFn getBool = (GetBoolFn)objc_msgSend;

    NSString *name = getObject(nativeTool, nameSel);
    id properties = getObject(nativeTool, propertiesSel);
    BOOL userOnly = getBool(nativeTool, userOnlySel);

    if (![name isKindOfClass:[NSString class]] ||
        [name length] == 0 ||
        ![name isEqualToString:@"self.remote.send"]) {
        return nil;
    }

    if (!properties) properties = @[];

    NSString *description =
        @"Control the Romo robot. Use device_name=Romo and action=forward, backward, or stop. "
         "When the user asks Romo to move forward, use action=forward. "
         "When the user asks Romo to move backward or reverse, use action=backward. "
         "When the user asks Romo to stop, use action=stop.";

    typedef id (*ToolInitFn)(id, SEL, id, id, id, BOOL, id);
    ToolInitFn initFn = (ToolInitFn)objc_msgSend;

    id replacement = initFn([toolClass alloc],
                             initSel,
                             name,
                             description,
                             properties,
                             userOnly,
                             ^id(id args) {
                                 return LilyRomoRemoteCallback(args);
                             });

    NSLog(@"[Lily][MCP-ROMO] native self.remote.send %@ with Romo callback", replacement ? @"replaced" : @"FAILED");
    return replacement;
}

static void LilyAddToolHook(id self, SEL _cmd, id tool) {
    if (!gLilyOriginalAddTool) return;

    id toolToAdd = tool;

    SEL nameSel = NSSelectorFromString(@"name");
    if (tool && [tool respondsToSelector:nameSel]) {
        typedef id (*GetObjectFn)(id, SEL);
        GetObjectFn getObject = (GetObjectFn)objc_msgSend;
        id name = getObject(tool, nameSel);

        if ([name isKindOfClass:[NSString class]] &&
            [(NSString *)name isEqualToString:@"self.remote.send"]) {
            LilyMCPWrite(@"MCP-ROMO ADD: self.remote.send");
            id replacement = LilyCreateRomoReplacementTool(tool);
            if (replacement) {
                toolToAdd = replacement;
                LilyMCPWrite(@"MCP-ROMO REPLACE: self.remote.send SUCCESS");
                NSLog(@"[Lily][MCP-ROMO] intercepted native tool self.remote.send");
            } else {
                LilyMCPWrite(@"MCP-ROMO REPLACE: self.remote.send FAILED");
            }
        }
    }

    typedef void (*AddToolFn)(id, SEL, id);
    AddToolFn original = (AddToolFn)gLilyOriginalAddTool;
    original(self, _cmd, toolToAdd);
}

static void LilyRegisterToolsHook(id self, SEL _cmd)
{
    LilyMCPWrite(@"MCP-ROMO REGISTER: ENTER");

    if (gLilyOriginalRegisterTools) {
        ((void (*)(id, SEL))gLilyOriginalRegisterTools)(self, _cmd);
    }

    LilyMCPWrite(@"MCP-ROMO REGISTER: EXIT");
}

static void LilyInstallMCPRomoHook(void) {
    if (gLilyMCPHookInstalled) return;

    Class serverClass = NSClassFromString(@"SharedMcpServer");
    SEL addToolSel = NSSelectorFromString(@"addToolTool:");

    if (!serverClass) {
        NSLog(@"[Lily][MCP-ROMO] SharedMcpServer class not found");
        LilyMCPWrite(@"MCP-ROMO INSTALL: SharedMcpServer NOT FOUND");
        return;
    }

    Method method = class_getInstanceMethod(serverClass, addToolSel);
    if (!method) {
        NSLog(@"[Lily][MCP-ROMO] SharedMcpServer addTool: method not found");
        LilyMCPWrite(@"MCP-ROMO INSTALL: addToolTool: NOT FOUND");
        return;
    }

    gLilyOriginalAddTool = method_getImplementation(method);
    method_setImplementation(method, (IMP)LilyAddToolHook);
    gLilyMCPHookInstalled = YES;

    LilyMCPWrite(@"MCP-ROMO INSTALL: HOOK INSTALLED addToolTool:");

    SEL registerToolsSel = NSSelectorFromString(@"registerTools");
    Method registerMethod = class_getInstanceMethod(serverClass, registerToolsSel);

    if (registerMethod) {
        gLilyOriginalRegisterTools =
            method_getImplementation(registerMethod);

        method_setImplementation(
            registerMethod,
            (IMP)LilyRegisterToolsHook
        );

        gLilyRegisterHookInstalled = YES;

        LilyMCPWrite(@"MCP-ROMO INSTALL: HOOK INSTALLED registerTools");
    } else {
        LilyMCPWrite(@"MCP-ROMO INSTALL: registerTools NOT FOUND");
    }

    NSLog(@"[Lily][MCP-ROMO] installed native addTool: hook");
}

@implementation LilySharedBridge

+ (BOOL)initializeSharedWithAPIKey:(NSString *)apiKey wsURL:(NSString *)wsURL otaURL:(NSString *)otaURL {
    Class cls = NSClassFromString(@"SharedIosModuleKt");
    if (!cls) return NO;

    SEL sel = NSSelectorFromString(@"doInitKoinApiEncryptionKey:wsUrl:otaUrl:");
    if (![cls respondsToSelector:sel]) return NO;

    LilyInstallMCPRomoHook();

    typedef void (*InitFn)(id, SEL, NSString *, NSString *, NSString *);
    InitFn fn = (InitFn)objc_msgSend;
    fn(cls, sel, apiKey, wsURL, otaURL);

    NSLog(@"[Lily] Shared Koin initialization invoked");    
    LilyDumpMethods(@"SharedMcpServer");
    LilyDumpMethods(@"SharedMcpServerCompanion");
    LilyDumpMethods(@"SharedMcpTool");
    LilyDumpMethods(@"SharedMcpToolInfo");
    LilyDumpMethods(@"SharedMcpToolRegistry");
    LilyDumpMethods(@"SharedSkillToolFactory");




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

