//
//  CARateLimitManager — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSDate;
@class NSDictionary;
@class NSString;

@interface CARateLimitManager : NSObject
    - (bool)available;
    - (id)formattedQuotaReport;
    - (bool)isExpiredSnapshot:(id)arg1;
    - (NSDate *)lastUpdatedAt;
    - (bool)loadingCache;
    - (void)markUnavailableWithReason:(id)arg1;
    - (NSDictionary *)officialSnapshot;
    - (NSString *)planName;
    - (NSString *)quotaBadgeText;
    - (void)recordTurnFinishedWithTokens:(id)arg1;
    - (void)resetSessionTokenCount;
    - (unsigned long long)sessionTotalTokens;
    - (void)setAvailable:(id)arg1;
    - (void)setLastUpdatedAt:(id)arg1;
    - (void)setLoadingCache:(id)arg1;
    - (void)setOfficialSnapshot:(id)arg1;
    - (void)setPlanName:(id)arg1;
    - (void)setQuotaBadgeText:(id)arg1;
    - (void)setSessionTotalTokens:(id)arg1;
    - (void)setSnapshot:(id)arg1;
    - (void)setUnavailableReason:(id)arg1;
    - (id)sharedManager;
    - (NSDictionary *)snapshot;
    - (id)snapshotCachePath;
    - (NSString *)unavailableReason;
    - (void)updateWithServerSnapshot:(id)arg1;
    - (id)windowReport:(id)arg1 title:(id)arg2;

@end

NS_ASSUME_NONNULL_END
