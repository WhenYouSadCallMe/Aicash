//
//  CACodexMetadataReader.h — 只读解析 Codex home 的账号 / 会话元数据
//
//  原包符号对齐（SPEC/assets/objc_api_map.json → "CACodexMetadataReader"）：
//    +profileMetadataAtHome: / +readKind:home:thread:completion: / +readProfileAtHome:completion: /
//    +readUsageForThread:home:completion: / +usageMetadataForThread:home:
//  账号读取入口（原包由 CAAccountInfoBridge 转发）：
//    +readAccountEmailWithBin:home:completion: / +readAccountProfileWithBin:home:completion:
//
//  只读数据源（strings_full.txt 0x58d9a2…0x58da99 段）：
//    auth.json → tokens → id_token（JWT payload：sub / preferred_username / given_name / email / picture）、
//    image_url / avatar_url / profile_image_url / avatarUrl、plan_type
//    sessions / archived_sessions → *.jsonl → payload → event_msg → total_token_usage
//
//  说明：本类只读本地文件，不做任何网络请求或上传。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const CACodexMetadataErrorDomain;

@interface CACodexMetadataReader : NSObject

/// auth.json → tokens.id_token 的 JWT payload（原包 profileMetadataAtHome:）
+ (NSDictionary<NSString *, NSString *> *)profileMetadataAtHome:(NSString *)home;

/// kind = profile / usage（原包 readKind:home:thread:completion:）
+ (void)readKind:(NSString *)kind
            home:(NSString *)home
          thread:(nullable NSString *)threadId
      completion:(void (^)(NSDictionary *_Nullable metadata, NSError *_Nullable error))completion;

+ (void)readProfileAtHome:(NSString *)home
               completion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;

+ (void)readUsageForThread:(NSString *)threadId
                      home:(NSString *)home
                completion:(void (^)(NSDictionary *_Nullable usage, NSError *_Nullable error))completion;

+ (nullable NSDictionary *)usageMetadataForThread:(NSString *)threadId home:(NSString *)home;

#pragma mark 账号（本地只读；bin 仅用于判定 codex 可执行是否存在）

+ (void)readAccountEmailWithBin:(nullable NSString *)bin
                           home:(NSString *)home
                     completion:(void (^)(NSString *_Nullable email, NSError *_Nullable error))completion;

+ (void)readAccountProfileWithBin:(nullable NSString *)bin
                             home:(NSString *)home
                       completion:(void (^)(NSDictionary *_Nullable profile, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
