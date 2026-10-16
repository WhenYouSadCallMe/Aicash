//
//  CARemoteOperations.m
//
//  行为逐条对齐原包：
//    requestForPath:method:  → base=Supabase、头 apikey/Authorization=anon JWT、Content-Type、UA=CodexApp/1.0、timeout 12s
//    sendHeartbeat           → POST /rest/v1/heartbeats?on_conflict=anonymous_id，Prefer: resolution=merge-duplicates,return=minimal
//                              body 8 字段：anonymous_id / device_group_id / last_seen / updated_at / app_version / device_model /
//                                          app_id="codex" / log_switches={codex_logging:bool}
//    fetchPolicy             → GET /rest/v1/risk_control_config?id=eq.1&select=…；失败累计 → CodexRemoteHeartbeatFailureLimit
//    applyPolicy             → feature_flags / log_switches / max_heartbeat_fail_count
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CARemoteOperations.h"
#import "CALogger.h"
#import <sys/sysctl.h>

NSNotificationName const CARemoteOperationsDidChangeNotification = @"CARemoteOperationsDidChangeNotification";

static NSString * const kPolicyRefreshIntervalKey = @"CodexRemotePolicyRefreshInterval";
static const NSTimeInterval kDefaultPolicyRefreshInterval = 6 * 60 * 60;
static const NSTimeInterval kHeartbeatInterval = 30 * 60;

@implementation CARemoteOperations
{
    NSURLSession *_session;
    NSTimer *_timer;
}

+ (instancetype)sharedOperations
{
    static CARemoteOperations *ops; static dispatch_once_t once;
    dispatch_once(&once, ^{ ops = [[CARemoteOperations alloc] init]; });
    return ops;
}

- (instancetype)init
{
    if ((self = [super init])) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _anonymousID = [[defaults stringForKey:@"CodexRemoteInstallID"] copy];
        if (!_anonymousID.length) {
            _anonymousID = NSUUID.UUID.UUIDString;
            [defaults setObject:_anonymousID forKey:@"CodexRemoteInstallID"];
        }
        _deviceGroupID = [self loadDeviceGroupID];
        _heartbeatFailureLimit = [defaults integerForKey:CADefaultsRemoteHeartbeatLimit];
        if (_heartbeatFailureLimit <= 0) _heartbeatFailureLimit = 5;
        _heartbeatHealthy = YES;
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = CARemoteTimeout;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - 设备指纹（原包：/var/mobile/Documents/.mt-device-group-id-v1）

- (NSString *)loadDeviceGroupID
{
    NSString *path = CARuntimePaths.deviceGroupIDPath;
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length) return value;
    value = NSUUID.UUID.UUIDString;
    [CARuntimePaths writeFileAtomically:path contents:[value dataUsingEncoding:NSUTF8StringEncoding] mode:0644 error:NULL];
    return value;
}

- (NSString *)deviceModel
{
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0) return @"unknown";
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *model = [NSString stringWithUTF8String:machine];
    free(machine);
    return model ?: @"unknown";
}

- (NSString *)appVersion
{
    NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: CABundleShortVersion;
    NSString *b = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: CABundleVersion;
    return [NSString stringWithFormat:@"%@ (%@)", v, b];
}

#pragma mark - 请求构造（原包逐字段）

- (NSURLRequest *)requestForPath:(NSString *)path method:(NSString *)method
{
    NSString *urlString = [CARemoteBaseURL stringByAppendingString:path];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:CARemoteTimeout];
    request.HTTPMethod = method;
    [request setValue:CARemoteAnonKey forHTTPHeaderField:@"apikey"];
    [request setValue:[@"Bearer " stringByAppendingString:CARemoteAnonKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:CAUserAgent forHTTPHeaderField:@"User-Agent"];
    return request;
}

- (NSURLSession *)ephemeralSession { return _session; }

#pragma mark - 生命周期

- (void)start
{
    [self performRefresh];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kHeartbeatInterval target:self selector:@selector(performRefresh) userInfo:nil repeats:YES];
}

- (void)performRefresh
{
    [self fetchPolicyWithCompletion:^(NSDictionary *policy, NSError *error) {
        if (error) {
            CALog(CALogLevelWarn, @"NETWORK", @"remote policy refresh failed reason=%@", error.localizedDescription);
            return;
        }
        [self sendHeartbeatWithCompletion:nil];
    }];
}

- (BOOL)heartbeatFreshAtTime:(NSDate *)now
{
    if (!self.lastHeartbeatSuccess) return NO;
    return [now timeIntervalSinceDate:self.lastHeartbeatSuccess] < kHeartbeatInterval * 2;
}

