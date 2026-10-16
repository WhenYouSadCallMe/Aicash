//
//  CAMCPBridge.m — 内部 MCP 桥实现（loopback HTTP + JSON-RPC 2.0，端点 /mcp）
//

#import "CACommon.h"
#import "CAMCPBridge.h"
#import "CALogger.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

NSString *const CAMCPProtocolVersion = @"2025-06-18";

@interface CAMCPBridge ()
@property (nonatomic, assign) int listenFD;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) uint16_t port;
@end

@implementation CAMCPBridge

+ (instancetype)sharedBridge
{
    static CAMCPBridge *bridge; static dispatch_once_t once;
    dispatch_once(&once, ^{ bridge = [CAMCPBridge new]; });
    return bridge;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _listenFD = -1;
        _queue = dispatch_queue_create("app.codex.mcpbridge", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

#pragma mark - 生命周期

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error
{
    if (self.running) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // 仅回环（原包 127.0.0.1:27018）

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(fd, 16) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        close(fd);
        return NO;
    }
    self.listenFD = fd;
    self.port = port;
    self.running = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (weakSelf.running) {
            int client = accept(weakSelf.listenFD, NULL, NULL);
            if (client < 0) break;
            dispatch_async(weakSelf.queue, ^{ [weakSelf handleClient:client]; });
        }
    });
    CALog(CALogLevelInfo, @"APP-SERVER", @"internal MCP bridge listening %@:%u%@", CAInternalMCPHost, port, CAInternalMCPPath);
    return YES;
}

- (void)stop
{
    self.running = NO;
    if (self.listenFD >= 0) close(self.listenFD);
    self.listenFD = -1;
}

#pragma mark - HTTP

- (void)handleClient:(int)client
{
    NSMutableData *request = [NSMutableData data];
    char buffer[4096];
    ssize_t got;
    NSUInteger contentLength = 0;
    NSRange headerEnd = NSMakeRange(NSNotFound, 0);

    while ((got = recv(client, buffer, sizeof(buffer), 0)) > 0) {
        [request appendBytes:buffer length:(NSUInteger)got];
        if (headerEnd.location == NSNotFound) {
            NSRange r = [request rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, request.length)];
            if (r.location != NSNotFound) {
                headerEnd = r;
                NSString *headers = [[NSString alloc] initWithData:[request subdataWithRange:NSMakeRange(0, r.location)] encoding:NSUTF8StringEncoding];
                for (NSString *line in [headers componentsSeparatedByString:@"\r\n"]) {
                    if ([line.lowercaseString hasPrefix:@"content-length:"]) {
                        contentLength = (NSUInteger)[line substringFromIndex:15].integerValue;
                    }
                }
            }
        }
        if (headerEnd.location != NSNotFound) {
            NSUInteger bodyStart = headerEnd.location + headerEnd.length;
            if (request.length >= bodyStart + contentLength) break;
        }
    }

    NSData *responseBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    int status = 200;
    if (headerEnd.location == NSNotFound) {
        status = 400;
    } else {
        NSUInteger bodyStart = headerEnd.location + headerEnd.length;
        NSData *body = request.length > bodyStart ? [request subdataWithRange:NSMakeRange(bodyStart, request.length - bodyStart)] : [NSData data];
        if (!body.length) {
            status = 202;   // 通知（initialized 等）
        } else {
            NSDictionary *message = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
            NSDictionary *reply = [self handleJSONRPC:message];
            responseBody = reply ? [NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL] : [NSData data];
        }
    }

    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 %d %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        status, status == 200 ? @"OK" : (status == 202 ? @"Accepted" : @"Bad Request"),
        (unsigned long)responseBody.length];
    NSMutableData *payload = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [payload appendData:responseBody];
    send(client, payload.bytes, payload.length, 0);
    close(client);
}

#pragma mark - JSON-RPC

- (NSDictionary *)handleJSONRPC:(NSDictionary *)message
{
    id rid = message[@"id"];
    NSString *method = message[@"method"];
    if (!method) return nil;

    if ([method isEqualToString:@"initialize"]) {
        return @{ @"jsonrpc": @"2.0", @"id": rid ?: NSNull.null, @"result": @{
            @"protocolVersion": CAMCPProtocolVersion,
            @"capabilities": @{ @"tools": @{ @"listChanged": @NO } },
            @"serverInfo": @{ @"name": @"CodexApp Native Tools", @"version": CABundleShortVersion },
        } };
    }
    if ([method isEqualToString:@"ping"]) {
        return @{ @"jsonrpc": @"2.0", @"id": rid ?: NSNull.null, @"result": @{} };
    }
    if ([method isEqualToString:@"tools/list"]) {
        NSArray *tools = [self.toolProvider mcpToolDescriptors] ?: @[];
        return @{ @"jsonrpc": @"2.0", @"id": rid ?: NSNull.null, @"result": @{ @"tools": tools } };
    }
    if ([method isEqualToString:@"tools/call"]) {
        NSDictionary *params = message[@"params"] ?: @{};
        NSDictionary *result = [self.toolProvider mcpCallTool:params[@"name"] arguments:params[@"arguments"] ?: @{}];
        if (!result) {
            self.reportedInternalMCPTransportFailure = YES;
            return @{ @"jsonrpc": @"2.0", @"id": rid ?: NSNull.null,
                      @"error": @{ @"code": @(-32601), @"message": @"internal CodexApp MCP bridge is unavailable" } };
        }
        return @{ @"jsonrpc": @"2.0", @"id": rid ?: NSNull.null, @"result": result };
    }
    return @{ @"jsonrpc": @"2.0", @"id": rid ?: NSNull.null,
              @"error": @{ @"code": @(-32601), @"message": [NSString stringWithFormat:@"method not found: %@", method] } };
}

@end
