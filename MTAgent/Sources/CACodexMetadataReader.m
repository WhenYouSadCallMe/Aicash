//
//  CACodexMetadataReader.m — Codex home 只读元数据解析
//
//  解析规则全部来自原包字符串资产：
//    auth.json / tokens / id_token / preferred_username / given_name / picture / image_url / avatar_url /
//    plan_type / chatgpt / .jsonl / sessions / archived_sessions / payload / event_msg / total_token_usage /
//    -agent-metadata / avatarUrl / profile_image_url / profileImageUrl / avatar
//  日志（分类 ACCOUNT）：
//    profile metadata available name=%@ image=%@ / account/read skipped: missing codex binary /
//    account/read completed email=YES plan=%@ / account/read finished without email reason=%@
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CACodexMetadataReader.h"

NSString *const CACodexMetadataErrorDomain = @"CodexApp.Metadata";

static NSString * const kCAMetadataAuthFileName      = @"auth.json";
static NSString * const kCAMetadataSessionsDirName   = @"sessions";
static NSString * const kCAMetadataArchivedDirName   = @"archived_sessions";
static NSString * const kCAMetadataJSONLSuffix       = @".jsonl";
static NSString * const kCAMetadataAgentSuffix       = @"-agent-metadata";

@implementation CACodexMetadataReader

#pragma mark - 基础

+ (NSString *)resolvedHome:(NSString *)home
{
    return home.length ? home : CARuntimePaths.codexHome;
}

+ (NSError *)errorWithCode:(NSInteger)code reason:(NSString *)reason
{
    return [NSError errorWithDomain:CACodexMetadataErrorDomain
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: reason ?: @"metadata unavailable" }];
}

+ (NSDictionary *)JSONDictionaryAtPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

/// JWT payload（base64url 中段）→ 字典
+ (NSDictionary *)jwtPayloadFromToken:(NSString *)token
{
    if (![token isKindOfClass:NSString.class] || !token.length) return nil;
    NSArray<NSString *> *segments = [token componentsSeparatedByString:@"."];
    if (segments.count < 2) return nil;
    NSMutableString *encoded = [segments[1] mutableCopy];
    [encoded replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, encoded.length)];
    [encoded replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, encoded.length)];
    while (encoded.length % 4 != 0) [encoded appendString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (!data.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

+ (NSString *)firstStringInDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys
{
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return nil;
}

#pragma mark - 账号元数据

+ (NSMutableDictionary<NSString *, NSString *> *)profileMetadataAtHome:(NSString *)home
{
    NSMutableDictionary<NSString *, NSString *> *metadata = [NSMutableDictionary dictionary];
    NSString *resolved = [self resolvedHome:home];
    NSString *authPath = [resolved stringByAppendingPathComponent:kCAMetadataAuthFileName];
    NSDictionary *auth = [self JSONDictionaryAtPath:authPath];
    if (!auth) return metadata;

    NSDictionary *tokens = [auth[@"tokens"] isKindOfClass:NSDictionary.class] ? auth[@"tokens"] : nil;
    NSDictionary *payload = [self jwtPayloadFromToken:tokens[@"id_token"] ?: auth[@"id_token"]];
    if (!payload) payload = [self jwtPayloadFromToken:auth[@"access_token"]];

    NSString *userId = [self firstStringInDictionary:payload keys:@[ @"sub", @"user_id", @"userId" ]];
    NSString *displayName = [self firstStringInDictionary:payload keys:@[ @"preferred_username", @"given_name", @"name" ]];
    NSString *email = [self firstStringInDictionary:payload keys:@[ @"email" ]];
    NSString *imageURL = [self firstStringInDictionary:payload keys:@[ @"picture", @"image_url", @"avatar_url", @"avatarUrl", @"profile_image_url", @"profileImageUrl", @"avatar" ]];
    NSString *planType = [self firstStringInDictionary:payload keys:@[ @"chatgpt_plan_type", @"plan_type" ]];

    if (!userId.length) userId = [self firstStringInDictionary:auth keys:@[ @"user_id", @"userId", @"account_id" ]];
    if (!email.length) email = [self firstStringInDictionary:auth keys:@[ @"email" ]];
    if (!planType.length) planType = [self firstStringInDictionary:auth keys:@[ @"chatgpt_plan_type", @"plan_type" ]];
    if (!displayName.length) displayName = [self firstStringInDictionary:auth keys:@[ @"preferred_username", @"given_name", @"displayName", @"name" ]];
    if (!imageURL.length) imageURL = [self firstStringInDictionary:auth keys:@[ @"picture", @"image_url", @"avatar_url", @"avatarUrl" ]];

    if (userId.length) metadata[@"userId"] = userId;
    if (displayName.length) metadata[@"displayName"] = displayName;
    if (email.length) metadata[@"email"] = email;
    if (imageURL.length) metadata[@"imageURL"] = imageURL;
    if (planType.length) metadata[@"planType"] = planType;
    metadata[@"accountType"] = planType.length ? @"chatgpt" : @"unknown";
    metadata[@"authenticated"] = (tokens.count || payload.count) ? @"YES" : @"NO";
    metadata[@"readSucceeded"] = (metadata.count > 0) ? @"YES" : @"NO";

    if (displayName.length || imageURL.length) {
        CALog(CALogLevelInfo, @"ACCOUNT", @"profile metadata available name=%@ image=%@",
              displayName ?: @"(none)", imageURL ?: @"(none)");
    }
    return metadata;
}

#pragma mark - 会话用量

/// 在 JSON 对象里递归寻找 total_token_usage（codex 会话 JSONL：payload.event_msg.info.total_token_usage）
+ (NSDictionary *)totalTokenUsageInObject:(id)object
{
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = object;
        id usage = dictionary[@"total_token_usage"];
        if ([usage isKindOfClass:NSDictionary.class]) return usage;
        for (id value in dictionary.allValues) {
            NSDictionary *found = [self totalTokenUsageInObject:value];
            if (found) return found;
        }
    } else if ([object isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)object) {
            NSDictionary *found = [self totalTokenUsageInObject:value];
            if (found) return found;
        }
    }
    return nil;
}

