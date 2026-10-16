//
//  CAAppServerSession.m
//  对齐原包：app-server --stdio 子进程、按行 JSON-RPC、通知分发、失效上报、退出码日志
//  （原包日志字面量：app-server exited status=%d / app-server stopped / app-server died mid-turn status=%d）
//

#import "CACommon.h"
#import "CAAppServerSession.h"
#import "CALogger.h"
#import "CAProcess.h"

@interface CAAppServerSession ()
@property (nonatomic, copy) NSString *executable;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, copy) NSString *workingDirectory;
@property (nonatomic, strong) CAProcess *task;
@property (nonatomic, strong) NSPipe *stdinPipe;
@property (nonatomic, strong) NSPipe *stdoutPipe;
@property (nonatomic, strong) NSPipe *stderrPipe;
@property (nonatomic, strong) NSMutableString *stdoutBuffer;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(id, NSError *)> *pending;
@property (nonatomic, assign) NSInteger nextRequestID;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) int pid;
@end

@implementation CAAppServerSession

- (instancetype)initWithExecutable:(NSString *)executable
                         arguments:(NSArray<NSString *> *)arguments
                       environment:(NSDictionary<NSString *, NSString *> *)environment
                 workingDirectory:(NSString *)workingDirectory
{
    if ((self = [super init])) {
        _executable = [executable copy];
        _arguments = [arguments copy];
        _environment = [environment copy];
        _workingDirectory = [workingDirectory copy];
        _stdoutBuffer = [NSMutableString string];
        _pending = [NSMutableDictionary dictionary];
        _nextRequestID = 1;
    }
    return self;
}

#pragma mark - 生命周期

- (void)startWithCompletion:(void (^)(BOOL, NSError *))completion
{
    if (self.running) { if (completion) completion(YES, nil); return; }

    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:self.executable];
    task.arguments = self.arguments;
    task.environment = self.environment;
    if (self.workingDirectory.length) task.currentDirectoryURL = [NSURL fileURLWithPath:self.workingDirectory];

    self.stdinPipe = [NSPipe pipe];
    self.stdoutPipe = [NSPipe pipe];
    self.stderrPipe = [NSPipe pipe];
    task.standardInput = self.stdinPipe;
    task.standardOutput = self.stdoutPipe;
    task.standardError = self.stderrPipe;

    __weak typeof(self) weakSelf = self;
    self.stdoutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *data = h.availableData;
        if (!data.length) return;
        [weakSelf ingestData:data];
    };
    self.stderrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *data = h.availableData;
        if (!data.length) return;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (!line.length) continue;
            if ([line containsString:@"127.0.0.1:27018/mcp"] || [line containsString:@"rmcp::transport::worker"] ||
                [line containsString:@"Transport channel closed"]) {
                CALog(CALogLevelWarn, @"APP-SERVER", @"internal CodexApp MCP bridge is unavailable; user-facing MCP discovery will degrade (%@)", line);
            } else {
                CALog(CALogLevelDebug, @"CHAT-STDERR", @"%@", line);
            }
        }
    };

    task.terminationHandler = ^(CAProcess *t) {
        typeof(self) strongSelf = weakSelf;
        strongSelf.running = NO;
        strongSelf.stdoutPipe.fileHandleForReading.readabilityHandler = nil;
        strongSelf.stderrPipe.fileHandleForReading.readabilityHandler = nil;
        CALog(CALogLevelWarn, @"APP-SERVER", @"app-server exited status=%d", t.terminationStatus);
        CALog(CALogLevelWarn, @"APP-SERVER", @"app-server stopped");
        for (NSNumber *key in strongSelf.pending.allKeys) {
            void (^handler)(id, NSError *) = strongSelf.pending[key];
            handler(nil, [NSError errorWithDomain:@"CodexApp.AppServer" code:t.terminationStatus
                                         userInfo:@{ NSLocalizedDescriptionKey: @"app-server stopped" }]);
        }
        [strongSelf.pending removeAllObjects];
        if ([strongSelf.delegate respondsToSelector:@selector(appServerSession:didInvalidateWithReason:)]) {
            [strongSelf.delegate appServerSession:strongSelf didInvalidateWithReason:@"app-server stopped"];
        }
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        CALog(CALogLevelError, @"APP-SERVER", @"app-server launch failed error=%@", error.localizedDescription);
        if (completion) completion(NO, error);
        return;
    }
    self.task = task;
    self.running = YES;
    self.pid = task.processIdentifier;
    self.signature = [NSString stringWithFormat:@"%@|%@|%d", self.executable.lastPathComponent,
                      [self.arguments componentsJoinedByString:@" "], self.pid];
    CALog(CALogLevelInfo, @"APP-SERVER", @"app-server started pid=%d executable=%@", self.pid, self.executable);
    if (completion) completion(YES, nil);
}

