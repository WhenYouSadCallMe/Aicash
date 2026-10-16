//
//  CALogger.m — 日志子系统（对齐原包：等级/分类/按大小轮转/脱敏/远端开关）
//  原包观测格式：时间 "yyyy-MM-dd HH:mm:ss.SSS"、形如 "[CodexApp][%@] %@"、文件名 CodexApp.log / CodexApp.log.1
//  脱敏正则：Bearer / sk-… / (access_token|api_key|authorization)=…
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"

static NSString * const kLogFileName       = @"CodexApp.log";
static NSString * const kLogRotatedName    = @"CodexApp.log.1";
static const unsigned long long kLogRotateBytes = 4ull * 1024 * 1024; // 轮转阈值

@implementation CALogger
{
    dispatch_queue_t _queue;
    NSDateFormatter  *_formatter;
    NSMutableSet<NSString *> *_enabledCategories;
    NSMutableDictionary<NSString *, NSDate *> *_throttleTimes;
    NSLock *_throttleLock;
    unsigned long long _bytesSinceRotateCheck;
    NSTimeInterval _lastRotateCheckUptime;
}

+ (instancetype)sharedLogger
{
    static CALogger *logger; static dispatch_once_t once;
    dispatch_once(&once, ^{ logger = [[CALogger alloc] initPrivate]; });
    return logger;
}

- (instancetype)initPrivate
{
    if ((self = [super init])) {
        _queue = dispatch_queue_create("app.codex.logger", DISPATCH_QUEUE_SERIAL);
        _formatter = [NSDateFormatter new];
        _formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        _formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _enabledCategories = [NSMutableSet set];
        _throttleTimes = [NSMutableDictionary dictionary];
        _throttleLock = [NSLock new];
        _runtimeEnabled = YES;
        _runtimeDebugEnabled = NO;
    }
    return self;
}

- (instancetype)initWithLogFilePath:(NSString *)path defaults:(NSUserDefaults *)defaults
{
    if ((self = [self initPrivate])) {
        _logFilePath = [path copy];
        _preferences = defaults;
    }
    return self;
}

#pragma mark - 远端开关

- (void)applyRemoteLoggingEnabled:(BOOL)enabled
{
    self.remoteLoggingEnabled = enabled;
    CALog(CALogLevelInfo, @"GENERAL", @"remote logging %@", enabled ? @"enabled" : @"disabled");
}

- (BOOL)enabled { return _runtimeEnabled; }
- (void)setEnabled:(BOOL)enabled { _runtimeEnabled = enabled; }
- (BOOL)debugEnabled { return _runtimeDebugEnabled || self.remoteLoggingEnabled == NO ? _runtimeDebugEnabled : YES; }
- (void)setDebugEnabled:(BOOL)v { _runtimeDebugEnabled = v; }

- (NSSet<NSString *> *)knownCategories { return [_enabledCategories copy]; }
- (BOOL)isCategoryEnabled:(NSString *)category
{
    if (!_runtimeEnabledCategories.count) return YES;
    return [_runtimeEnabledCategories containsObject:category];
}
- (void)setCategory:(NSString *)category enabled:(BOOL)enabled
{
    dispatch_barrier_async(_queue, ^{
        NSMutableSet *set = self->_runtimeEnabledCategories ? [self->_runtimeEnabledCategories mutableCopy] : [NSMutableSet set];
        if (enabled) [set addObject:category]; else [set removeObject:category];
        self->_runtimeEnabledCategories = [set copy];
    });
}

- (BOOL)shouldLogLevel:(CALogLevel)level category:(NSString *)category
{
    if (self.remoteLoggingEnabled) return YES;
    if (level == CALogLevelDebug && !self.debugEnabled) return NO;
    return [self isCategoryEnabled:category];
}

- (BOOL)shouldLogLevel:(CALogLevel)level category:(NSString *)category throttleKey:(NSString *)key minimumInterval:(NSTimeInterval)interval
{
    if (![self shouldLogLevel:level category:category]) return NO;
    if (!key.length) return YES;
    [_throttleLock lock];
    NSDate *last = _throttleTimes[key];
    BOOL allow = (!last || -last.timeIntervalSinceNow >= interval);
    if (allow) _throttleTimes[key] = [NSDate date];
    [_throttleLock unlock];
    return allow;
}

