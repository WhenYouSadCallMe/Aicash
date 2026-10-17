//
//  CAModelPricingManager.m — 模型价格目录 / 汇率 / 成本统计 + 第三方模型目录写入
//
//  数据源（全部 https，NSURLSession，失败只记日志）：
//    https://models.dev/catalog.json                                            （cost 为 USD / 1M tokens）
//    https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json（USD / token）
//    https://openrouter.ai/api/v1/models                                        （pricing 为 USD / token 字符串）
//    https://api.frankfurter.dev/v2/rate/usd/cny                                （汇率，缓存键 CAModelPricingUSDToCNYRate）
//  本地文件：<support>/Usage/model-pricing-v1.json、<support>/Usage/cost-history-v1.json
//  原包文案：model pricing synced models=%lu reasoning=%lu sources=models.dev,litellm,openrouter /
//            model pricing sync failed reason=%@ / USD/CNY reference rate refreshed rate=%.6f /
//            USD/CNY reference rate refresh failed status=%ld reason=%@; keeping rate=%.6f /
//            invalid response / HTTP %ld / cost history persist failed turn=%@ /
//            turn cost not recorded turn=%@ model=%@ mainInput=%@ mainOutput=%@ childSamples=%lu (missing usage or unpriced model) /
//            third-party native model catalog main=%@ models=%lu compatibility=%lu path=%@
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CAModelPricingManager.h"

#import <math.h>

NSNotificationName const CAModelPricingDidChangeNotification = @"CAModelPricingDidChangeNotification";
NSNotificationName const CAModelCostDidChangeNotification    = @"CAModelCostDidChangeNotification";

NSString *const CAModelPricingUSDToCNYRateKey            = @"CAModelPricingUSDToCNYRate";
NSString *const CAModelPricingUSDToCNYRateUpdatedAtKey   = @"CAModelPricingUSDToCNYRateUpdatedAt";

static NSString * const kCAPricingCacheFileName      = @"model-pricing-v1.json";
static NSString * const kCAPricingCostHistoryName    = @"cost-history-v1.json";
static NSString * const kCAPricingUsageDirectoryName = @"Usage";
static const NSTimeInterval kCAPricingExchangeRateTTL = 24 * 60 * 60;

#pragma mark - 工具

/// 美元单价换算：models.dev 用 USD/1M tokens，litellm / openrouter 用 USD/token
static NSNumber *CAPricingRateValue(id raw, double divisor)
{
    if (![raw respondsToSelector:@selector(doubleValue)]) return nil;
    double value = [raw doubleValue];
    if (!(value > 0)) return nil;
    return @(value / divisor);
}

static NSNumber *CAPricingJSONNumber(id raw)
{
    if ([raw respondsToSelector:@selector(doubleValue)]) return @([raw doubleValue]);
    return nil;
}

/// 原包模型名归一化：去 provider 前缀与 thinking/level 后缀
static NSString *CAPricingNormalizedModelName(NSString *name)
{
    NSString *value = name.lowercaseString ?: @"";
    NSArray<NSString *> *prefixes = @[ @"models/", @"openai/", @"google/", @"google-ai-studio/", @"gemini/",
                                       @"vertex_ai/", @"vertex-ai/", @"anthropic/", @"deepseek/", @"mistral/",
                                       @"cohere/", @"groq/", @"openrouter/" ];
    for (NSString *prefix in prefixes) {
        if ([value hasPrefix:prefix]) value = [value substringFromIndex:prefix.length];
    }
    NSArray<NSString *> *suffixes = @[ @"-thinking", @"-think", @":thinking", @"-high", @":high" ];
    for (NSString *suffix in suffixes) {
        if ([value hasSuffix:suffix] && value.length > suffix.length) {
            value = [value substringToIndex:value.length - suffix.length];
        }
    }
    return value;
}

static NSString *CAModelCatalogDisplayNameFromSlug(NSString *slug)
{
    if (!slug.length) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [slug componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_ "]]) {
        if (!part.length) continue;
        NSString *lowered = part.lowercaseString;
        if ([lowered isEqualToString:@"gpt"] || [lowered isEqualToString:@"api"]) {
            [parts addObject:lowered.uppercaseString];
        } else {
            [parts addObject:lowered.capitalizedString];
        }
    }
    return parts.count ? [parts componentsJoinedByString:@"-"] : slug;
}

#pragma mark - 价格 / 成本

@interface CAModelPricingManager ()

@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSDictionary *> *prices;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSArray<NSString *> *> *reasoningEfforts;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *costHistory;
@property (nonatomic, assign, readwrite) NSUInteger modelCount;
@property (nonatomic, strong, readwrite, nullable) NSDate *lastUpdatedAt;
@property (nonatomic, assign, readwrite) BOOL refreshing;
@property (nonatomic, assign, readwrite) double usdToCNYRate;
@property (nonatomic, strong, readwrite, nullable) NSDate *exchangeRateUpdatedAt;
@property (nonatomic, assign) BOOL exchangeRateRefreshing;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *confirmedAliases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *candidateCache;

- (NSDictionary<NSString *, NSDictionary *> *)liteLLMCatalogFromJSON:(id)json;
- (void)fetchPricingURL:(NSString *)urlString completion:(void (^)(id _Nullable json, NSError *_Nullable error))completion;
- (void)persistCostHistory;