- (void)publishStateIfNeeded
{
    if (!self.policyKnown) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:CARemoteOperationsDidChangeNotification object:self];
}

#pragma mark - 策略

- (void)fetchPolicyWithCompletion:(void (^)(NSDictionary *, NSError *))completion
{
    NSURLRequest *request = [self requestForPath:CAPolicyPath method:@"GET"];
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error || http.statusCode >= 400) {
            self.consecutiveHeartbeatFailures += 1;
            self.heartbeatHealthy = NO;
            CALog(CALogLevelWarn, @"NETWORK", @"remote policy fetch failed status=%ld reason=%@", (long)http.statusCode, error.localizedDescription ?: @"http");
            if (completion) completion(nil, error ?: [NSError errorWithDomain:@"CodexApp.Remote" code:http.statusCode userInfo:nil]);
            return;
        }
        NSArray *rows = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSDictionary *policy = [rows isKindOfClass:NSArray.class] ? rows.firstObject : nil;
        [self applyPolicy:policy ?: @{}];
        if (completion) completion(policy, nil);
    }];
    [task resume];
}

- (void)applyPolicy:(NSDictionary *)policy
{
    self.policy = policy;
    self.policyKnown = YES;
    NSDictionary *featureFlags = [policy[@"feature_flags"] isKindOfClass:NSDictionary.class] ? policy[@"feature_flags"] : @{};
    NSDictionary *logSwitches  = [policy[@"log_switches"] isKindOfClass:NSDictionary.class] ? policy[@"log_switches"] : @{};
    NSNumber *limit = [policy[@"max_heartbeat_fail_count"] isKindOfClass:NSNumber.class] ? policy[@"max_heartbeat_fail_count"] : nil;
    if (limit) {
        self.heartbeatFailureLimit = limit.integerValue;
        [NSUserDefaults.standardUserDefaults setInteger:limit.integerValue forKey:CADefaultsRemoteHeartbeatLimit];
    }

    // 远端日志开关（原包：log_switches.codex_logging → CALogger applyRemoteLoggingEnabled:）
    NSNumber *logging = logSwitches[@"codex_logging"];
    if ([logging isKindOfClass:NSNumber.class]) {
        self.remoteLoggingEnabled = logging.boolValue;
        [[CALogger sharedLogger] applyRemoteLoggingEnabled:logging.boolValue];
    }

    // 远端 Theos / 运行时开关（原包：CodexRemoteTheosEnabled、feature_flags）
    NSNumber *theos = featureFlags[@"theos"] ?: featureFlags[@"remote_theos"];
    if ([theos isKindOfClass:NSNumber.class]) {
        [NSUserDefaults.standardUserDefaults setBool:theos.boolValue forKey:CADefaultsRemoteTheosEnabled];
    }
    CALog(CALogLevelInfo, @"NETWORK", @"remote policy applied feature_flags=%lu log_switches=%lu limit=%ld",
          (unsigned long)featureFlags.count, (unsigned long)logSwitches.count, (long)self.heartbeatFailureLimit);
    [self publishStateIfNeeded];
}

#pragma mark - 心跳（原包 8 字段，顺序一致）

- (void)sendHeartbeatWithCompletion:(void (^)(BOOL, NSError *))completion
{
    NSMutableURLRequest *request = [[self requestForPath:CAHeartbeatPath method:@"POST"] mutableCopy];
    [request setValue:CAHeartbeatPrefer forHTTPHeaderField:@"Prefer"];

    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSString *now = [formatter stringFromDate:[NSDate date]];

    NSDictionary *body = @{
        @"anonymous_id":   self.anonymousID ?: @"",
        @"device_group_id": self.deviceGroupID ?: @"",
        @"last_seen":      now,
        @"updated_at":     now,
        @"app_version":    [self appVersion],
        @"device_model":   [self deviceModel],
        @"app_id":         @"codex",
        @"log_switches":   @{ @"codex_logging": @(self.remoteLoggingEnabled) },
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        BOOL ok = (!error && http.statusCode < 400);
        if (ok) {
            self.lastHeartbeatSuccess = [NSDate date];
            self.consecutiveHeartbeatFailures = 0;
            self.heartbeatHealthy = YES;
        } else {
            self.consecutiveHeartbeatFailures += 1;
            self.heartbeatHealthy = NO;
            CALog(CALogLevelWarn, @"NETWORK", @"Codex heartbeat failed count=%ld/%ld status=%ld",
                  (long)self.consecutiveHeartbeatFailures, (long)self.heartbeatFailureLimit, (long)http.statusCode);
        }
        if (completion) completion(ok, error);
    }];
    [task resume];
}

@end
