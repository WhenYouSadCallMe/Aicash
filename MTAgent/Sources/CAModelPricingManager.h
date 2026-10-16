//
//  CAModelPricingManager.h — 模型目录 / 价格 / 成本统计 + 第三方模型目录（CAThirdPartyModelCatalog）
//
//  原包符号对齐（SPEC/assets/objc_api_map.json → "CAModelPricingManager" / "CAThirdPartyModelCatalog"）：
//    +sharedManager / +displayUSD: / +displayCNYFromUSD: / -refreshCatalogWithCompletion: / -loadCache /
//    -modelsDevCatalogFromJSON: / -openRouterCatalogFromJSON: / -sanitizedCatalog: /
//    -persistCatalog:reasoningEfforts:updatedAt: / -refreshUSDCNYRateIfNeededForce: / -pricingForModel:providerHint: /
//    -supportedReasoningEffortsForModel:providerHint: / -costSummaryForBillingMode: / -cachePath / -costHistoryPath
//    +catalogObjectForModels:selectedModel:contextWindow:instructions: / +fallbackInstructions /
//    +modelInfoForSlug:instructions:contextWindow:priority:enhanced: / +reasoningLevels / +writeCatalogForModels:selectedModel:contextWindow:error:
//  远端（contracts.json urls）：
//    https://models.dev/catalog.json、https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json、
//    https://openrouter.ai/api/v1/models、https://api.frankfurter.dev/v2/rate/usd/cny（汇率缓存键 CAModelPricingUSDToCNYRate）
//  本地文件：model-pricing-v1.json、cost-history-v1.json（原包：Library/Application Support/Usage/…）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const CAModelPricingDidChangeNotification;
extern NSNotificationName const CAModelCostDidChangeNotification;

/// 汇率缓存键（原包观测字面量，勿改）
extern NSString *const CAModelPricingUSDToCNYRateKey;            // CAModelPricingUSDToCNYRate
extern NSString *const CAModelPricingUSDToCNYRateUpdatedAtKey;   // CAModelPricingUSDToCNYRateUpdatedAt

#pragma mark - 价格 / 成本

@interface CAModelPricingManager : NSObject

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary *> *prices;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<NSString *> *> *reasoningEfforts;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *costHistory;
@property (nonatomic, assign, readonly) NSUInteger modelCount;
@property (nonatomic, strong, readonly, nullable) NSDate *lastUpdatedAt;
@property (nonatomic, assign, readonly, getter=isRefreshing) BOOL refreshing;
@property (nonatomic, assign, readonly) double usdToCNYRate;
@property (nonatomic, strong, readonly, nullable) NSDate *exchangeRateUpdatedAt;

+ (instancetype)sharedManager;

#pragma mark 目录刷新

- (void)refreshCatalogWithCompletion:(nullable void (^)(NSError *_Nullable error))completion;
- (void)loadCache;

- (NSDictionary<NSString *, NSDictionary *> *)modelsDevCatalogFromJSON:(id)json;
- (NSDictionary<NSString *, NSArray<NSString *> *> *)modelsDevReasoningEffortsFromJSON:(id)json;
- (NSDictionary<NSString *, NSDictionary *> *)openRouterCatalogFromJSON:(id)json;
- (NSDictionary<NSString *, NSDictionary *> *)sanitizedCatalog:(NSDictionary *)catalog;

- (BOOL)persistCatalog:(NSDictionary<NSString *, NSDictionary *> *)catalog
      reasoningEfforts:(NSDictionary<NSString *, NSArray<NSString *> *> *)reasoningEfforts
             updatedAt:(NSDate *)updatedAt;

- (NSString *)cachePath;
- (NSString *)costHistoryPath;

#pragma mark 汇率 / 成本

- (void)refreshUSDCNYRateIfNeededForce:(BOOL)force;
- (void)recordUsage:(NSDictionary *)usage
              model:(nullable NSString *)model
       providerHint:(nullable NSString *)providerHint;
- (NSDictionary *)costSummaryForBillingMode:(nullable NSString *)billingMode;

#pragma mark 查询

- (nullable NSDictionary *)pricingForModel:(NSString *)model providerHint:(nullable NSString *)providerHint;
- (NSArray<NSString *> *)supportedReasoningEffortsForModel:(NSString *)model providerHint:(nullable NSString *)providerHint;

#pragma mark 展示

+ (NSString *)displayUSD:(double)amount;
+ (nullable NSString *)displayCNYFromUSD:(double)amount;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, assign) BOOL exchangeRateRefreshing;
    @property (nonatomic, strong, nullable) NSObject<OS_dispatch_queue> * queue;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)appendGlobalCostEntry:(id)arg1 record:(id)arg2;
    - (id)clearConfirmedPricingForModel:(id)arg1;
    - (id)confirmPricingCandidateForModel:(id)arg1 pricingKey:(id)arg2;
    - (id)conversationEstimatedCostUSD:(id)arg1;
    - (id)estimateCurrentTurnForEngine:(id)arg1;
    - (id)estimateUsage:(id)arg1 model:(id)arg2 providerHint:(id)arg3;
    - (id)estimateUsageSamples:(id)arg1 fallback:(id)arg2 model:(id)arg3 providerHint:(id)arg4;
    - (id)latestTurnCostForRecord:(id)arg1;
    - (id)persistCurrentPricingState;
    - (id)prepareDisplaySnapshotForModels:(id)arg1 providerHint:(id)arg2 completion:(id)arg3;
    - (id)pricingCandidatesForModel:(id)arg1 providerHint:(id)arg2 limit:(id)arg3;
    - (id)pricingEntriesMatchingQuery:(id)arg1 limit:(id)arg2;
    - (id)recordCompletedTurnForEngine:(id)arg1 record:(id)arg2;
    - (id)refreshAvailableModelsAndPricingWithCompletion:(id)arg1;
    - (id)refreshOfficialModelsForEngine:(id)arg1 completion:(id)arg2;
    - (id)refreshThirdPartyModelsForEngine:(id)arg1 completion:(id)arg2;
    - (id)refreshWithCompletion:(id)arg1;
    - (id)resolvedRecordForKeys:(id)arg1 providerHint:(id)arg2;
    - (id)sanitizedPriceRecord:(id)arg1;
    - (id)setRefreshActive:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

#pragma mark - 第三方模型目录（codex model_catalog_json）

@interface CAThirdPartyModelCatalog : NSObject

/// 原包档位（reasoningEfforts）：minimal / low / medium / high / xhigh / max / ultra
+ (NSArray<NSString *> *)reasoningLevels;
+ (NSString *)reasoningLevelTitle:(NSString *)level;

/// 内嵌 codex-fallback-prompt.md（缺失时用内置兜底文案）
+ (nullable NSString *)fallbackInstructions;

+ (NSDictionary *)modelInfoForSlug:(NSString *)slug
                      instructions:(nullable NSString *)instructions
                     contextWindow:(NSUInteger)contextWindow
                          priority:(NSInteger)priority
                          enhanced:(BOOL)enhanced;

+ (NSDictionary *)catalogObjectForModels:(NSArray<NSDictionary *> *)models
                           selectedModel:(nullable NSString *)slug
                           contextWindow:(NSUInteger)contextWindow
                            instructions:(nullable NSString *)instructions;

+ (BOOL)writeCatalogForModels:(NSArray<NSDictionary *> *)models
                selectedModel:(nullable NSString *)slug
                contextWindow:(NSUInteger)contextWindow
                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