@end

@implementation CAModelPricingManager

#pragma mark - 原包占位选择器实现（此前只声明未实现）

/// 模型价格候选：从已加载的价目表里取同族候选（slug 归一化后前缀匹配）
- (id)pricingCandidatesForModel:(id)arg1 providerHint:(id)arg2 limit:(id)arg3
{
    NSString *slug = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 lowercaseString] : @"";
    NSInteger maxCount = [arg3 respondsToSelector:@selector(integerValue)] ? [arg3 integerValue] : 5;
    if (maxCount <= 0) maxCount = 5;
    if (slug.length == 0) return @[];

    NSDictionary<NSString *, NSDictionary *> *table = self.prices ?: @{};
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (NSString *key in table) {
        if (![key isKindOfClass:NSString.class]) continue;
        if ([key.lowercaseString isEqualToString:slug]) {
            [candidates insertObject:table[key] atIndex:0];
        } else if ([key.lowercaseString containsString:slug] || [slug containsString:key.lowercaseString]) {
            [candidates addObject:table[key]];
        }
        if ((NSInteger)candidates.count >= maxCount) break;
    }
    return candidates;
}

/// 价目表模糊搜索（设置页价格库搜索用）
- (id)pricingEntriesMatchingQuery:(id)arg1 limit:(id)arg2
{
    NSString *query = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 lowercaseString] : @"";
    NSInteger maxCount = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 30;
    if (maxCount <= 0) maxCount = 30;

    NSDictionary<NSString *, NSDictionary *> *table = self.prices ?: @{};
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    for (NSString *key in table) {
        if (![key isKindOfClass:NSString.class]) continue;
        if (query.length > 0 && [key.lowercaseString rangeOfString:query].location == NSNotFound) continue;
        [results addObject:table[key]];
        if ((NSInteger)results.count >= maxCount) break;
    }
    return results;
}



+ (instancetype)sharedManager
{
    static CAModelPricingManager *manager; static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [CAModelPricingManager new]; });
    return manager;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _prices = @{};
        _reasoningEfforts = @{};
        _costHistory = @[];
        _modelCount = 0;
        _confirmedAliases = [NSMutableDictionary dictionary];
        _candidateCache = [NSMutableDictionary dictionary];
        _usdToCNYRate = [[NSUserDefaults standardUserDefaults] doubleForKey:CAModelPricingUSDToCNYRateKey];
        NSNumber *storedAt = [[NSUserDefaults standardUserDefaults] objectForKey:CAModelPricingUSDToCNYRateUpdatedAtKey];
        if (storedAt.doubleValue > 0) _exchangeRateUpdatedAt = [NSDate dateWithTimeIntervalSince1970:storedAt.doubleValue];
        [self loadCache];
    }
    return self;
}

#pragma mark - 路径

- (NSString *)usageDirectory
{
    // 原包：Library/Application Support/Usage
    return [CARuntimePaths.supportDirectory stringByAppendingPathComponent:kCAPricingUsageDirectoryName];
}

- (NSString *)cachePath
{
    return [[self usageDirectory] stringByAppendingPathComponent:kCAPricingCacheFileName];
}

- (NSString *)costHistoryPath
{
    return [[self usageDirectory] stringByAppendingPathComponent:kCAPricingCostHistoryName];
}

#pragma mark - 缓存

- (void)loadCache
{
    NSData *data = [NSData dataWithContentsOfFile:[self cachePath]];
    if (data.length) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([json isKindOfClass:NSDictionary.class]) {
            NSDictionary *payload = json;
            NSDictionary *prices = [payload[@"prices"] isKindOfClass:NSDictionary.class] ? payload[@"prices"] : @{};
            NSDictionary *efforts = [payload[@"reasoningEfforts"] isKindOfClass:NSDictionary.class] ? payload[@"reasoningEfforts"] : @{};
            self.prices = prices;
            self.reasoningEfforts = efforts;
            self.modelCount = prices.count;
            NSNumber *updatedAt = [payload[@"updatedAt"] respondsToSelector:@selector(doubleValue)] ? @([payload[@"updatedAt"] doubleValue]) : nil;
            if (updatedAt.doubleValue > 0) self.lastUpdatedAt = [NSDate dateWithTimeIntervalSince1970:updatedAt.doubleValue];
            CALog(CALogLevelInfo, @"USAGE", @"model pricing cache restored models=%lu reasoning=%lu",
                  (unsigned long)prices.count, (unsigned long)efforts.count);
        } else {
            CALog(CALogLevelWarn, @"USAGE", @"invalid response");
        }
    }
    [self loadCostHistory];
}

- (void)loadCostHistory
{
    NSData *data = [NSData dataWithContentsOfFile:[self costHistoryPath]];
    if (!data.length) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if ([json isKindOfClass:NSDictionary.class]) {
        id entries = ((NSDictionary *)json)[@"entries"];
        if ([entries isKindOfClass:NSArray.class]) self.costHistory = entries;
    } else if ([json isKindOfClass:NSArray.class]) {
        self.costHistory = json;
    }
}

- (void)persistCostHistory
{
    NSDictionary *payload = @{ @"entries": self.costHistory ?: @[] };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!data) {
        CALog(CALogLevelWarn, @"USAGE", @"cost history persist failed turn=%@", error.localizedDescription ?: @"invalid payload");
        return;
    }
    if (![CARuntimePaths writeFileAtomically:[self costHistoryPath] contents:data mode:0600 error:&error]) {
        CALog(CALogLevelWarn, @"USAGE", @"cost history persist failed turn=%@", error.localizedDescription ?: @"unknown");
    }
}

