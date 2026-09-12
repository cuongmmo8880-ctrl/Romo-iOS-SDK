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
#import <pthread.h>


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
   Native Lily MCP -> Romo bridge — BUILD #48

   Correct lifecycle:
       WebsocketProtocol.openAudioChannel
           -> new McpServer
           -> registerTools()
           -> RETURN
           -> inject Romo tools into the LIVE server
           -> later tools/list reads server + 0x70

   We deliberately DO NOT hook McpServer#addTool(). Build #47 proved that
   injecting synchronously from inside addTool() can corrupt/invalidly re-enter
   Kotlin/Native collection/runtime dispatch. The safe boundary is the native
   registerTools() return.

   Confirmed native target in this exact Shared binary:
       Shared + 0x126B040 = McpServer#registerTools()
       x0 = live McpServer
       return = Unit / void

   First 16 bytes are:
       stp d9,d8,[sp,#-0x70]!
       stp x28,x27,[sp,#0x10]
       stp x26,x25,[sp,#0x20]
       stp x24,x23,[sp,#0x30]
   No PC-relative instruction occurs in this relocated prologue.
   ============================================================ */

static BOOL gLilyMCPHookInstalled = NO;
static BOOL gLilyNativeRegisterToolsPatchInstalled = NO;
static uintptr_t gLilyNativeRegisterToolsAddress = 0;
static uintptr_t gLilyNativeRegisterToolsTrampoline = 0;
static uint8_t gLilyOriginalRegisterToolsBytes[16];
static uintptr_t gLilyNativeAddToolAddress = 0;
static void *gLilyRomoInjectedServer = NULL;
static pthread_mutex_t gLilyNativeHookLock = PTHREAD_MUTEX_INITIALIZER;

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
    if (!toolClass) {
        LilyMCPWrite(@"MCP-ROMO #48 TOOL: SharedMcpTool NOT FOUND");
        return nil;
    }

    SEL initSel = NSSelectorFromString(
        @"initWithName:description:properties:userOnly:callback:");

    if (![toolClass instancesRespondToSelector:initSel]) {
        LilyMCPWrite(@"MCP-ROMO #48 TOOL: initializer NOT FOUND");
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
        @"MCP-ROMO #48 TOOL: %@ %@", name,
        tool ? @"CREATED" : @"FAILED"]);
    return tool;
}

typedef void (*LilyMcpAddToolFn)(void *server, void *tool);
typedef void (*LilyMcpRegisterToolsFn)(void *server);

/* Direct native addTool call. addTool itself is NOT patched in build #48. */
static void LilyAddRomoToolDirect(void *server, void *tool) {
    if (!server || !tool || !gLilyNativeAddToolAddress) {
        LilyMCPWrite(@"MCP-ROMO #48 ADDTOOL: missing server/tool/address");
        return;
    }
    ((LilyMcpAddToolFn)gLilyNativeAddToolAddress)(server, tool);
}

static void LilyInjectRobotToolsIntoServer(void *server) {
    if (!server) return;

    if (gLilyRomoInjectedServer == server) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO #48 INJECT: already injected server=%p", server]);
        return;
    }

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO #48 INJECT ENTER live McpServer=%p", server]);

    id forwardTool = LilyCreateSimpleRomoTool(
        @"robot.forward",
        @"Move the physical Romo robot connected to Lily forward. Use this when the user asks Romo to move forward, go forward, drive forward, or tien len.",
        ^id(id args) {
            (void)args;
            LilyRomoForwardNoArgs();
            return @"Romo moved forward";
        });

    id backwardTool = LilyCreateSimpleRomoTool(
        @"robot.backward",
        @"Move the physical Romo robot connected to Lily backward. Use this when the user asks Romo to move backward, reverse, or lui lai.",
        ^id(id args) {
            (void)args;
            LilyRomoBackwardNoArgs();
            return @"Romo moved backward";
        });

    id stopTool = LilyCreateSimpleRomoTool(
        @"robot.stop",
        @"Stop the physical Romo robot connected to Lily immediately.",
        ^id(id args) {
            (void)args;
            LilyRomoStopNoArgs();
            return @"Romo stopped";
        });

    if (forwardTool)  LilyAddRomoToolDirect(server, (__bridge void *)forwardTool);
    if (backwardTool) LilyAddRomoToolDirect(server, (__bridge void *)backwardTool);
    if (stopTool)     LilyAddRomoToolDirect(server, (__bridge void *)stopTool);

    /* Mark only after all three native addTool calls have returned. */
    gLilyRomoInjectedServer = server;
    LilyMCPWrite(@"MCP-ROMO #48 INJECT RETURNED: robot.forward / robot.backward / robot.stop");
}

static BOOL LilyProtectCodePage(void *address, BOOL writable) {
    vm_address_t page = (vm_address_t)address & ~(vm_address_t)(vm_page_size - 1);
    vm_prot_t prot = writable
        ? (VM_PROT_READ | VM_PROT_WRITE)
        : (VM_PROT_READ | VM_PROT_EXECUTE);

    kern_return_t kr = vm_protect(mach_task_self(), page, vm_page_size,
                                  FALSE, prot);
    if (kr != KERN_SUCCESS) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO #48 PATCH: vm_protect failed kr=%d", kr]);
        return NO;
    }
    return YES;
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

static BOOL LilyWriteBranch(void *address, uintptr_t destination) {
    uintptr_t source = (uintptr_t)address;
    int64_t delta = (int64_t)destination - (int64_t)source;

    if ((delta & 0x3) != 0 || delta < -(128LL * 1024 * 1024) ||
        delta >= (128LL * 1024 * 1024)) {
        LilyMCPWrite(@"MCP-ROMO #48 PATCH: hook outside AArch64 B range");
        return NO;
    }

    int64_t imm26 = delta >> 2;
    uint32_t instruction = 0x14000000u |
        ((uint32_t)imm26 & 0x03ffffffu);

    if (!LilyProtectCodePage(address, YES)) return NO;
    memcpy(address, &instruction, sizeof(instruction));
    sys_icache_invalidate(address, sizeof(instruction));
    return LilyProtectCodePage(address, NO);
}

static BOOL LilyAllocateRegisterToolsTrampoline(uintptr_t target) {
    if (gLilyNativeRegisterToolsTrampoline) return YES;

    vm_address_t page = 0;
    kern_return_t kr = vm_allocate(mach_task_self(), &page, vm_page_size,
                                   VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO #48 PATCH: vm_allocate trampoline failed kr=%d", kr]);
        return NO;
    }

    kr = vm_protect(mach_task_self(), page, vm_page_size, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), page, vm_page_size);
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO #48 PATCH: trampoline RW protect failed kr=%d", kr]);
        return NO;
    }

    memcpy((void *)page, (void *)target,
           sizeof(gLilyOriginalRegisterToolsBytes));

    uint8_t *jumpAt = (uint8_t *)page + sizeof(gLilyOriginalRegisterToolsBytes);
    uint32_t jump[2] = { 0x58000050, 0xD61F0200 }; /* ldr x16,#8; br x16 */
    uint64_t continuation = (uint64_t)(target +
                                       sizeof(gLilyOriginalRegisterToolsBytes));
    memcpy(jumpAt, jump, sizeof(jump));
    memcpy(jumpAt + 8, &continuation, sizeof(continuation));
    sys_icache_invalidate((void *)page, 32);

    kr = vm_protect(mach_task_self(), page, vm_page_size, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), page, vm_page_size);
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO #48 PATCH: trampoline RX protect failed kr=%d", kr]);
        return NO;
    }

    gLilyNativeRegisterToolsTrampoline = (uintptr_t)page;
    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO #48 PATCH: registerTools trampoline=%p continue=0x%llx",
        (void *)page,
        (unsigned long long)(target + sizeof(gLilyOriginalRegisterToolsBytes))]);
    return YES;
}

