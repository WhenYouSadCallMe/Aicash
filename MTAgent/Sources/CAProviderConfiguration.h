//
//  CAProviderConfiguration.h — 第三方 provider 配置（密钥文件 + Keychain 迁移）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const CAProviderLegacyKeychainService;   // "CodexApp.CustomProvider"
extern NSString *const CAProviderLegacyKeychainAccount;   // "APIKey"
extern NSString *const CAProviderKeychainServiceV2;       // "CodexApp/Provider"
extern NSString *const CAProviderKeychainAccountV2;       // "api-key"

@interface CAProviderConfiguration : NSObject

@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *keyPath;

+ (instancetype)sharedConfiguration;
- (instancetype)initWithDirectory:(NSString *)directory;

+ (NSString *)normalizedBaseURL:(NSString *)baseURL;
+ (NSString *)modelsURLForBaseURL:(NSString *)baseURL;   // → <base>/models 或 <base>/v1/models

- (nullable NSString *)readAPIKeyWithError:(NSError **)error;
- (BOOL)saveAPIKey:(NSString *)apiKey error:(NSError **)error;

+ (BOOL)removeLegacyKeychainCredential;                   // 删除 Keychain 旧条目
+ (nullable NSString *)migrateLegacyKeychainCredentialWithError:(NSError **)error; // SecItemCopyMatching 读旧值

@end

NS_ASSUME_NONNULL_END
