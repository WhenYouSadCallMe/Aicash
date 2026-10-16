//
//  CAUpdateManager.h — GitHub 发布获取 / SHA256 校验 / 解包 / 重新签名（codex-sign）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CAUpdateProgressHandler)(double fraction, NSString * _Nullable stage);

@interface CAUpdateManager : NSObject

@property (nonatomic, assign, readonly) unsigned long long latestDownloadSizeBytes;
- (void)setLatestDownloadSizeBytes:(unsigned long long)value;

+ (instancetype)sharedManager;

- (NSString *)runtimeDownloadCacheRoot;
- (NSArray<NSString *> *)downloadCandidatesForGitHubURLString:(NSString *)urlString;
- (NSArray<NSString *> *)downloadCandidatesForURL:(NSString *)urlString;

- (void)fetchOfficialSHA256ForAsset:(NSString *)asset version:(NSString *)version completion:(void (^)(NSString *_Nullable sha256, NSError *_Nullable error))completion;

- (BOOL)downloadAssetURL:(NSString *)urlString
         destinationPath:(NSString *)destination
                progress:(nullable CAUpdateProgressHandler)progress
                   error:(NSError **)error;

- (BOOL)cachedPackageAtPath:(NSString *)path matchesSHA256:(NSString *)sha256;
- (void)pruneRuntimeDownloadCacheExceptVersion:(nullable NSString *)version;
- (nullable NSArray<NSString *> *)findExtractedBinariesIn:(NSString *)root codexPath:(NSString *_Nullable *_Nullable)codexPath hostPath:(NSString *_Nullable *_Nullable)hostPath;

// 解包 + 以 codex-sign 重新签名（使用包内 entitlements 模板）
- (BOOL)installPackageAtPath:(NSString *)packagePath
                 runtimeID:(NSString *)runtimeID
               entitlements:(NSString *)entitlementsPath
                  progress:(nullable CAUpdateProgressHandler)progress
                     error:(NSError **)error;

- (BOOL)signPaths:(NSArray<NSString *> *)paths staging:(nullable NSString *)staging error:(NSError **)error;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
// ==PARITY-PROPERTIES-END==

#pragma mark - P2 补齐（原包方法对齐）

// 属性补齐（原包 proplist，readwrite；latestDownloadSizeBytes 复用顶部 readonly 声明 + 手写 setter）
@property (nonatomic, copy, nullable) NSString *cachedInstalledVersion;
@property (nonatomic, assign) BOOL isRecoveringRuntime;
@property (nonatomic, strong, nullable) NSMutableArray *runtimeRecoveryWaiters;
@property (nonatomic, assign) BOOL updateInProgress;
@property (nonatomic, strong, nullable) NSObject<OS_dispatch_queue> *workQueue;
@property (nonatomic, copy, nullable) NSString *privateHelperDirectory;

// 版本语义
- (NSComparisonResult)compareVersion:(nullable NSString *)left toVersion:(nullable NSString *)right;
- (nullable NSArray<NSNumber *> *)numericComponentsForVersion:(nullable NSString *)version;
- (BOOL)isValidVersionTag:(nullable NSString *)version;
- (nullable NSString *)logicalVersionForRuntimeReleaseTag:(nullable NSString *)tag;
- (nullable NSString *)runtimeReleaseTagForVersion:(nullable NSString *)version;

// 探测 / 版本状态
- (BOOL)prefersBundledCodexTestRuntime;
- (BOOL)hasActiveHelper;
- (nullable NSDictionary *)helperExecutionEnvironmentWithStaging:(nullable NSString *)staging;
- (nullable NSString *)executablePathWithFallback;
- (nullable NSString *)activeExecutablePath;
- (nullable NSString *)installedVersion;
- (BOOL)isInstalled;
- (BOOL)isManagedRuntime;
- (BOOL)isManagedRuntimeVersion:(nullable NSString *)version;
- (unsigned long long)installedSizeBytes;
- (nullable NSString *)legacyInstalledVersionRecord;
- (void)saveLegacyVersionRecord:(nullable NSString *)version;
- (nullable NSString *)cachedDebPathForVersion:(nullable NSString *)version;
- (nullable NSString *)locateToolNamed:(nullable NSString *)name;
- (nullable NSString *)resolvedBundledSignerPath;
- (nullable NSString *)resolvedEntitlementsPathInWorkDir:(nullable NSString *)workDirectory;

// 校验 / 签名 / 执行
- (nullable NSString *)sha256ForFileAtPath:(nullable NSString *)path;
- (BOOL)signBinary:(NSString *)path withLdid:(nullable NSString *)ldidPath entitlementsPath:(nullable NSString *)entitlementsPath error:(NSError **)error;
- (BOOL)runExecutable:(NSString *)executable
            arguments:(nullable NSArray<NSString *> *)arguments
           environment:(nullable NSDictionary<NSString *, NSString *> *)environment
              timeout:(NSTimeInterval)timeout
               output:(NSString *_Nullable *_Nullable)output
                error:(NSError **)error;
- (nullable NSString *)verifyBinaryLaunchability:(NSString *)binaryPath expectedVersion:(nullable NSString *)expectedVersion error:(NSError **)error;
- (nullable NSString *)validateBinaryLaunchability:(NSString *)binaryPath expectedVersion:(nullable NSString *)expectedVersion error:(NSError **)error;
- (nullable NSString *)validatedCodexEntryFromManifestData:(NSData *)manifestData error:(NSError **)error;

// 解包 / 原子交换 / 回滚
- (BOOL)extractDebPath:(NSString *)debPath toDirectory:(NSString *)destination progress:(nullable CAUpdateProgressHandler)progress error:(NSError **)error;
- (BOOL)atomicSwapStagingCodex:(NSString *)stagingCodexPath
                   stagingHost:(nullable NSString *)stagingHostPath
                       version:(nullable NSString *)version
                         error:(NSError **)error;
- (BOOL)rollbackToPreviousVersion:(NSError *_Nullable *_Nullable)error;
- (void)restoreCachedRuntimeIfNeededWithCompletion:(nullable void (^)(BOOL restored, NSError *_Nullable error))completion;
- (BOOL)removeInstalledRuntime:(nullable NSString *)runtimeID error:(NSError **)error;
- (BOOL)removeManagedBundleRuntime:(nullable NSString *)runtimeID;

// 更新流程
- (void)checkLatestVersion:(NSString *)runtimeID completion:(void (^)(NSString *_Nullable version, NSError *_Nullable error))completion;
- (void)checkLatestVersionViaGitHubAPI:(NSString *)runtimeID completion:(void (^)(NSString *_Nullable version, NSError *_Nullable error))completion;
- (void)updateToVersion:(NSString *)version
               progress:(nullable CAUpdateProgressHandler)progress
             completion:(void (^)(BOOL ok, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