- (BOOL)persistCatalog:(NSDictionary<NSString *, NSDictionary *> *)catalog
      reasoningEfforts:(NSDictionary<NSString *, NSArray<NSString *> *> *)reasoningEfforts
             updatedAt:(NSDate *)updatedAt
{
    NSDictionary *payload = @{
        @"prices": catalog ?: @{},
        @"reasoningEfforts": reasoningEfforts ?: @{},
        @"confirmedAliases": self.confirmedAliases ?: @{},
        @"modelCount": @(catalog.count),
        @"updatedAt": @((updatedAt ?: [NSDate date]).timeIntervalSince1970),
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!data) {
        CALog(CALogLevelWarn, @"USAGE", @"model pricing sync failed reason=%@", error.localizedDescription ?: @"invalid payload");
        return NO;
    }
    BOOL ok = [CARuntimePaths writeFileAtomically:[self cachePath] contents:data mode:0600 error:&error];
    if (!ok) {
        CALog(CALogLevelWarn, @"USAGE", @"model pricing sync failed reason=%@", error.localizedDescription ?: @"write failed");
    }
    return ok;
}

#pragma mark - 远端

- (void)fetchPricingURL:(NSString *)urlString completion:(void (^)(id _Nullable, NSError *_Nullable))completion
{
    NSURL *url = [NSURL URLWithString:urlString ?: @""];
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length) {
        NSError *error = [NSError errorWithDomain:@"CodexApp.Pricing" code:400
                                         userInfo:@{ NSLocalizedDescriptionKey: @"insecure url rejected" }];
        if (completion) completion(nil, error);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 30;
    [request setValue:CAUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error || !data.length || (http && http.statusCode >= 400)) {
            CALog(CALogLevelWarn, @"USAGE", @"HTTP %ld", (long)(http ? http.statusCode : 0));
            NSError *failure = error ?: [NSError errorWithDomain:@"CodexApp.Pricing"
                                                            code:(http ? http.statusCode : 0)
                                                        userInfo:@{ NSLocalizedDescriptionKey: @"invalid response" }];
            if (completion) completion(nil, failure);
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (!json) {
            CALog(CALogLevelWarn, @"USAGE", @"invalid response");
            if (completion) completion(nil, [NSError errorWithDomain:@"CodexApp.Pricing" code:422
                                                           userInfo:@{ NSLocalizedDescriptionKey: @"invalid response" }]);
            return;
        }
        if (completion) completion(json, nil);
    }];
    [task resume];
}

- (void)refreshCatalogWithCompletion:(void (^)(NSError *_Nullable))completion
{
    if (self.refreshing) {
        if (completion) completion(nil);
        return;
    }
    self.refreshing = YES;

    NSMutableDictionary<NSString *, NSDictionary *> *merged = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *efforts = [NSMutableDictionary dictionary];
    __block NSUInteger failures = 0;
    dispatch_group_t group = dispatch_group_create();

    for (NSString *urlString in @[ CAPricingModelsDevURL, CAPricingLiteLLMURL, CAPricingOpenRouterURL ]) {
        dispatch_group_enter(group);
        [self fetchPricingURL:urlString completion:^(id json, NSError *error) {
            if (json) {
                if ([urlString isEqualToString:CAPricingModelsDevURL]) {
                    [merged addEntriesFromDictionary:[self modelsDevCatalogFromJSON:json]];
                    [efforts addEntriesFromDictionary:[self modelsDevReasoningEffortsFromJSON:json]];
                } else if ([urlString isEqualToString:CAPricingLiteLLMURL]) {
                    [merged addEntriesFromDictionary:[self liteLLMCatalogFromJSON:json]];
                } else {
                    [merged addEntriesFromDictionary:[self openRouterCatalogFromJSON:json]];
                }
            } else {
                failures += 1;
            }
            dispatch_group_leave(group);
        }];
    }
    [self refreshUSDCNYRateIfNeededForce:NO];

    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        CAModelPricingManager *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.refreshing = NO;

        if (!merged.count) {
            NSError *error = [NSError errorWithDomain:@"CodexApp.Pricing" code:502
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                            [NSString stringWithFormat:@"all pricing sources failed (%lu)", (unsigned long)failures] }];
            CALog(CALogLevelWarn, @"USAGE", @"model pricing sync failed reason=%@", error.localizedDescription);
            if (completion) completion(error);
            return;
        }

        NSDictionary<NSString *, NSDictionary *> *sanitized = [strongSelf sanitizedCatalog:merged];
        strongSelf.prices = sanitized.count ? sanitized : merged;
        strongSelf.reasoningEfforts = efforts;
        strongSelf.modelCount = strongSelf.prices.count;
        strongSelf.lastUpdatedAt = [NSDate date];
        [strongSelf persistCatalog:strongSelf.prices reasoningEfforts:efforts updatedAt:strongSelf.lastUpdatedAt];
        CALog(CALogLevelInfo, @"USAGE", @"model pricing synced models=%lu reasoning=%lu sources=models.dev,litellm,openrouter",
              (unsigned long)strongSelf.prices.count, (unsigned long)efforts.count);
        [[NSNotificationCenter defaultCenter] postNotificationName:CAModelPricingDidChangeNotification object:strongSelf];
        if (completion) completion(nil);
    });
}