+ (NSArray<NSString *> *)sessionFileCandidatesForThread:(NSString *)threadId home:(NSString *)home
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *root in @[ [home stringByAppendingPathComponent:kCAMetadataSessionsDirName],
                              [home stringByAppendingPathComponent:kCAMetadataArchivedDirName] ]) {
        NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:root];
        for (NSString *relative in enumerator) {
            if (![relative.lowercaseString hasSuffix:kCAMetadataJSONLSuffix]) continue;
            if (threadId.length && ![relative containsString:threadId] && ![relative containsString:kCAMetadataAgentSuffix]) continue;
            NSString *full = [root stringByAppendingPathComponent:relative];
            [candidates addObject:full];
        }
    }
    return candidates;
}

+ (nullable NSDictionary *)usageMetadataForThread:(NSString *)threadId home:(NSString *)home
{
    if (!threadId.length) return nil;
    NSString *resolved = [self resolvedHome:home];
    NSDictionary *latest = nil;
    NSDate *latestDate = nil;

    for (NSString *path in [self sessionFileCandidatesForThread:threadId home:resolved]) {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (!text.length) continue;
        for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            if (!line.length) continue;
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![json isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *usage = [self totalTokenUsageInObject:json];
            if (!usage) continue;

            NSNumber *timestamp = [json[@"timestamp"] respondsToSelector:@selector(doubleValue)] ? @([json[@"timestamp"] doubleValue]) : nil;
            NSDate *date = timestamp ? [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue] : [NSDate date];
            if (!latestDate || [date compare:latestDate] != NSOrderedAscending) {
                latestDate = date;
                latest = usage;
            }
        }
    }
    if (!latest) return nil;

    NSMutableDictionary *usage = [NSMutableDictionary dictionary];
    for (NSString *key in @[ @"input_tokens", @"cached_input_tokens", @"output_tokens", @"reasoning_output_tokens", @"total_tokens" ]) {
        if (latest[key] != nil) usage[key] = latest[key];
    }
    if (latestDate) usage[@"updatedAt"] = @(latestDate.timeIntervalSince1970);
    return usage.count ? usage : nil;
}

