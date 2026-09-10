#import "RomoTCPServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>
#import <math.h>

#import <Romo/RMCore.h>

static const int kRomoTCPPort = 5000;

@interface RomoTCPServer ()
@property (nonatomic, copy) RMCoreRobot *(^robotProvider)(void);
@property (nonatomic) int serverSocket;
@property (nonatomic) BOOL running;
@end

@implementation RomoTCPServer

- (instancetype)initWithRobotProvider:(RMCoreRobot *(^)(void))robotProvider
{
    self = [super init];
    if (self) {
        _robotProvider = [robotProvider copy];
        _serverSocket = -1;
        _running = NO;
    }
    return self;
}

- (void)start
{
    if (self.running) {
        return;
    }

    self.running = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self serverLoop];
    });
}

- (void)stop
{
    self.running = NO;

    if (self.serverSocket >= 0) {
        shutdown(self.serverSocket, SHUT_RDWR);
        close(self.serverSocket);
        self.serverSocket = -1;
    }
}

- (void)serverLoop
{
    NSLog(@"ROMO TCP: entering serverLoop");
    self.serverSocket = socket(AF_INET, SOCK_STREAM, 0);

    if (self.serverSocket < 0) {
        NSLog(@"ROMO TCP: socket() failed errno=%d (%s)", errno, strerror(errno));
        return;
    }

    int yes = 1;
    setsockopt(self.serverSocket,
               SOL_SOCKET,
               SO_REUSEADDR,
               &yes,
               sizeof(yes));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(kRomoTCPPort);

    if (bind(self.serverSocket,
             (struct sockaddr *)&address,
             sizeof(address)) < 0) {

        NSLog(@"ROMO TCP: bind() failed errno=%d (%s)", errno, strerror(errno));
        close(self.serverSocket);
        self.serverSocket = -1;
        return;
    }

    if (listen(self.serverSocket, 5) < 0) {
        NSLog(@"ROMO TCP: listen() failed errno=%d (%s)", errno, strerror(errno));
        close(self.serverSocket);
        self.serverSocket = -1;
        return;
    }

    NSLog(@"ROMO TCP: listening on port %d", kRomoTCPPort);

    while (self.running) {

        struct sockaddr_in clientAddress;
        socklen_t clientLength = sizeof(clientAddress);

        int clientSocket = accept(
            self.serverSocket,
            (struct sockaddr *)&clientAddress,
            &clientLength
        );

        if (clientSocket < 0) {
            if (self.running) {
                NSLog(@"ROMO TCP: accept() failed");
            }
            continue;
        }

        NSLog(@"ROMO TCP: client connected");

        [self handleClient:clientSocket];

        shutdown(clientSocket, SHUT_RDWR);
        close(clientSocket);

        NSLog(@"ROMO TCP: client disconnected");

        [self stopRobot];
    }

    NSLog(@"ROMO TCP: server stopped");
}

- (void)handleClient:(int)clientSocket
{
    char buffer[256];

    NSMutableData *pendingData = [NSMutableData data];

    while (self.running) {

        ssize_t bytesRead = recv(
            clientSocket,
            buffer,
            sizeof(buffer) - 1,
            0
        );

        if (bytesRead <= 0) {
            break;
        }

        buffer[bytesRead] = '\0';

        [pendingData appendBytes:buffer length:(NSUInteger)bytesRead];

        while (YES) {

            const char *bytes = pendingData.bytes;
            NSUInteger length = pendingData.length;

            const char *newline =
                memchr(bytes, '\n', length);

            if (!newline) {
                break;
            }

            NSUInteger commandLength =
                (NSUInteger)(newline - bytes);

            NSData *commandData =
                [pendingData subdataWithRange:
                    NSMakeRange(0, commandLength)];

            NSString *command =
                [[NSString alloc]
                    initWithData:commandData
                    encoding:NSUTF8StringEncoding];

            NSUInteger consumed = commandLength + 1;

            if (pendingData.length >= consumed) {
                [pendingData replaceBytesInRange:
                    NSMakeRange(0, consumed)
                    withBytes:NULL
                    length:0];
            }

            command =
                [command stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if (command.length > 0) {
                [self processCommand:command];
            }
        }
    }
}

- (void)processCommand:(NSString *)command
{
    NSString *upper =
        [command uppercaseString];

    RMCoreRobot *robot = self.robotProvider
        ? self.robotProvider()
        : nil;

    if (!robot) {
        NSLog(@"ROMO TCP: robot not connected");
        return;
    }

    RMCoreRobot<HeadTiltProtocol, DriveProtocol, DifferentialDriveProtocol, LEDProtocol> *romo =
        (RMCoreRobot<HeadTiltProtocol, DriveProtocol, DifferentialDriveProtocol, LEDProtocol> *)robot;

    NSLog(@"ROMO TCP COMMAND: %@", upper);

    if ([upper isEqualToString:@"STOP"]) {

        [romo stopDriving];

    } else if ([upper isEqualToString:@"FORWARD"]) {

        [romo driveWithPower:0.5];

    } else if ([upper isEqualToString:@"BACKWARD"]) {

        [romo driveWithPower:-0.5];

    } else if ([upper isEqualToString:@"LEFT"]) {

        [romo driveWithRadius:0.0 speed:0.5];

    } else if ([upper isEqualToString:@"RIGHT"]) {

        [romo driveWithRadius:0.0 speed:-0.5];

    } else if ([upper isEqualToString:@"TILT_UP"]) {

        [romo tiltByAngle:10.0 completion:^(BOOL success) {
            NSLog(@"ROMO TCP: tilt up complete");
        }];

    } else if ([upper isEqualToString:@"TILT_DOWN"]) {

        [romo tiltByAngle:-10.0 completion:^(BOOL success) {
            NSLog(@"ROMO TCP: tilt down complete");
        }];

    } else if ([upper hasPrefix:@"TURN_ANGLE:"]) {

        NSString *value = [upper substringFromIndex:11];
        NSScanner *scanner = [NSScanner scannerWithString:value];
        float angle = 0.0f;

        BOOL parsed = [scanner scanFloat:&angle] && scanner.isAtEnd;

        if (!parsed || !isfinite(angle) || angle == 0.0f || angle < -180.0f || angle > 180.0f) {
            NSLog(@"ROMO TCP: invalid TURN_ANGLE: %@", value);
            return;
        }

        NSLog(@"ROMO TCP: native turn angle %.2f deg", angle);

        [romo turnByAngle:angle
               withRadius:RM_DRIVE_RADIUS_TURN_IN_PLACE
                    speed:0.3f
          finishingAction:RMCoreTurnFinishingActionStopDriving
               completion:^(BOOL success, float heading) {
            NSLog(@"ROMO TCP: turn %.2f -> success=%d heading=%.2f",
                  angle, success, heading);
        }];

    } else {

        NSLog(@"ROMO TCP: unknown command: %@", upper);
    }
}

- (void)stopRobot
{
    RMCoreRobot *robot = self.robotProvider
        ? self.robotProvider()
        : nil;

    if (robot) {
        RMCoreRobot<HeadTiltProtocol, DriveProtocol, DifferentialDriveProtocol, LEDProtocol> *romo =
            (RMCoreRobot<HeadTiltProtocol, DriveProtocol, DifferentialDriveProtocol, LEDProtocol> *)robot;

        [romo stopDriving];

        NSLog(@"ROMO TCP: safety STOP");
    }
}

@end