#pragma mark - 解析

- (NSDictionary<NSString *, NSDictionary *> *)modelsDevCatalogFromJSON:(id)json
{
    NSMutableDictionary<NSString *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    if (![json isKindOfClass:NSDictionary.class]) return catalog;
    NSDictionary *root = json;
    NSDictionary *providers = [root[@"providers"] isKindOfClass:NSDictionary.class] ? root[@"providers"] : root;

    for (NSString *providerKey in providers) {
        if ([providerKey isEqualToString:@"models"] || [providerKey isEqualToString:@"providers"]) continue;
        id providerValue = providers[providerKey];
        if (![providerValue isKindOfClass:NSDictionary.class]) continue;
        id modelsValue = ((NSDictionary *)providerValue)[@"models"];
        if (![modelsValue isKindOfClass:NSDictionary.class]) continue;

        for (NSString *modelKey in (NSDictionary *)modelsValue) {
            id modelValue = ((NSDictionary *)modelsValue)[modelKey];
            if (![modelValue isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *model = modelValue;
            NSDictionary *cost = [model[@"cost"] isKindOfClass:NSDictionary.class] ? model[@"cost"] : @{};
            NSDictionary *limit = [model[@"limit"] isKindOfClass:NSDictionary.class] ? model[@"limit"] : @{};
            NSString *modelID = [model[@"id"] isKindOfClass:NSString.class] ? model[@"id"] : modelKey;

            NSMutableDictionary *record = [NSMutableDictionary dictionary];
            record[@"inputRate"]      = CAPricingRateValue(cost[@"input"], 1000000.0);
            record[@"outputRate"]     = CAPricingRateValue(cost[@"output"], 1000000.0);
            record[@"cacheReadRate"]  = CAPricingRateValue(cost[@"cache_read"], 1000000.0);
            record[@"cacheWriteRate"] = CAPricingRateValue(cost[@"cache_write"], 1000000.0);
            record[@"reasoningRate"]  = CAPricingRateValue(cost[@"reasoning"], 1000000.0) ?: record[@"outputRate"];
            record[@"max_input_tokens"]  = CAPricingJSONNumber(limit[@"context"]);
            record[@"max_output_tokens"] = CAPricingJSONNumber(limit[@"output"]);
            record[@"litellm_provider"]  = providerKey;
            record[@"_pricing_source"]   = @"models.dev";
            record[@"_source_model_id"]  = modelID;
            record[@"_canonical_model_id"] = [NSString stringWithFormat:@"%@/%@", providerKey, modelID];
            record[@"pricingUpdatedAt"]  = @([NSDate date].timeIntervalSince1970);

            NSMutableDictionary *clean = [NSMutableDictionary dictionary];
            [record enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                if (value == nil || value == [NSNull null]) return;
                clean[key] = value;
            }];
            if (clean.count > 4) {
                catalog[[NSString stringWithFormat:@"%@/%@", providerKey, modelID]] = clean;
            }
        }
    }
    return catalog;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)modelsDevReasoningEffortsFromJSON:(id)json
{
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *efforts = [NSMutableDictionary dictionary];
    if (![json isKindOfClass:NSDictionary.class]) return efforts;
    NSDictionary *root = json;
    NSDictionary *providers = [root[@"providers"] isKindOfClass:NSDictionary.class] ? root[@"providers"] : root;

    for (NSString *providerKey in providers) {
        id providerValue = providers[providerKey];
        if (![providerValue isKindOfClass:NSDictionary.class]) continue;
        id modelsValue = ((NSDictionary *)providerValue)[@"models"];
        if (![modelsValue isKindOfClass:NSDictionary.class]) continue;

        for (NSString *modelKey in (NSDictionary *)modelsValue) {
            NSDictionary *model = ((NSDictionary *)modelsValue)[modelKey];
            if (![model isKindOfClass:NSDictionary.class]) continue;
            id options = model[@"reasoning_options"];
            if (![options isKindOfClass:NSArray.class]) continue;
            NSMutableArray<NSString *> *levels = [NSMutableArray array];
            for (id option in (NSArray *)options) {
                if (![option isKindOfClass:NSDictionary.class]) continue;
                id values = ((NSDictionary *)option)[@"values"];
                if ([values isKindOfClass:NSArray.class]) {
                    for (id level in (NSArray *)values) {
                        if ([level isKindOfClass:NSString.class] && [level length]) [levels addObject:level];
                    }
                }
            }
            if (!levels.count) continue;
            NSString *modelID = [model[@"id"] isKindOfClass:NSString.class] ? model[@"id"] : modelKey;
            efforts[[NSString stringWithFormat:@"%@/%@", providerKey, modelID]] = levels;
        }
    }
    return efforts;
}

- (NSDictionary<NSString *, NSDictionary *> *)liteLLMCatalogFromJSON:(id)json
{
    NSMutableDictionary<NSString *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    if (![json isKindOfClass:NSDictionary.class]) return catalog;

    for (NSString *modelKey in (NSDictionary *)json) {
        NSDictionary *entry = ((NSDictionary *)json)[modelKey];
        if (![entry isKindOfClass:NSDictionary.class]) continue;

        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"inputRate"]      = CAPricingRateValue(entry[@"input_cost_per_token"], 1.0);
        record[@"outputRate"]     = CAPricingRateValue(entry[@"output_cost_per_token"], 1.0);
        record[@"cacheReadRate"]  = CAPricingRateValue(entry[@"cache_read_input_token_cost"], 1.0);
        record[@"cacheWriteRate"] = CAPricingRateValue(entry[@"cache_creation_input_token_cost"], 1.0);
        record[@"reasoningRate"]  = CAPricingRateValue(entry[@"output_cost_per_reasoning_token"], 1.0) ?: record[@"outputRate"];
        record[@"max_input_tokens"]  = CAPricingJSONNumber(entry[@"max_input_tokens"]);
        record[@"max_output_tokens"] = CAPricingJSONNumber(entry[@"max_output_tokens"]);
        if ([entry[@"litellm_provider"] isKindOfClass:NSString.class]) record[@"litellm_provider"] = entry[@"litellm_provider"];
        record[@"_pricing_source"]  = @"litellm";
        record[@"_source_model_id"] = modelKey;
        record[@"pricingUpdatedAt"] = @([NSDate date].timeIntervalSince1970);

        BOOL priced = (record[@"inputRate"] != nil || record[@"outputRate"] != nil);
        if (!priced) continue;
        catalog[modelKey] = record;
    }
    return catalog;
}

