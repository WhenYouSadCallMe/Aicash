//
//  CARateLimitManager - local quota snapshots and session token accounting.
//

#import "CARateLimitManager.h"
#import "CARuntimePaths.h"

@interface CARateLimitManager () {
    NSDictionary *_snapshot;
    NSDictionary *_officialSnapshot;
    NSDate *_lastUpdatedAt;
    NSString *_planName;
    NSString *_quotaBadgeText;
    NSString *_unavailableReason;
    BOOL _available;
    BOOL _loadingCache;
    unsigned long long _sessionTotalTokens;
}
- (void)reloadFromDisk;
- (void)applySnapshot:(NSDictionary *)payload;
- (NSDictionary *)windowsFromSnapshot:(NSDictionary *)payload;
@end

@implementation CARateLimitManager

+ (instancetype)sharedManager
{
    static CARateLimitManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (id)sharedManager
{
    return [CARateLimitManager sharedManager];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _planName = @"Codex";
        [self reloadFromDisk];
    }
    return self;
}

- (NSString *)snapshotCachePath
{
    return [CARuntimePaths.supportDirectory stringByAppendingPathComponent:@"rate-limits.json"];
}

- (void)reloadFromDisk
{
    _loadingCache = YES;
    NSArray<NSString *> *paths = @[
        [CARuntimePaths.codexHome stringByAppendingPathComponent:@"rate-limits.json"],
        self.snapshotCachePath
    ];
    NSDictionary *payload = nil;
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data.length) continue;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([object isKindOfClass:NSDictionary.class]) {
            payload = object;
            break;
        }
    }
    if (payload) [self applySnapshot:payload];
    else [self markUnavailableWithReason:@"未找到本地配额快照"];
    _loadingCache = NO;
}

- (void)applySnapshot:(NSDictionary *)payload
{
    _snapshot = [payload copy];
    _officialSnapshot = _snapshot;
    id updated = payload[@"updated_at"] ?: payload[@"updatedAt"] ?: payload[@"timestamp"];
    if ([updated respondsToSelector:@selector(doubleValue)] && [updated doubleValue] > 0) {
        _lastUpdatedAt = [NSDate dateWithTimeIntervalSince1970:[updated doubleValue]];
    } else {
        _lastUpdatedAt = [NSDate date];
    }
    NSString *plan = payload[@"plan_type"] ?: payload[@"planType"] ?: payload[@"plan"];
    if ([plan isKindOfClass:NSString.class] && plan.length) _planName = plan;
    _available = [self windowsFromSnapshot:payload].count > 0;
    _unavailableReason = _available ? nil : @"配额数据暂不可用";
    _quotaBadgeText = [self formattedQuotaReport];
}

- (NSDictionary *)windowsFromSnapshot:(NSDictionary *)payload
{
    if (![payload isKindOfClass:NSDictionary.class]) return @{};
    id direct = payload[@"windows"];
    NSMutableDictionary *windows = [NSMutableDictionary dictionary];
    if ([direct isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"primary", @"secondary"]) {
            id value = direct[key];
            if ([value isKindOfClass:NSDictionary.class]) value = value[@"used_percent"] ?: value[@"usedPercent"] ?: value[@"percent"];
            if ([value respondsToSelector:@selector(doubleValue)]) windows[key] = @([value doubleValue]);
        }
    }
    NSArray *containers = @[
        payload,
        payload[@"rate_limits"] ?: @{},
        payload[@"rateLimits"] ?: @{},
        payload[@"rate_limits_by_limit_id"] ?: @{},
        payload[@"rateLimitsByLimitId"] ?: @{}
    ];
    for (id container in containers) {
        if (![container isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *dictionary = container;
        for (NSString *key in @[@"primary", @"secondary"]) {
            if (windows[key]) continue;
            id value = dictionary[key];
            if ([value isKindOfClass:NSDictionary.class]) {
                value = value[@"used_percent"] ?: value[@"usedPercent"] ?: value[@"percent"];
            }
            if ([value respondsToSelector:@selector(doubleValue)]) windows[key] = @([value doubleValue]);
        }
        for (id child in dictionary.allValues) {
            if (![child isKindOfClass:NSDictionary.class]) continue;
            for (NSString *key in @[@"primary", @"secondary"]) {
                if (windows[key]) continue;
                id value = child[key];
                if ([value isKindOfClass:NSDictionary.class]) value = value[@"used_percent"] ?: value[@"usedPercent"];
                if ([value respondsToSelector:@selector(doubleValue)]) windows[key] = @([value doubleValue]);
            }
        }
    }
    return windows;
}

- (bool)available { return _available && ![self isExpiredSnapshot:_snapshot]; }
- (id)formattedQuotaReport
{
    NSDictionary *windows = [self windowsFromSnapshot:_snapshot];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"primary", @"secondary"]) {
        NSNumber *percent = [windows[key] respondsToSelector:@selector(doubleValue)] ? windows[key] : nil;
        if (percent) {
            NSString *title = [key isEqualToString:@"primary"] ? @"主限额" : @"次限额";
            [parts addObject:[NSString stringWithFormat:@"%@ %.0f%%", title, percent.doubleValue]];
        }
    }
    return parts.count ? [parts componentsJoinedByString:@" · "] : @"暂未获取";
}