#pragma mark - 脱敏（原包三条正则）

- (NSString *)redactedMessage:(NSString *)message
{
    if (!message.length) return message ?: @"";
    NSMutableString *out = [message mutableCopy];
    NSArray<NSArray<NSString *> *> *rules = @[
        @[ @"(?i)Bearer\\s+[A-Za-z0-9._~+/-]+=*", @"Bearer <redacted>" ],
        @[ @"sk-[A-Za-z0-9_-]{8,}",              @"<redacted-key>" ],
        @[ @"(?i)(access[_ -]?token|api[_ -]?key|authorization)(\\s*[:=]\\s*)([^\\s,;]+)", @"$1$2<redacted>" ],
    ];
    for (NSArray<NSString *> *rule in rules) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:rule[0] options:0 error:NULL];
        if (re) [re replaceMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:rule[1]];
    }
    return out;
}

- (NSString *)levelName:(CALogLevel)level
{
    switch (level) {
        case CALogLevelDebug: return @"DEBUG";
        case CALogLevelWarn:  return @"WARN";
        case CALogLevelError: return @"ERROR";
        default:              return @"INFO";
    }
}

- (NSString *)section:(CALogLevel)level category:(NSString *)category
{
    return [NSString stringWithFormat:@"[CodexApp][%@] ", category ?: @"GENERAL"];
}

#pragma mark - 写入

- (void)logLevel:(CALogLevel)level category:(NSString *)category message:(NSString *)message
{
    if (![self shouldLogLevel:level category:category]) return;
    NSString *safe = [self redactedMessage:message];
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n", [_formatter stringFromDate:[NSDate date]], [self levelName:level], safe];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(_queue, ^{
        NSString *path = self->_logFilePath ?: [[CARuntimePaths logsDirectory] stringByAppendingPathComponent:kLogFileName];
        [CARuntimePaths ensureDirectory:path.stringByDeletingLastPathComponent mode:0700 error:NULL];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:@{ NSFilePosixPermissions: @(0600) }];
            fh = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } @catch (__unused NSException *e) {}
        self->_bytesSinceRotateCheck += data.length;
        [self rotateIfNeeded];
    });
}

- (void)rotateIfNeeded
{
    unsigned long long total = 0;
    NSString *path = _logFilePath ?: [[CARuntimePaths logsDirectory] stringByAppendingPathComponent:kLogFileName];
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    total = [attrs[NSFileSize] unsignedLongLongValue];
    if (total < kLogRotateBytes) return;
    NSString *rotated = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:kLogRotatedName];
    [NSFileManager.defaultManager removeItemAtPath:rotated error:NULL];
    [NSFileManager.defaultManager moveItemAtPath:path toPath:rotated error:NULL];
}

- (NSString *)currentLogText
{
    NSString *path = _logFilePath ?: [[CARuntimePaths logsDirectory] stringByAppendingPathComponent:kLogFileName];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
}

- (void)clear
{
    NSString *path = _logFilePath ?: [[CARuntimePaths logsDirectory] stringByAppendingPathComponent:kLogFileName];
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    [NSFileManager.defaultManager removeItemAtPath:[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:kLogRotatedName] error:NULL];
}

- (void)beginAppSession
{
    CALog(CALogLevelInfo, @"GENERAL", @"Codex started");
    CALog(CALogLevelInfo, @"RUNTIME", @"%@", [self environmentSummary]);
}

- (NSString *)environmentSummary
{
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: CABundleIdentifier;
    return [NSString stringWithFormat:@"environment profile kind=%@ jailbreak=%d trollstore=%d flavor=%@ brand=%@ family=%@ root=%@ launcher=%@ bundle=%@ evidence=%@ theos=%@",
            @"standalone", 0, 0, @"none", @"none", @"none", @"none", @"none", bundle, @"n/a", @"bundled"];
}

@end

void CALog(CALogLevel level, NSString *category, NSString *format, ...)
{
    va_list args; va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [[CALogger sharedLogger] logLevel:level category:category message:msg];
    if (getenv("CA_LOG_STDERR")) fprintf(stderr, "[CodexApp][%s] %s\n", category.UTF8String, msg.UTF8String);
}