- (NSDictionary<NSString *, NSDictionary *> *)openRouterCatalogFromJSON:(id)json
{
    NSMutableDictionary<NSString *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    NSArray *data = nil;
    if ([json isKindOfClass:NSDictionary.class]) {
        id raw = ((NSDictionary *)json)[@"data"];
        if ([raw isKindOfClass:NSArray.class]) data = raw;
    } else if ([json isKindOfClass:NSArray.class]) {
        data = json;
    }

    for (id entry in data) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *model = entry;
        NSString *identifier = [model[@"id"] isKindOfClass:NSString.class] ? model[@"id"] : nil;
        if (!identifier.length) continue;
        NSDictionary *pricing = [model[@"pricing"] isKindOfClass:NSDictionary.class] ? model[@"pricing"] : @{};

        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"inputRate"]      = CAPricingRateValue(pricing[@"prompt"], 1.0);
        record[@"outputRate"]     = CAPricingRateValue(pricing[@"completion"], 1.0);
        record[@"cacheReadRate"]  = CAPricingRateValue(pricing[@"input_cache_read"], 1.0);
        record[@"cacheWriteRate"] = CAPricingRateValue(pricing[@"input_cache_write"], 1.0);
        record[@"reasoningRate"]  = CAPricingRateValue(pricing[@"internal_reasoning"], 1.0) ?: record[@"outputRate"];
        record[@"max_input_tokens"] = CAPricingJSONNumber(model[@"context_length"]);
        record[@"_pricing_source"]  = @"openrouter";
        record[@"_source_model_id"] = identifier;
        record[@"pricingUpdatedAt"] = @([NSDate date].timeIntervalSince1970);
        if ([model[@"name"] isKindOfClass:NSString.class]) record[@"display_name"] = model[@"name"];

        if (record[@"inputRate"] == nil && record[@"outputRate"] == nil) continue;
        catalog[[NSString stringWithFormat:@"openrouter/%@", identifier]] = record;
    }
    return catalog;
}

- (NSDictionary<NSString *, NSDictionary *> *)sanitizedCatalog:(NSDictionary *)catalog
{
    NSMutableDictionary<NSString *, NSDictionary *> *clean = [NSMutableDictionary dictionary];
    for (id key in catalog) {
        if (![key isKindOfClass:NSString.class]) continue;
        if ([key hasPrefix:@"_"]) continue;
        id value = catalog[key];
        if (![value isKindOfClass:NSDictionary.class]) continue;

        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        for (id subKey in (NSDictionary *)value) {
            if (![subKey isKindOfClass:NSString.class]) continue;
            if ([subKey hasPrefix:@"_"]) continue;
            id subValue = ((NSDictionary *)value)[subKey];
            if (![subValue isKindOfClass:NSNumber.class] && ![subValue isKindOfClass:NSString.class]) continue;
            record[subKey] = subValue;
        }
        if (record.count) clean[key] = record;
    }
    return clean;
}

#pragma mark - 汇率

