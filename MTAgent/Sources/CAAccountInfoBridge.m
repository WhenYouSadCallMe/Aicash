//
//  CAAccountInfoBridge.m — 账号信息桥实现
//
//  数据来源：CACodexMetadataReader（本地 auth.json / 会话） + CACodexEngine 的 codex 可执行探测。
//  缓存：NSUserDefaults，键 = "CodexAccountProfile.v2." + codex home（原包前缀观测值）。
//  失败只记日志（CALog，分类 ACCOUNT），不弹窗、不阻断。
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CACodexEngine.h"
#import "CACodexMetadataReader.h"
#import "CAAccountInfoBridge.h"

static NSString * const kCAAccountInfoUpdatedAtKey = @"updatedAt";

@implementation CAAccountInfoBridge

+ (instancetype)sharedBridge
{
    static CAAccountInfoBridge *bridge; static dispatch_once_t once;
    dispatch_once(&once, ^{ bridge = [CAAccountInfoBridge new]; });
    return bridge;
}

#pragma mark - 缓存键

+ (NSString *)cacheKeyForHome:(NSString *)home
{
    NSString *resolved = home.length ? home : CARuntimePaths.codexHome;
    return [NSString stringWithFormat:@"%@%@", CADefaultsAccountProfilePrefix, resolved];
}

+ (NSUserDefaults *)preferences
{
    return [NSUserDefaults standardUserDefaults];
}

#pragma mark - 缓存读写

+ (nullable NSDictionary *)cachedProfileForHome:(NSString *)home
{
    NSDictionary *cached = [[self preferences] dictionaryForKey:[self cacheKeyForHome:home]];
    return cached.count ? cached : nil;
}

+ (void)saveProfile:(NSDictionary *)profile home:(NSString *)home
{
    if (!profile.count) return;
    NSMutableDictionary *payload = [profile mutableCopy];
    payload[kCAAccountInfoUpdatedAtKey] = @([NSDate date].timeIntervalSince1970);
    [[self preferences] setObject:payload forKey:[self cacheKeyForHome:home]];
    CALog(CALogLevelDebug, @"ACCOUNT", @"account profile cached keys=%@", [[payload.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]);
}

+ (void)invalidateProfileCacheForHome:(NSString *)home
{
    [[self preferences] removeObjectForKey:[self cacheKeyForHome:home]];
    CALog(CALogLevelDebug, @"ACCOUNT", @"account profile cache invalidated home=%@", home ?: @"(default)");
}

#pragma mark - 读取

+ (void)readAccountEmailWithBin:(NSString *)bin
                           home:(NSString *)home
                     completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion
{
    [CACodexMetadataReader readAccountEmailWithBin:bin home:home completion:completion];
}

+ (void)readAccountProfileWithBin:(NSString *)bin
                             home:(NSString *)home
                       completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    [CACodexMetadataReader readAccountProfileWithBin:bin home:home completion:completion];
}

+ (void)augmentProfile:(NSDictionary *)profile
        fromCodexHome:(NSString *)home
           completion:(void (^)(NSDictionary *))completion
{
    NSMutableDictionary *merged = profile ? [profile mutableCopy] : [NSMutableDictionary dictionary];
    NSDictionary<NSString *, NSString *> *metadata = [CACodexMetadataReader profileMetadataAtHome:home];
    for (NSString *key in metadata) {
        id existing = merged[key];
        BOOL empty = (existing == nil) || ([existing isKindOfClass:NSString.class] && ![existing length]);
        if (empty) merged[key] = metadata[key];
    }
    if (completion) completion(merged);
}

+ (void)fetchAccountProfileWithBin:(NSString *)bin
                              home:(NSString *)home
                        completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    NSString *resolved = home.length ? home : CARuntimePaths.codexHome;
    CALog(CALogLevelInfo, @"ACCOUNT", @"reading account via persistent app-server home=%@", resolved);
    [self readAccountProfileWithBin:bin home:resolved completion:^(NSDictionary *profile, NSError *error) {
        if (profile.count) {
            [self saveProfile:profile home:resolved];
            if (completion) completion(profile, nil);
            return;
        }
        NSDictionary *cached = [self cachedProfileForHome:resolved];
        CALog(CALogLevelWarn, @"ACCOUNT", @"persistent account/read failed reason=%@", error.localizedDescription ?: @"unknown");
        CALog(CALogLevelWarn, @"ACCOUNT", @"account/read response has no account");
        if (completion) completion(cached, error);
    }];
}

#pragma mark - 视图层入口

- (void)readOfficialAccountWithCompletion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    NSString *home = CARuntimePaths.codexHome;
    NSString *bin = [[CACodexEngine sharedEngine] resolveCodexExecutable];
    if (!bin.length) {
        CALog(CALogLevelWarn, @"ACCOUNT", @"account/read skipped: missing codex binary");
        NSDictionary *cached = [CAAccountInfoBridge cachedProfileForHome:home];
        NSError *error = [NSError errorWithDomain:CACodexMetadataErrorDomain
                                             code:404
                                         userInfo:@{ NSLocalizedDescriptionKey: @"missing codex binary" }];
        if (completion) completion(cached, cached ? nil : error);
        return;
    }

    CALog(CALogLevelInfo, @"ACCOUNT", @"requesting account/read on persistent session");
    [CAAccountInfoBridge fetchAccountProfileWithBin:bin home:home completion:^(NSDictionary *profile, NSError *error) {
        if (!profile.count) {
            if (completion) completion(nil, error);
            return;
        }
        NSMutableDictionary *augmented = [profile mutableCopy];
        id cachedAuthenticated = profile[@"authenticated"];
        BOOL wasAuthenticated = [cachedAuthenticated respondsToSelector:@selector(boolValue)] ? [cachedAuthenticated boolValue] : NO;
        augmented[@"authenticated"] = @([[CACodexEngine sharedEngine] isLoggedIn] || wasAuthenticated);
        [CAAccountInfoBridge saveProfile:augmented home:home];
        if (completion) completion(augmented, nil);
    }];
}

- (void)readOfficialAccountOnMainQueueWithCompletion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    if (NSThread.isMainThread) {
        [self readOfficialAccountWithCompletion:completion];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self readOfficialAccountWithCompletion:completion];
    });
}

- (void)fetchAccountProfileWithBin:(NSString *)bin
                              home:(NSString *)home
                        completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    [CAAccountInfoBridge fetchAccountProfileWithBin:bin home:home completion:completion];
}

- (nullable NSDictionary *)profileMetadataAtHome:(NSString *)home
{
    return [CACodexMetadataReader profileMetadataAtHome:home];
}

#pragma mark - 实例缓存转发

- (nullable NSDictionary *)cachedProfileForHome:(NSString *)home
{
    return [CAAccountInfoBridge cachedProfileForHome:home];
}

- (void)saveProfile:(NSDictionary *)profile home:(NSString *)home
{
    [CAAccountInfoBridge saveProfile:profile home:home];
}

- (void)invalidateProfileCacheForHome:(NSString *)home
{
    [CAAccountInfoBridge invalidateProfileCacheForHome:home];
}

@end