static void LilyNativeRegisterToolsHook(void *server);

static BOOL LilyPatchNativeRegisterTools(void) {
    pthread_mutex_lock(&gLilyNativeHookLock);

    if (gLilyNativeRegisterToolsPatchInstalled) {
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return YES;
    }

    uintptr_t slide = LilyFindSharedImageSlide();
    if (!slide) {
        LilyMCPWrite(@"MCP-ROMO #48 PATCH: Shared.framework slide NOT FOUND");
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    /* Exact offsets from the current Shared binary. */
    uintptr_t registerTarget = slide + 0x126B040;
    uintptr_t addToolTarget  = slide + 0x126CC88;

    memcpy(gLilyOriginalRegisterToolsBytes, (void *)registerTarget, 16);

    const uint8_t expected[16] = {
        0xe9, 0x23, 0xb9, 0x6d,
        0xfc, 0x6f, 0x01, 0xa9,
        0xfa, 0x67, 0x02, 0xa9,
        0xf8, 0x5f, 0x03, 0xa9
    };

    if (memcmp(gLilyOriginalRegisterToolsBytes, expected, 16) != 0) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO #48 PATCH: registerTools prologue mismatch @ 0x%llx",
            (unsigned long long)registerTarget]);
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    /* addTool remains completely unpatched; only remember its native address. */
    gLilyNativeAddToolAddress = addToolTarget;

    if (!LilyAllocateRegisterToolsTrampoline(registerTarget)) {
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    if (!LilyWriteBranch((void *)registerTarget,
                         (uintptr_t)&LilyNativeRegisterToolsHook)) {
        vm_deallocate(mach_task_self(),
                      (vm_address_t)gLilyNativeRegisterToolsTrampoline,
                      vm_page_size);
        gLilyNativeRegisterToolsTrampoline = 0;
        gLilyNativeAddToolAddress = 0;
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    gLilyNativeRegisterToolsAddress = registerTarget;
    gLilyNativeRegisterToolsPatchInstalled = YES;

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO #48 PATCH ENABLED registerTools @ 0x%llx addTool @ 0x%llx -> %p",
        (unsigned long long)registerTarget,
        (unsigned long long)addToolTarget,
        (void *)&LilyNativeRegisterToolsHook]);

    pthread_mutex_unlock(&gLilyNativeHookLock);
    return YES;
}