- (void)refreshUSDCNYRateIfNeededForce:(BOOL)force
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSNumber *storedRate = [defaults objectForKey:CAModelPricingUSDToCNYRateKey];
    NSNumber *storedAt = [defaults objectForKey:CAModelPricingUSDToCNYRateUpdatedAtKey];
    if (storedRate.doubleValue > 0) self.usdToCNYRate = storedRate.doubleValue;
    if (storedAt.doubleValue > 0) self.exchangeRateUpdatedAt = [NSDate dateWithTimeIntervalSince1970:storedAt.doubleValue];

    if (!force && self.exchangeRateUpdatedAt && -self.exchangeRateUpdatedAt.timeIntervalSinceNow < kCAPricingExchangeRateTTL) return;
    if (self.exchangeRateRefreshing) return;
    self.exchangeRateRefreshing = YES;

    NSURL *url = [NSURL URLWithString:CARateUSDCNYURL];
    if (!url) {
        self.exchangeRateRefreshing = NO;
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 20;
    [request setValue:CAUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        double rate = 0;
        if ([json isKindOfClass:NSDictionary.class]) {
            id rates = ((NSDictionary *)json)[@"rates"];
            if ([rates isKindOfClass:NSDictionary.class] && [rates[@"CNY"] respondsToSelector:@selector(doubleValue)]) {
                rate = [rates[@"CNY"] doubleValue];
            } else if ([((NSDictionary *)json)[@"rate"] respondsToSelector:@selector(doubleValue)]) {
                rate = [((NSDictionary *)json)[@"rate"] doubleValue];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            CAModelPricingManager *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.exchangeRateRefreshing = NO;
            if (error || rate <= 0) {
                CALog(CALogLevelWarn, @"USAGE",
                      @"USD/CNY reference rate refresh failed status=%ld reason=%@; keeping rate=%.6f",
                      (long)(http ? http.statusCode : 0),
                      error.localizedDescription ?: @"invalid response",
                      strongSelf.usdToCNYRate);
                return;
            }
            strongSelf.usdToCNYRate = rate;
            strongSelf.exchangeRateUpdatedAt = [NSDate date];
            [defaults setDouble:rate forKey:CAModelPricingUSDToCNYRateKey];
            [defaults setDouble:strongSelf.exchangeRateUpdatedAt.timeIntervalSince1970 forKey:CAModelPricingUSDToCNYRateUpdatedAtKey];
            CALog(CALogLevelInfo, @"USAGE", @"USD/CNY reference rate refreshed rate=%.6f", rate);
        });
    }];
    [task resume];
}

#pragma mark - 查询

- (nullable NSDictionary *)pricingForModel:(NSString *)model providerHint:(NSString *)providerHint
{
    if (!model.length || !self.prices.count) return nil;
    NSString *matchedKey = nil;
    NSString *reason = nil;
    NSDictionary *record = nil;
    NSString *lowered = model.lowercaseString;

    record = self.prices[model];
    if (record) { matchedKey = model; reason = @"exact-model-id"; }

    if (!record) {
        for (NSString *key in self.prices) {
            if ([key.lowercaseString isEqualToString:lowered]) {
                record = self.prices[key]; matchedKey = key; reason = @"case-insensitive-model-id";
                break;
            }
        }
    }
    if (!record && providerHint.length) {
        NSString *candidate = [NSString stringWithFormat:@"%@/%@", providerHint.lowercaseString, lowered];
        for (NSString *key in self.prices) {
            if ([key.lowercaseString isEqualToString:candidate]) {
                record = self.prices[key]; matchedKey = key; reason = @"same-model-with-provider-prefix";
                break;
            }
        }
    }
    if (!record) {
        NSString *normalized = CAPricingNormalizedModelName(model);
        for (NSString *key in self.prices) {
            NSString *normalizedKey = CAPricingNormalizedModelName(key);
            if ([normalizedKey isEqualToString:normalized]) {
                record = self.prices[key]; matchedKey = key; reason = @"normalized-model-name";
                break;
            }
        }
    }
    if (!record) {
        NSString *normalized = CAPricingNormalizedModelName(model);
        for (NSString *key in self.prices) {
            NSString *normalizedKey = CAPricingNormalizedModelName(key);
            if (normalizedKey.length > 3 && [normalized hasPrefix:normalizedKey]) {
                record = self.prices[key]; matchedKey = key; reason = @"normalized-name-contains";
                break;
            }
            if (normalized.length > 3 && [normalizedKey hasPrefix:normalized]) {
                record = self.prices[key]; matchedKey = key; reason = @"model-name-contains";
                break;
            }
        }
    }
    if (!record) return nil;

    NSMutableDictionary *result = [record mutableCopy];
    result[@"matchedModel"] = matchedKey ?: model;
    result[@"_match_reason"] = reason ?: @"weak-similarity";
    result[@"_pricing_key"] = matchedKey ?: model;
    return result;
}

- (NSArray<NSString *> *)supportedReasoningEffortsForModel:(NSString *)model providerHint:(NSString *)providerHint
{
    if (!model.length) return @[];
    NSArray<NSString *> *levels = self.reasoningEfforts[model];
    if (!levels.count && providerHint.length) {
        levels = self.reasoningEfforts[[NSString stringWithFormat:@"%@/%@", providerHint, model]];
    }
    if (!levels.count) {
        NSString *normalized = CAPricingNormalizedModelName(model);
        for (NSString *key in self.reasoningEfforts) {
            if ([CAPricingNormalizedModelName(key) isEqualToString:normalized]) {
                levels = self.reasoningEfforts[key];
                break;
            }
        }
    }
    if (!levels.count) {
        NSDictionary *pricing = [self pricingForModel:model providerHint:providerHint];
        if (pricing) levels = [CAThirdPartyModelCatalog reasoningLevels];
    }
    return levels ?: @[];
}

#pragma mark - 成本

