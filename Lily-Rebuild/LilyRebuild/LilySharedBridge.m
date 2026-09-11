#import "LilySharedBridge.h"
#import <objc/message.h>
#import <Romo/RMCore.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>
#import <objc/runtime.h>
#import <libkern/OSCacheControl.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>


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

static BOOL gLilyMCPHookInstalled = NO;
static BOOL gLilyNativeRegisterPatchInstalled = NO;
static uintptr_t gLilyNativeRegisterAddress = 0;
static uint8_t gLilyOriginalRegisterBytes[16];

static void LilyRomoForwardNoArgs(void) {
    [[LilyRomoController sharedController] forward];
}

static void LilyRomoBackwardNoArgs(void) {
    [[LilyRomoController sharedController] backward];
}

static void LilyRomoStopNoArgs(void) {
    [[LilyRomoController sharedController] stopDriving];
}

static id LilyCreateSimpleRomoTool(NSString *name,
                                   NSString *description,
                                   id (^callback)(id)) {
    Class toolClass = NSClassFromString(@"SharedMcpTool");
    if (!toolClass) return nil;

    SEL initSel = NSSelectorFromString(
        @"initWithName:description:properties:userOnly:callback:"
    );

    if (![toolClass instancesRespondToSelector:initSel]) {
        LilyMCPWrite(@"MCP-ROMO TOOL: SharedMcpTool initializer NOT FOUND");
        return nil;
    }

    typedef id (*ToolInitFn)(id, SEL, id, id, id, BOOL, id);
    ToolInitFn initFn = (ToolInitFn)objc_msgSend;

    id tool = initFn([toolClass alloc],
                     initSel,
                     name,
                     description,
                     @[],
                     NO,
                     callback);

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO TOOL: %@ %@",
        name,
        tool ? @"CREATED" : @"FAILED"]);

    return tool;
}

static void LilyInjectRobotToolsIntoServer(id server) {
    if (!server) return;

    SEL addToolSel = NSSelectorFromString(@"addToolTool:");
    if (![server respondsToSelector:addToolSel]) {
        LilyMCPWrite(@"MCP-ROMO INJECT: addToolTool: NOT FOUND");
        return;
    }

    id forwardTool = LilyCreateSimpleRomoTool(
        @"robot.forward",
        @"Move the physical robot connected to Lily forward. Use this when the user asks the robot to move forward, go forward, or tien len.",
        ^id(id args) {
            (void)args;
            LilyRomoForwardNoArgs();
            return @"Robot moved forward";
        });

    id backwardTool = LilyCreateSimpleRomoTool(
        @"robot.backward",
        @"Move the physical robot connected to Lily backward. Use this when the user asks the robot to move backward, reverse, or lui lai.",
        ^id(id args) {
            (void)args;
            LilyRomoBackwardNoArgs();
            return @"Robot moved backward";
        });

    id stopTool = LilyCreateSimpleRomoTool(
        @"robot.stop",
        @"Stop the physical robot connected to Lily immediately.",
        ^id(id args) {
            (void)args;
            LilyRomoStopNoArgs();
            return @"Robot stopped";
        });

    typedef void (*AddToolFn)(id, SEL, id);
    AddToolFn addFn = (AddToolFn)objc_msgSend;

    if (forwardTool)  addFn(server, addToolSel, forwardTool);
    if (backwardTool) addFn(server, addToolSel, backwardTool);
    if (stopTool)     addFn(server, addToolSel, stopTool);

    LilyMCPWrite(@"MCP-ROMO INJECT: robot.forward / robot.backward / robot.stop ADDED");
}

static void LilyProtectCodePage(void *address, BOOL writable) {
    vm_address_t page = (vm_address_t)address & ~(vm_address_t)(vm_page_size - 1);
    vm_prot_t prot = writable ? (VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)
                              : (VM_PROT_READ | VM_PROT_EXECUTE);
    vm_protect(mach_task_self(), page, vm_page_size, FALSE, prot);
}

