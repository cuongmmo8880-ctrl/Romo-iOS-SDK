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
   Native Lily MCP -> Romo bridge

   IMPORTANT:
   Kotlin/Native calls McpServer#addTool directly, so ObjC method
   swizzling does not intercept the real registration path.

   Confirmed native target in the current Shared binary:
       Shared + 0x126CC88 = McpServer#addTool(McpTool)
       x0 = live McpServer
       x1 = McpTool
       return = Unit / void

   The first 16 bytes are relocated/restored exactly while the original
   function executes. We do NOT hook registerTools or addToolTool:.
   ============================================================ */

static BOOL gLilyMCPHookInstalled = NO;
static BOOL gLilyNativeAddToolPatchInstalled = NO;
static uintptr_t gLilyNativeAddToolAddress = 0;
static uintptr_t gLilyNativeAddToolTrampoline = 0;
static uint8_t gLilyOriginalAddToolBytes[16];
static void *gLilyRomoInjectedServer = NULL;
static pthread_mutex_t gLilyNativeHookLock = PTHREAD_MUTEX_INITIALIZER;
static __thread int gLilyNativeHookDepth = 0;

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
        LilyMCPWrite(@"MCP-ROMO TOOL: SharedMcpTool NOT FOUND");
        return nil;
    }

    SEL initSel = NSSelectorFromString(
        @"initWithName:description:properties:userOnly:callback:");

    if (![toolClass instancesRespondToSelector:initSel]) {
        LilyMCPWrite(@"MCP-ROMO TOOL: initializer NOT FOUND");
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

/*
 * Native McpServer#addTool has ABI:
 *     void addTool(void *server, void *tool)
 *
 * Calling this function pointer directly avoids ObjC dispatch and therefore
 * avoids the exact registerTools/addToolTool: problem we already proved.
 */
typedef void (*LilyMcpAddToolFn)(void *server, void *tool);

static void LilyAddRomoToolDirect(void *server, void *tool) {
    if (!server || !tool || !gLilyNativeAddToolAddress) return;
    LilyMcpAddToolFn original = (LilyMcpAddToolFn)gLilyNativeAddToolTrampoline;
    original(server, tool);
}

static void LilyInjectRobotToolsIntoServer(void *server) {
    if (!server) return;

    /* One injection per live McpServer instance. */
    if (gLilyRomoInjectedServer == server) {
        return;
    }
    gLilyRomoInjectedServer = server;

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO INJECT: live McpServer=%p",
        server]);

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

    if (forwardTool) {
        LilyAddRomoToolDirect(server, (__bridge void *)forwardTool);
    }
    if (backwardTool) {
        LilyAddRomoToolDirect(server, (__bridge void *)backwardTool);
    }
    if (stopTool) {
        LilyAddRomoToolDirect(server, (__bridge void *)stopTool);
    }

    LilyMCPWrite(@"MCP-ROMO INJECT: robot.forward / robot.backward / robot.stop ADDED via native addTool");
}

static BOOL LilyProtectCodePage(void *address, BOOL writable) {
    vm_address_t page = (vm_address_t)address & ~(vm_address_t)(vm_page_size - 1);
    vm_prot_t prot = writable
        ? (VM_PROT_READ | VM_PROT_WRITE)
        : (VM_PROT_READ | VM_PROT_EXECUTE);

    kern_return_t kr = vm_protect(mach_task_self(),
                                  page,
                                  vm_page_size,
                                  FALSE,
                                  prot);
    if (kr != KERN_SUCCESS) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO PATCH: vm_protect failed kr=%d", kr]);
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

static BOOL LilyWriteAbsoluteJump(void *address, uintptr_t destination) {
    /*
     * ARM64 absolute jump, 16 bytes:
     *   ldr x16, #8
     *   br  x16
     *   .quad destination
     */
    uint32_t jump[2] = { 0x58000050, 0xD61F0200 };

    if (!LilyProtectCodePage(address, YES)) {
        return NO;
    }

    memcpy(address, jump, sizeof(jump));
    memcpy((uint8_t *)address + 8, &destination, sizeof(destination));
    sys_icache_invalidate(address, 16);

    return LilyProtectCodePage(address, NO);
}

static BOOL LilyWriteBranch(void *address, uintptr_t destination) {
    uintptr_t source = (uintptr_t)address;
    int64_t delta = (int64_t)destination - (int64_t)source;

    /* AArch64 B has a signed 26-bit immediate scaled by 4: +/-128 MiB. */
    if ((delta & 0x3) != 0 || delta < -(128LL * 1024 * 1024) ||
        delta >= (128LL * 1024 * 1024)) {
        return NO;
    }

    int64_t imm26 = delta >> 2;
    uint32_t instruction = 0x14000000u | ((uint32_t)imm26 & 0x03ffffffu);

    if (!LilyProtectCodePage(address, YES)) {
        return NO;
    }

    memcpy(address, &instruction, sizeof(instruction));
    sys_icache_invalidate(address, sizeof(instruction));

    return LilyProtectCodePage(address, NO);
}

static BOOL LilyAllocateAddToolTrampoline(uintptr_t target) {
    if (gLilyNativeAddToolTrampoline) {
        return YES;
    }

    vm_address_t page = 0;
    kern_return_t kr = vm_allocate(mach_task_self(),
                                   &page,
                                   vm_page_size,
                                   VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO PATCH: vm_allocate trampoline failed kr=%d", kr]);
        return NO;
    }

    /* Make the fresh page writable, not RWX. */
    kr = vm_protect(mach_task_self(),
                    page,
                    vm_page_size,
                    FALSE,
                    VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), page, vm_page_size);
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO PATCH: trampoline RW protect failed kr=%d", kr]);
        return NO;
    }

    /*
     * Relocate the complete 16-byte prologue. It contains only stack/register
     * instructions, so no PC-relative relocation is required.
     */
    memcpy((void *)page, (void *)target, sizeof(gLilyOriginalAddToolBytes));

    /* Continue with the original function immediately after those 16 bytes. */
    uint8_t *jumpAt = (uint8_t *)page + sizeof(gLilyOriginalAddToolBytes);
    uint32_t jump[2] = { 0x58000050, 0xD61F0200 };
    uint64_t continuation = (uint64_t)(target + sizeof(gLilyOriginalAddToolBytes));
    memcpy(jumpAt, jump, sizeof(jump));
    memcpy(jumpAt + 8, &continuation, sizeof(continuation));

    sys_icache_invalidate((void *)page, 32);

    kr = vm_protect(mach_task_self(),
                    page,
                    vm_page_size,
                    FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), page, vm_page_size);
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO PATCH: trampoline RX protect failed kr=%d", kr]);
        return NO;
    }

    gLilyNativeAddToolTrampoline = (uintptr_t)page;

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO PATCH: trampoline=%p -> continue=0x%llx",
        (void *)page,
        (unsigned long long)(target + sizeof(gLilyOriginalAddToolBytes))]);
    return YES;
}

