//
//  CAProviderConfiguration.m
//
//  对齐原包行为：
//    - 密钥存在「文件」而不是 Keychain（原二进制只导入 SecItemCopyMatching / SecItemDelete，没有 SecItemAdd/Update）
//    - 读取：fileExistsAtPath:keyPath → stringWithContentsOfFile:encoding:error: → 去首尾空白
//    - 保存：createDirectoryAtPath:attributes:{NSFilePosixPermissions:0700} → 原子写文件（0600）
//    - 迁移：SecItemCopyMatching（kSecClass=kSecClassGenericPassword、kSecReturnData）读旧 Keychain 值后用 SecItemDelete 清掉
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAProviderConfiguration.h"
#import <Security/Security.h>

NSString *const CAProviderLegacyKeychainService = @"CodexApp.CustomProvider";
NSString *const CAProviderLegacyKeychainAccount = @"APIKey";
NSString *const CAProviderKeychainServiceV2     = @"CodexApp/Provider";
NSString *const CAProviderKeychainAccountV2     = @"api-key";

static NSString * const kKeyFileName = @"api-key";
static NSString * const kKeyTempPrefix = @".api-key-";

@implementation CAProviderConfiguration

+ (instancetype)sharedConfiguration
{
    static CAProviderConfiguration *config; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = [CARuntimePaths.supportDirectory stringByAppendingPathComponent:@"CodexApp/Provider"];
        config = [[CAProviderConfiguration alloc] initWithDirectory:dir];
    });
    return config;
}

- (instancetype)initWithDirectory:(NSString *)directory
{
    if ((self = [super init])) {
        _directory = [directory copy];
        _keyPath = [[directory stringByAppendingPathComponent:kKeyFileName] copy];
    }
    return self;
}

#pragma mark - URL 归一化（原包：/models 与 /v1/models 两种候选）

+ (NSString *)normalizedBaseURL:(NSString *)baseURL
{
    NSString *url = [baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    return url;
}

+ (NSString *)modelsURLForBaseURL:(NSString *)baseURL
{
    NSString *base = [self normalizedBaseURL:baseURL];
    if (!base.length) return nil;
    if ([base hasSuffix:@"/v1"] || [base hasSuffix:@"/v1/models"]) return [base stringByAppendingPathComponent:@"models"];
    if ([base hasSuffix:@"models"]) return base;
    return [base stringByAppendingPathComponent:@"models"];
}

#pragma mark - 读（文件）

- (NSString *)readAPIKeyWithError:(NSError **)error
{
    @synchronized (self) {
        if (![NSFileManager.defaultManager fileExistsAtPath:self.keyPath]) {
            if (error) *error = [NSError errorWithDomain:@"CodexApp.Provider" code:404
                                                userInfo:@{ NSLocalizedDescriptionKey: @"provider credential read failed code=404" }];
            return nil;
        }
        NSString *value = [NSString stringWithContentsOfFile:self.keyPath encoding:NSUTF8StringEncoding error:error];
        if (!value) {
            CALog(CALogLevelError, @"GENERAL", @"provider credential read failed code=%ld", (long)(error ? (*error).code : -1));
            return nil;
        }
        return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
}

#pragma mark - 写（文件，0700 目录 / 0600 文件）

- (BOOL)saveAPIKey:(NSString *)apiKey error:(NSError **)error
{
    @synchronized (self) {
        NSError *dirError = nil;
        NSDictionary *attrs = @{ NSFilePosixPermissions: @(0700) };
        if (![NSFileManager.defaultManager createDirectoryAtPath:self.directory
                                     withIntermediateDirectories:YES
                                                      attributes:attrs
                                                           error:&dirError]) {
            CALog(CALogLevelError, @"GENERAL", @"provider credential save failed code=%ld", (long)dirError.code);
            if (error) *error = dirError;
            return NO;
        }
        NSData *data = [(apiKey ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
        NSString *tmp = [self.directory stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@%@", kKeyTempPrefix, NSUUID.UUID.UUIDString]];
        if (![data writeToFile:tmp options:NSDataWritingAtomic error:error]) {
            CALog(CALogLevelError, @"GENERAL", @"provider credential save failed code=%ld", (long)(error ? (*error).code : -1));
            return NO;
        }
        chmod(tmp.fileSystemRepresentation, 0600);
        if (![NSFileManager.defaultManager replaceItemAtURL:[NSURL fileURLWithPath:self.keyPath]
                                              withItemAtURL:[NSURL fileURLWithPath:tmp]
                                             backupItemName:nil
                                                    options:0
                                           resultingItemURL:NULL
                                                      error:error]) {
            [NSFileManager.defaultManager removeItemAtPath:tmp error:NULL];
            CALog(CALogLevelError, @"GENERAL", @"provider credential save failed code=%ld", (long)(error ? (*error).code : -1));
            return NO;
        }
        chmod(self.keyPath.fileSystemRepresentation, 0600);
        return YES;
    }
}

#pragma mark - Keychain 旧条目（只读 + 只删，与原包一致）

+ (BOOL)removeLegacyKeychainCredential
{
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: CAProviderLegacyKeychainService,
        (__bridge id)kSecAttrAccount: CAProviderLegacyKeychainAccount,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    BOOL ok = (status == errSecSuccess || status == errSecItemNotFound);
    if (!ok) CALog(CALogLevelWarn, @"GENERAL", @"legacy provider credential cleanup failed status=%d", (int)status);
    // 第二组旧命名（原包字面量 CodexApp/Provider + api-key）
    NSDictionary *queryV2 = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: CAProviderKeychainServiceV2,
        (__bridge id)kSecAttrAccount: CAProviderKeychainAccountV2,
    };
    SecItemDelete((__bridge CFDictionaryRef)queryV2);
    return ok;
}

+ (NSString *)migrateLegacyKeychainCredentialWithError:(NSError **)error
{
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: CAProviderKeychainServiceV2,
        (__bridge id)kSecAttrAccount: CAProviderKeychainAccountV2,
        (__bridge id)kSecReturnData:  @YES,
        (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) {
        if (status != errSecItemNotFound && error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                                     userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"provider credential migration failed code=%d", (int)status] }];
        }
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@end