- (bool)isExpiredSnapshot:(id)arg1
{
    if (![arg1 isKindOfClass:NSDictionary.class]) return YES;
    id raw = arg1[@"updated_at"] ?: arg1[@"updatedAt"] ?: arg1[@"timestamp"];
    if (![raw respondsToSelector:@selector(doubleValue)] || [raw doubleValue] <= 0) return NO;
    return ([[NSDate date] timeIntervalSince1970] - [raw doubleValue]) > (24.0 * 60.0 * 60.0);
}

- (NSDate *)lastUpdatedAt { return _lastUpdatedAt; }
- (bool)loadingCache { return _loadingCache; }
- (void)markUnavailableWithReason:(id)arg1
{
    _available = NO;
    _unavailableReason = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : @"配额数据暂不可用";
}
- (NSDictionary *)officialSnapshot { return _officialSnapshot ?: @{}; }
- (NSString *)planName { return _planName ?: @"Codex"; }
- (NSString *)quotaBadgeText { return _quotaBadgeText ?: [self formattedQuotaReport]; }

- (void)recordTurnFinishedWithTokens:(id)arg1
{
    if ([arg1 respondsToSelector:@selector(unsignedLongLongValue)]) {
        _sessionTotalTokens += [arg1 unsignedLongLongValue];
    } else if ([arg1 isKindOfClass:NSDictionary.class]) {
        NSDictionary *usage = arg1;
        for (NSString *key in @[@"total_tokens", @"totalTokens", @"input_tokens", @"output_tokens"]) {
            if ([usage[key] respondsToSelector:@selector(unsignedLongLongValue)]) _sessionTotalTokens += [usage[key] unsignedLongLongValue];
        }
    }
}
- (void)resetSessionTokenCount { _sessionTotalTokens = 0; }
- (unsigned long long)sessionTotalTokens { return _sessionTotalTokens; }
- (void)setAvailable:(id)arg1 { _available = [arg1 respondsToSelector:@selector(boolValue)] && [arg1 boolValue]; }
- (void)setLastUpdatedAt:(id)arg1 { _lastUpdatedAt = [arg1 isKindOfClass:NSDate.class] ? arg1 : nil; }
- (void)setLoadingCache:(id)arg1 { _loadingCache = [arg1 respondsToSelector:@selector(boolValue)] && [arg1 boolValue]; }
- (void)setOfficialSnapshot:(id)arg1 { _officialSnapshot = [arg1 isKindOfClass:NSDictionary.class] ? [arg1 copy] : nil; }
- (void)setPlanName:(id)arg1 { _planName = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : @"Codex"; }
- (void)setQuotaBadgeText:(id)arg1 { _quotaBadgeText = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil; }
- (void)setSessionTotalTokens:(id)arg1 { _sessionTotalTokens = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0; }
- (void)setSnapshot:(id)arg1 { if ([arg1 isKindOfClass:NSDictionary.class]) [self applySnapshot:arg1]; }
- (void)setUnavailableReason:(id)arg1 { _unavailableReason = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil; }
- (NSDictionary *)snapshot { return _snapshot ?: @{}; }
- (NSString *)unavailableReason { return _unavailableReason ?: @""; }

- (void)updateWithServerSnapshot:(id)arg1
{
    if (![arg1 isKindOfClass:NSDictionary.class]) {
        [self markUnavailableWithReason:@"服务器未返回配额数据"];
        return;
    }
    [self applySnapshot:arg1];
    NSData *data = [NSJSONSerialization dataWithJSONObject:arg1 options:NSJSONWritingPrettyPrinted error:NULL];
    if (data) {
        // snapshotCachePath is an id in the generated compatibility header; keep
        // filesystem operations type-safe instead of relying on dot syntax.
        NSString *cachePath = [self.snapshotCachePath isKindOfClass:NSString.class] ? self.snapshotCachePath : nil;
        if (cachePath.length) {
            [CARuntimePaths ensureDirectory:[cachePath stringByDeletingLastPathComponent] mode:0755 error:NULL];
            [CARuntimePaths writeFileAtomically:cachePath contents:data mode:0644 error:NULL];
        }
    }
}

- (id)windowReport:(id)arg1 title:(id)arg2
{
    NSDictionary *window = [arg1 isKindOfClass:NSDictionary.class] ? arg1 : @{};
    NSString *title = [arg2 isKindOfClass:NSString.class] ? arg2 : @"用量窗口";
    id percent = window[@"used_percent"] ?: window[@"usedPercent"] ?: window[@"percent"];
    id remaining = window[@"remaining"] ?: window[@"remaining_tokens"];
    if ([percent respondsToSelector:@selector(doubleValue)]) {
        NSString *suffix = remaining ? [NSString stringWithFormat:@"，剩余 %@", remaining] : @"";
        return [NSString stringWithFormat:@"%@：已用 %.0f%%%@", title, [percent doubleValue], suffix];
    }
    return [NSString stringWithFormat:@"%@：暂未获取", title];
}

@end