static void LilyNativeAddToolHook(void *server, void *tool);

static BOOL LilyPatchNativeAddTool(void) {
    pthread_mutex_lock(&gLilyNativeHookLock);

    if (gLilyNativeAddToolPatchInstalled) {
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return YES;
    }

    uintptr_t slide = LilyFindSharedImageSlide();
    if (!slide) {
        LilyMCPWrite(@"MCP-ROMO PATCH: Shared.framework slide NOT FOUND");
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    /* Confirmed forensic VA for this exact Shared binary. */
    uintptr_t target = slide + 0x126CC88;

    memcpy(gLilyOriginalAddToolBytes,
           (void *)target,
           sizeof(gLilyOriginalAddToolBytes));

    /* Runtime guard against applying this patch to the wrong binary/version. */
    const uint8_t expected[16] = {
        0xff, 0x03, 0x02, 0xd1,
        0xfa, 0x67, 0x03, 0xa9,
        0xf8, 0x5f, 0x04, 0xa9,
        0xf6, 0x57, 0x05, 0xa9
    };
    if (memcmp(gLilyOriginalAddToolBytes, expected, sizeof(expected)) != 0) {
        LilyMCPWrite([NSString stringWithFormat:
            @"MCP-ROMO PATCH: PROLOGUE MISMATCH @ 0x%llx; refusing patch",
            (unsigned long long)target]);
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    if (!LilyAllocateAddToolTrampoline(target)) {
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    /*
     * Prefer a single 4-byte B instruction. This avoids the old 16-byte
     * restore/repatch race and leaves the remaining original bytes untouched.
     * The trampoline already contains the complete relocated prologue.
     */
    if (!LilyWriteBranch((void *)target, (uintptr_t)&LilyNativeAddToolHook)) {
        LilyMCPWrite(@"MCP-ROMO PATCH: hook is outside AArch64 B range; refusing unsafe patch");
        vm_deallocate(mach_task_self(),
                      (vm_address_t)gLilyNativeAddToolTrampoline,
                      vm_page_size);
        gLilyNativeAddToolTrampoline = 0;
        pthread_mutex_unlock(&gLilyNativeHookLock);
        return NO;
    }

    gLilyNativeAddToolAddress = target;
    gLilyNativeAddToolPatchInstalled = YES;

    LilyMCPWrite([NSString stringWithFormat:
        @"MCP-ROMO PATCH: native addTool hooked @ 0x%llx -> %p",
        (unsigned long long)target,
        (void *)&LilyNativeAddToolHook]);

    pthread_mutex_unlock(&gLilyNativeHookLock);
    return YES;
}

static void LilyNativeAddToolHook(void *server, void *tool) {
    uintptr_t trampoline = gLilyNativeAddToolTrampoline;
    if (!trampoline) {
        return;
    }

    /*
     * The hook itself can be re-entered by unrelated code. Never inject while
     * another injection is already in progress. Calls made by the injector use
     * the trampoline directly and therefore bypass this hook.
     */
    BOOL outermost = (gLilyNativeHookDepth == 0);
    gLilyNativeHookDepth++;

    if (outermost && server && gLilyRomoInjectedServer != server) {
        LilyInjectRobotToolsIntoServer(server);
    }

    gLilyNativeHookDepth--;

    /* Execute the original function through the permanent trampoline. */
    ((LilyMcpAddToolFn)trampoline)(server, tool);
}

static void LilyInstallMCPRomoHook(void) {
    /* TEMPORARY A/B TEST: disable native addTool patch.
       Keep all hook code intact, but do not modify Shared.framework. */
    gLilyMCPHookInstalled = NO;
    LilyMCPWrite(@"MCP-ROMO PATCH: DISABLED FOR BUILD #39 A/B TEST");
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