static void LilyNativeRegisterToolsHook(void *server) {
    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO #48 REGISTER ENTER server=%p", server]);

    uintptr_t trampoline = gLilyNativeRegisterToolsTrampoline;
    if (!trampoline) {
        LilyMCPWrite(@"MCP-ROMO #48 ERROR: registerTools trampoline NULL");
        return;
    }

    /* FIRST: let Lily complete every built-in/custom registration normally. */
    ((LilyMcpRegisterToolsFn)trampoline)(server);

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO #48 REGISTER RETURN server=%p", server]);

    /* SECOND: inject only after registerTools has fully returned. */
    if (server) {
        LilyInjectRobotToolsIntoServer(server);
    }

    LilyMCPWrite(@"MCP-ROMO #48 REGISTER HOOK DONE");
}

static void LilyInstallMCPRomoHook(void) {
    gLilyMCPHookInstalled = LilyPatchNativeRegisterTools();
    LilyMCPWrite(gLilyMCPHookInstalled
        ? @"MCP-ROMO PATCH: ENABLED FOR BUILD #48 (native registerTools post-return)"
        : @"MCP-ROMO PATCH: FAILED FOR BUILD #48");
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

    /*
     * BUILD #44 DIAGNOSTIC:
     * Keep Koin initialization, Romo startup, and MCP reflection dumps ON.
     * Native addTool patch is enabled, but the hook only logs and returns.
     */
    [[LilyRomoController sharedController] start];

    LilyDumpMethods(@"SharedMcpServer");
    LilyDumpMethods(@"SharedMcpServerCompanion");
    LilyDumpMethods(@"SharedMcpTool");
    LilyDumpMethods(@"SharedMcpToolInfo");
    LilyDumpMethods(@"SharedMcpToolRegistry");
    LilyDumpMethods(@"SharedSkillToolFactory");
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

