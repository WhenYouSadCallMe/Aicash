//
//  CAAccountInfoBridge.h — 账号信息桥（官方账号读取 + 本地缓存）
//
//  原包符号对齐（SPEC/assets/objc_api_map.json → "CAAccountInfoBridge"）：
//    +augmentProfile:fromCodexHome:completion: / +cacheKeyForHome: / +cachedProfileForHome: /
//    +fetchAccountProfileWithBin:home:completion: / +invalidateProfileCacheForHome: /
//    +readAccountEmailWithBin:home:completion: / +readAccountProfileWithBin:home:completion: / +saveProfile:home:
//  视图层入口（复刻版按调用点补齐的同名实例方法）：
//    -readOfficialAccountWithCompletion: / -readOfficialAccountOnMainQueueWithCompletion: /
//    -fetchAccountProfileWithBin:home:completion: / -cachedProfileForHome: / -saveProfile:home: /
//    -invalidateProfileCacheForHome: / -profileMetadataAtHome:
//
//  缓存键前缀：CADefaultsAccountProfilePrefix = "CodexAccountProfile.v2."（原包观测）
//  原包文案：reading account via persistent app-server home=%@ / requestng account/read on persistent session /
//            account/read completed email=YES plan=%@ / account/read finished without email reason=%@ /
//            account/read response has no account / persistent account/read failed reason=%@ /
//            profile metadata available name=%@ image=%@
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 账号档案字段（对齐原包 CAAccountProfile ivar 名）：
/// email / displayName / imageURL / planType / accountType / userId / authenticated / readSucceeded
@interface CAAccountInfoBridge : NSObject

+ (instancetype)sharedBridge;

#pragma mark 读取

- (void)readOfficialAccountWithCompletion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;
- (void)readOfficialAccountOnMainQueueWithCompletion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;
- (void)fetchAccountProfileWithBin:(nullable NSString *)bin
                              home:(NSString *)home
                        completion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;
- (nullable NSDictionary *)profileMetadataAtHome:(NSString *)home;

#pragma mark 缓存

- (nullable NSDictionary *)cachedProfileForHome:(NSString *)home;
- (void)saveProfile:(NSDictionary *)profile home:(NSString *)home;
- (void)invalidateProfileCacheForHome:(NSString *)home;

#pragma mark 原包同名类方法（实例方法内部转发到这些）

+ (NSString *)cacheKeyForHome:(NSString *)home;
+ (nullable NSDictionary *)cachedProfileForHome:(NSString *)home;
+ (void)saveProfile:(NSDictionary *)profile home:(NSString *)home;
+ (void)invalidateProfileCacheForHome:(NSString *)home;
+ (void)fetchAccountProfileWithBin:(nullable NSString *)bin
                              home:(NSString *)home
                        completion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;
+ (void)augmentProfile:(NSDictionary *_Nullable)profile
        fromCodexHome:(NSString *)home
           completion:(void (^)(NSDictionary *profile))completion;
+ (void)readAccountEmailWithBin:(nullable NSString *)bin
                           home:(NSString *)home
                     completion:(void (^)(NSString *_Nullable email, NSError *_Nullable error))completion;
+ (void)readAccountProfileWithBin:(nullable NSString *)bin
                             home:(NSString *)home
                       completion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