- (void)recordUsage:(NSDictionary *)usage model:(NSString *)model providerHint:(NSString *)providerHint
{
    if (![usage isKindOfClass:NSDictionary.class]) return;
    double input = [usage[@"input_tokens"] respondsToSelector:@selector(doubleValue)] ? [usage[@"input_tokens"] doubleValue] : 0;
    double cached = [usage[@"cached_input_tokens"] respondsToSelector:@selector(doubleValue)] ? [usage[@"cached_input_tokens"] doubleValue] : 0;
    double output = [usage[@"output_tokens"] respondsToSelector:@selector(doubleValue)] ? [usage[@"output_tokens"] doubleValue] : 0;
    double reasoning = [usage[@"reasoning_output_tokens"] respondsToSelector:@selector(doubleValue)] ? [usage[@"reasoning_output_tokens"] doubleValue] : 0;
    NSString *turnId = [usage[@"turn_id"] isKindOfClass:NSString.class] ? usage[@"turn_id"] : [[NSUUID UUID] UUIDString];

    NSDictionary *pricing = [self pricingForModel:model ?: @"" providerHint:providerHint];
    if (!pricing) {
        CALog(CALogLevelWarn, @"USAGE",
              @"turn cost not recorded turn=%@ model=%@ mainInput=%@ mainOutput=%@ childSamples=%lu (missing usage or unpriced model)",
              turnId, model ?: @"(none)", usage[@"input_tokens"] ?: @0, usage[@"output_tokens"] ?: @0, (unsigned long)0);
        return;
    }

    double inputRate = [pricing[@"inputRate"] doubleValue];
    double outputRate = [pricing[@"outputRate"] doubleValue];
    double cacheReadRate = pricing[@"cacheReadRate"] ? [pricing[@"cacheReadRate"] doubleValue] : inputRate;
    double cacheWriteRate = pricing[@"cacheWriteRate"] ? [pricing[@"cacheWriteRate"] doubleValue] : inputRate;
    double reasoningRate = pricing[@"reasoningRate"] ? [pricing[@"reasoningRate"] doubleValue] : outputRate;

    double usd = (input * inputRate) + (cached * cacheReadRate) + (output * outputRate) + (reasoning * reasoningRate);
    NSString *billingMode = [usage[@"billing_mode"] isKindOfClass:NSString.class] ? usage[@"billing_mode"] : @"api";

    NSDictionary *entry = @{
        @"turnId": turnId,
        @"model": model ?: @"",
        @"matchedModel": pricing[@"matchedModel"] ?: model ?: @"",
        @"amountUSD": @(usd),
        @"mainAmountUSD": @(usd),
        @"subagentAmountUSD": @0,
        @"subagentCount": @0,
        @"billingMode": billingMode,
        @"inputRate": @(inputRate),
        @"outputRate": @(outputRate),
        @"cacheReadRate": @(cacheReadRate),
        @"cacheWriteRate": @(cacheWriteRate),
        @"reasoningRate": @(reasoningRate),
        @"requestCount": @1,
        @"pricingUpdatedAt": pricing[@"pricingUpdatedAt"] ?: @0,
        @"timestamp": @([NSDate date].timeIntervalSince1970),
    };
    self.costHistory = [self.costHistory arrayByAddingObject:entry];
    [self persistCostHistory];

    CALog(CALogLevelInfo, @"USAGE",
          @"turn cost recorded turn=%@ mode=%@ model=%@ usd=%.6f mainUSD=%.6f childUSD=%.6f childTurns=%lu mainInput=%@ mainCached=%@ mainOutput=%@ mainRequests=%lu",
          turnId, billingMode, model ?: @"(none)", usd, usd, 0.0, (unsigned long)0,
          usage[@"input_tokens"] ?: @0, usage[@"cached_input_tokens"] ?: @0, usage[@"output_tokens"] ?: @0, (unsigned long)1);
    [[NSNotificationCenter defaultCenter] postNotificationName:CAModelCostDidChangeNotification object:self];
}

- (NSDictionary *)costSummaryForBillingMode:(NSString *)billingMode
{
    NSDate *startOfDay = [NSCalendar.currentCalendar startOfDayForDate:[NSDate date]];
    double todayUSD = 0;
    double totalUSD = 0;
    NSUInteger todayTurns = 0;
    NSUInteger totalTurns = 0;
    for (NSDictionary *entry in self.costHistory) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if (billingMode.length && ![entry[@"billingMode"] isEqual:billingMode]) continue;
        double amount = [entry[@"amountUSD"] doubleValue];
        totalUSD += amount;
        totalTurns += 1;
        NSNumber *timestamp = [entry[@"timestamp"] respondsToSelector:@selector(doubleValue)] ? entry[@"timestamp"] : nil;
        if (timestamp) {
            NSDate *recordedAt = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
            if ([recordedAt compare:startOfDay] != NSOrderedAscending) {
                todayUSD += amount;
                todayTurns += 1;
            }
        }
    }
    return @{ @"todayUSD": @(todayUSD), @"totalUSD": @(totalUSD),
              @"todayTurns": @(todayTurns), @"totalTurns": @(totalTurns) };
}

#pragma mark - 展示

+ (NSString *)displayUSD:(double)amount
{
    if (amount == 0) return @"$0.000";
    double magnitude = fabs(amount);
    if (magnitude < 0.01) return [NSString stringWithFormat:@"$%.5f", amount];
    if (magnitude < 1)    return [NSString stringWithFormat:@"$%.3f", amount];
    return [NSString stringWithFormat:@"$%.2f", amount];
}