#pragma mark - 读取入口

+ (void)readProfileAtHome:(NSString *)home
               completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    NSString *resolved = [self resolvedHome:home];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *metadata = [self profileMetadataAtHome:resolved];
        NSError *error = metadata.count ? nil
                                        : [self errorWithCode:404 reason:[NSString stringWithFormat:@"%@ missing or unreadable", kCAMetadataAuthFileName]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(metadata.count ? metadata : nil, error);
        });
    });
}

+ (void)readUsageForThread:(NSString *)threadId
                      home:(NSString *)home
                completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    NSString *resolved = [self resolvedHome:home];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *usage = [self usageMetadataForThread:threadId home:resolved];
        NSError *error = usage ? nil : [self errorWithCode:404 reason:@"session usage unavailable"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(usage, error);
        });
    });
}

+ (void)readKind:(NSString *)kind
            home:(NSString *)home
          thread:(NSString *)threadId
      completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    NSString *normalized = kind.lowercaseString ?: @"";
    if ([normalized isEqualToString:@"profile"] || [normalized isEqualToString:@"account"]) {
        [self readProfileAtHome:home completion:completion];
        return;
    }
    if ([normalized isEqualToString:@"usage"] || [normalized isEqualToString:@"tokens"]) {
        if (!threadId.length) {
            if (completion) completion(nil, [self errorWithCode:400 reason:@"usage read requires thread id"]);
            return;
        }
        [self readUsageForThread:threadId home:home completion:completion];
        return;
    }
    if (completion) completion(nil, [self errorWithCode:400 reason:[NSString stringWithFormat:@"unsupported metadata kind: %@", kind ?: @"(null)"]]);
}

#pragma mark - 账号

+ (void)readAccountEmailWithBin:(NSString *)bin
                           home:(NSString *)home
                     completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion
{
    NSString *resolved = [self resolvedHome:home];
    if (!bin.length) {
        CALog(CALogLevelWarn, @"ACCOUNT", @"account/read skipped: missing codex binary");
        if (completion) completion(nil, [self errorWithCode:404 reason:@"missing codex binary"]);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary<NSString *, NSString *> *metadata = [self profileMetadataAtHome:resolved];
        NSString *email = metadata[@"email"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (email.length) {
                CALog(CALogLevelInfo, @"ACCOUNT", @"account/read completed email=YES plan=%@", metadata[@"planType"] ?: @"unknown");
                if (completion) completion(email, nil);
                return;
            }
            CALog(CALogLevelWarn, @"ACCOUNT", @"account/read finished without email reason=%@", @"auth.json has no id_token email claim");
            if (completion) completion(nil, [self errorWithCode:404 reason:@"account/read finished without email"]);
        });
    });
}

+ (void)readAccountProfileWithBin:(NSString *)bin
                             home:(NSString *)home
                       completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion
{
    NSString *resolved = [self resolvedHome:home];
    if (!bin.length) {
        CALog(CALogLevelWarn, @"ACCOUNT", @"account/read skipped: missing codex binary");
        if (completion) completion(nil, [self errorWithCode:404 reason:@"missing codex binary"]);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary *profile = [[self profileMetadataAtHome:resolved] mutableCopy] ?: [NSMutableDictionary dictionary];
        BOOL authenticated = [profile[@"authenticated"] isEqualToString:@"YES"];
        profile[@"authenticated"] = @(authenticated);
        profile[@"readSucceeded"] = @(profile.count > 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (profile.count) {
                CALog(CALogLevelInfo, @"ACCOUNT", @"account/read completed email=%@ plan=%@",
                      profile[@"email"] ? @"YES" : @"NO", profile[@"planType"] ?: @"unknown");
                if (completion) completion(profile, nil);
                return;
            }
            CALog(CALogLevelWarn, @"ACCOUNT", @"account/read finished without email reason=%@", @"auth.json unreadable");
            if (completion) completion(nil, [self errorWithCode:404 reason:@"account profile unavailable"]);
        });
    });
}

@end