- (void)stop
{
    if (!self.running) return;
    [self.task terminate];
    self.running = NO;
}

- (BOOL)retireIfIdle
{
    if (self.pending.count > 0) return NO;
    [self stop];
    return YES;
}

- (BOOL)isRunning { return _running; }
- (int)processIdentifier { return _pid; }

#pragma mark - JSON-RPC

- (void)callMethod:(NSString *)method parameters:(NSDictionary *)parameters completion:(void (^)(id, NSError *))completion
{
    if (!self.running) {
        if (completion) completion(nil, [NSError errorWithDomain:@"CodexApp.AppServer" code:409
                                                        userInfo:@{ NSLocalizedDescriptionKey: @"app-server not ready" }]);
        return;
    }
    NSInteger rid = self.nextRequestID++;
    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    message[@"jsonrpc"] = @"2.0";
    message[@"id"] = @(rid);
    message[@"method"] = method;
    if (parameters) message[@"params"] = parameters;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    NSMutableData *line = [payload mutableCopy];
    [line appendBytes:"\n" length:1];

    if (completion) self.pending[@(rid)] = completion;
    @try {
        [self.stdinPipe.fileHandleForWriting writeData:line];
    } @catch (NSException *exception) {
        if (completion) completion(nil, [NSError errorWithDomain:@"CodexApp.AppServer" code:500 userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: @"write failed" }]);
    }
}

- (void)ingestData:(NSData *)data
{
    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    [self.stdoutBuffer appendString:chunk];
    NSRange newline;
    while ((newline = [self.stdoutBuffer rangeOfString:@"\n"]).location != NSNotFound) {
        NSString *line = [self.stdoutBuffer substringToIndex:newline.location];
        [self.stdoutBuffer deleteCharactersInRange:NSMakeRange(0, newline.location + 1)];
        if (!line.length) continue;
        [self handleLine:line];
    }
}

- (void)handleLine:(NSString *)line
{
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![message isKindOfClass:NSDictionary.class]) {
        CALog(CALogLevelDebug, @"CHAT-STDERR", @"%@", line);
        return;
    }
    if (message[@"id"] && (message[@"result"] || message[@"error"])) {
        NSNumber *rid = message[@"id"];
        void (^handler)(id, NSError *) = self.pending[rid];
        [self.pending removeObjectForKey:rid];
        if (!handler) return;
        if (message[@"error"]) {
            NSDictionary *err = message[@"error"];
            handler(nil, [NSError errorWithDomain:@"CodexApp.AppServer" code:[err[@"code"] integerValue]
                                         userInfo:@{ NSLocalizedDescriptionKey: err[@"message"] ?: @"app-server returned an error" }]);
        } else {
            handler(message[@"result"], nil);
        }
        return;
    }
    NSString *method = message[@"method"];
    NSDictionary *params = [message[@"params"] isKindOfClass:NSDictionary.class] ? message[@"params"] : @{};

    if ([method isEqualToString:CARPCNotificationInvalidated]) {
        if ([self.delegate respondsToSelector:@selector(appServerSession:didInvalidateWithReason:)]) {
            [self.delegate appServerSession:self didInvalidateWithReason:params[@"reason"] ?: @"configuration changed"];
        }
    } else if ([method isEqualToString:CARPCItemRequestUserInput]) {
        if ([self.delegate respondsToSelector:@selector(appServerSession:didRequestUserInput:)]) {
            [self.delegate appServerSession:self didRequestUserInput:params];
        }
    } else if ([method isEqualToString:@"turn/usage"]) {
        if ([self.delegate respondsToSelector:@selector(appServerSession:didReportUsage:)]) {
            [self.delegate appServerSession:self didReportUsage:params];
        }
    } else if ([self.delegate respondsToSelector:@selector(appServerSession:didEmitNotification:params:)]) {
        [self.delegate appServerSession:self didEmitNotification:method params:params];
    }
}

#pragma mark - 诊断

- (NSDictionary *)diagnosticSnapshot
{
    return @{
        @"executable": self.executable ?: @"",
        @"arguments": self.arguments ?: @[],
        @"running": @(self.running),
        @"pid": @(self.pid),
        @"pendingRequests": @(self.pending.count),
        @"signature": self.signature ?: @"",
    };
}

@end