+ (NSString *)displayCNYFromUSD:(double)amount
{
    double rate = [CAModelPricingManager sharedManager].usdToCNYRate;
    if (!(rate > 0)) return nil;
    double cny = amount * rate;
    if (fabs(cny) < 1) return [NSString stringWithFormat:@"¥%.3f", cny];
    return [NSString stringWithFormat:@"¥%.2f", cny];
}

@end

#pragma mark - 第三方模型目录

@implementation CAThirdPartyModelCatalog

+ (NSArray<NSString *> *)reasoningLevels
{
    // 原版顺序；Auto 由调用方在最前追加（0 = 服务默认）
    return @[ @"auto", @"none", @"minimal", @"low", @"medium", @"high", @"xhigh", @"max" ];
}

+ (NSString *)reasoningLevelTitle:(NSString *)level
{
    static NSDictionary<NSString *, NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 短标签与原版 __cstring 一致：Auto/None/Minimal/Low/Med/High/xHigh/Max
        titles = @{
            @"auto":    @"Auto",
            @"none":    @"None",
            @"minimal": @"Minimal",
            @"low":     @"Low",
            @"medium":  @"Med",
            @"high":    @"High",
            @"xhigh":   @"xHigh",
            @"max":     @"Max",
            @"ultra":   @"Max",
        };
    });
    NSString *key = level.lowercaseString ?: @"";
    NSString *title = titles[key];
    if (title.length) return title;
    return level.length ? level.capitalizedString : @"";
}

+ (NSString *)fallbackInstructions
{
    // 原包内嵌 codex-fallback-prompt.md（bundle 根目录）
    NSString *path = [NSBundle.mainBundle pathForResource:@"codex-fallback-prompt" ofType:@"md"];
    NSString *text = path.length ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (text.length) return text;
    return @"You are a coding agent running on iOS through CodexApp. Use the provided tools and keep changes minimal.";
}

+ (NSDictionary *)modelInfoForSlug:(NSString *)slug
                      instructions:(NSString *)instructions
                     contextWindow:(NSUInteger)contextWindow
                          priority:(NSInteger)priority
                          enhanced:(BOOL)enhanced
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"slug"] = slug ?: @"";
    info[@"display_name"] = CAModelCatalogDisplayNameFromSlug(slug);
    info[@"description"] = enhanced ? @"Codex CLI native tools" : @"third-party compatibility";
    info[@"context_window"] = @(contextWindow);
    info[@"max_context_window"] = @(contextWindow);
    info[@"effective_context_window_percent"] = @95;
    info[@"supports_reasoning"] = @YES;
    info[@"supported_levels"] = [self reasoningLevels];
    info[@"supported_reasoning_levels"] = [self reasoningLevels];
    info[@"default_level"] = @"medium";
    info[@"default_reasoning_level"] = @"medium";
    info[@"shell_type"] = @"unified_exec";
    info[@"apply_patch_tool_type"] = @"freeform";
    info[@"include_skills_usage_instructions"] = @YES;
    info[@"include_plugin_usage_instructions"] = @YES;
    info[@"include_apps_usage_instructions"] = @YES;
    info[@"priority"] = @(priority);
    NSString *base = instructions.length ? instructions : [self fallbackInstructions];
    if (base.length) info[@"base_instructions"] = base;
    return info;
}

+ (NSDictionary *)catalogObjectForModels:(NSArray<NSDictionary *> *)models
                           selectedModel:(NSString *)slug
                           contextWindow:(NSUInteger)contextWindow
                            instructions:(NSString *)instructions
{
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    for (NSDictionary *model in models) {
        if (![model isKindOfClass:NSDictionary.class]) continue;
        if (model[@"slug"] && model[@"display_name"]) {
            [entries addObject:model];
            continue;
        }
        NSString *modelSlug = [model[@"slug"] isKindOfClass:NSString.class] ? model[@"slug"] : model[@"id"];
        if (!modelSlug.length) continue;
        NSUInteger window = [model[@"context_window"] respondsToSelector:@selector(unsignedIntegerValue)] ? [model[@"context_window"] unsignedIntegerValue] : contextWindow;
        [entries addObject:[self modelInfoForSlug:modelSlug
                                     instructions:instructions
                                    contextWindow:window
                                         priority:(NSInteger)entries.count
                                         enhanced:NO]];
    }
    return @{
        @"models": entries,
        @"selected": slug ?: @"",
        @"context_window": @(contextWindow),
    };
}

+ (BOOL)writeCatalogForModels:(NSArray<NSDictionary *> *)models
                selectedModel:(NSString *)slug
                contextWindow:(NSUInteger)contextWindow
                        error:(NSError **)error
{
    NSDictionary *catalog = [self catalogObjectForModels:models
                                           selectedModel:slug
                                           contextWindow:contextWindow
                                            instructions:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:catalog
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!data) return NO;

    NSString *path = CARuntimePaths.thirdPartyCatalogPath;
    BOOL ok = [CARuntimePaths writeFileAtomically:path contents:data mode:0644 error:error];
    NSUInteger compatibility = 0;
    for (NSDictionary *model in models) {
        if ([model isKindOfClass:NSDictionary.class] && [model[@"description"] isEqual:@"third-party compatibility"]) compatibility += 1;
    }
    CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"RUNTIME",
          @"third-party native model catalog main=%@ models=%lu compatibility=%lu path=%@",
          slug ?: @"(none)", (unsigned long)models.count, (unsigned long)compatibility, path);
    return ok;
}

@end