static uintptr_t LilyFindSharedImageSlide(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, @"Shared.framework/Shared".UTF8String)) {
            return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

static void LilyNativeRegisterToolsHook(void *server);

static void LilyPatchNativeRegisterTools(void) {
    if (gLilyNativeRegisterPatchInstalled) return;

    /*
     * Confirmed from the current Shared binary forensic map:
     * McpServer#registerTools() VA = 0x126b040.
     * The call is Kotlin/Native direct and bypasses ObjC swizzling.
     */
    uintptr_t slide = LilyFindSharedImageSlide();
    if (!slide) {
        LilyMCPWrite(@"MCP-ROMO PATCH: Shared.framework slide NOT FOUND");
        return;
    }

    uintptr_t target = slide + 0x126b040;
    memcpy(gLilyOriginalRegisterBytes, (void *)target, sizeof(gLilyOriginalRegisterBytes));

    uint32_t *code = (uint32_t *)gLilyOriginalRegisterBytes;
    (void)code;

    uint32_t jump[2] = { 0x58000050, 0xD61F0200 };
    uint64_t hookAddress = (uint64_t)(uintptr_t)&LilyNativeRegisterToolsHook;

    LilyProtectCodePage((void *)target, YES);
    memcpy((void *)target, jump, sizeof(jump));
    memcpy((void *)(target + 8), &hookAddress, sizeof(hookAddress));
    sys_icache_invalidate((void *)target, 16);
    LilyProtectCodePage((void *)target, NO);

    gLilyNativeRegisterAddress = target;
    gLilyNativeRegisterPatchInstalled = YES;

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO PATCH: native registerTools PATCHED @ 0x%llx",
        (unsigned long long)target]);
}

static void LilyNativeRegisterToolsHook(void *server) {
    if (!gLilyNativeRegisterAddress) return;

    /* Restore the original first 16 bytes, call the real native function,
       then reinstall the branch. registerTools is normally executed once
       per McpServer creation, so this keeps the patch simple and local. */
    LilyProtectCodePage((void *)gLilyNativeRegisterAddress, YES);
    memcpy((void *)gLilyNativeRegisterAddress,
           gLilyOriginalRegisterBytes,
           sizeof(gLilyOriginalRegisterBytes));
    sys_icache_invalidate((void *)gLilyNativeRegisterAddress, 16);
    LilyProtectCodePage((void *)gLilyNativeRegisterAddress, NO);

    typedef void (*RegisterToolsFn)(void *);
    RegisterToolsFn original = (RegisterToolsFn)gLilyNativeRegisterAddress;
    original(server);

    LilyInjectRobotToolsIntoServer((__bridge id)server);

    uint32_t jump[2] = { 0x58000050, 0xD61F0200 };
    uint64_t hookAddress = (uint64_t)(uintptr_t)&LilyNativeRegisterToolsHook;

    LilyProtectCodePage((void *)gLilyNativeRegisterAddress, YES);
    memcpy((void *)gLilyNativeRegisterAddress, jump, sizeof(jump));
    memcpy((void *)(gLilyNativeRegisterAddress + 8), &hookAddress, sizeof(hookAddress));
    sys_icache_invalidate((void *)gLilyNativeRegisterAddress, 16);
    LilyProtectCodePage((void *)gLilyNativeRegisterAddress, NO);

    LilyMCPWrite(@"MCP-ROMO PATCH: native registerTools completed + Romo tools injected");
}

static void LilyInstallMCPRomoHook(void) {
    if (gLilyMCPHookInstalled) return;

    LilyPatchNativeRegisterTools();

    /* Keep the old ObjC method discovery as diagnostics only. The actual
       native call path is patched above because Kotlin/Native direct calls
       bypass method_setImplementation(). */
    Class serverClass = NSClassFromString(@"SharedMcpServer");
    if (serverClass) {
        Method method = class_getInstanceMethod(
            serverClass,
            NSSelectorFromString(@"addToolTool:")
        );
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO DIAG: SharedMcpServer addToolTool: %@",
            method ? @"FOUND" : @"NOT FOUND"]);
    }

    gLilyMCPHookInstalled = YES;
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

