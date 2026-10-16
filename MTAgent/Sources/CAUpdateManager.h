//
//  CAUpdateManager.h — GitHub 发布获取 / SHA256 校验 / 解包 / 重新签名（codex-sign）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CAUpdateProgressHandler)(double fraction, NSString * _Nullable stage);

@interface CAUpdateManager : NSObject

@property (nonatomic, assign, readonly) unsigned long long latestDownloadSizeBytes;

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
    @property (nonatomic, strong, nullable) NSString * cachedInstalledVersion;
    @property (nonatomic, assign) BOOL isRecoveringRuntime;
    @property (nonatomic, strong, nullable) NSMutableArray * runtimeRecoveryWaiters;
    @property (nonatomic, assign) BOOL updateInProgress;
    @property (nonatomic, strong, nullable) NSObject<OS_dispatch_queue> * workQueue;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)activeCodeModeHostPath;
    - (id)activeExecutablePath;
    - (id)atomicSwapStagingCodex:(id)arg1 stagingHost:(id)arg2 version:(id)arg3 error:(id)arg4;
    - (id)cacheDirectoryForVersion:(id)arg1;
    - (id)cachedDebPathForVersion:(id)arg1;
    - (id)checkLatestVersion:(id)arg1;
    - (id)checkLatestVersionViaGitHubAPI:(id)arg1;
    - (id)compareVersion:(id)arg1 toVersion:(id)arg2;
    - (id)executablePathWithFallback;
    - (id)extractDebPath:(id)arg1 toDirectory:(id)arg2 progress:(id)arg3 error:(id)arg4;
    - (id)hasActiveHelper;
    - (id)helperExecutionEnvironmentWithStaging:(id)arg1;
    - (id)installSignedCodexIntoBundle:(id)arg1 host:(id)arg2 version:(id)arg3 error:(id)arg4;
    - (id)installedSizeBytes;
    - (id)installedVersion;
    - (id)isManagedRuntime;
    - (id)isManagedRuntimeVersion:(id)arg1;
    - (id)isUpdating;
    - (id)isValidVersionTag:(id)arg1;
    - (id)legacyInstalledVersionRecord;
    - (id)locateToolNamed:(id)arg1;
    - (id)logicalVersionForRuntimeReleaseTag:(id)arg1;
    - (id)numericComponentsForVersion:(id)arg1;
    - (id)prefersBundledCodexTestRuntime;
    - (id)privateHelperDirectory;
    - (id)releaseRepositoryForVersion:(id)arg1 owner:(id)arg2 repo:(id)arg3 releaseTag:(id)arg4;
    - (id)removeManagedBundleRuntime:(id)arg1;
    - (id)resolvedBundledSignerPath;
    - (id)resolvedEntitlementsPathInWorkDir:(id)arg1;
    - (id)restoreCachedRuntimeIfNeededWithCompletion:(id)arg1;
    - (id)rollbackToPreviousVersion:(id)arg1;
    - (id)runRootExecutable:(id)arg1 arguments:(id)arg2 environment:(id)arg3 timeout:(id)arg4 output:(id)arg5 error:(id)arg6;
    - (id)runtimeReleaseTagForVersion:(id)arg1;
    - (id)saveLegacyVersionRecord:(id)arg1;
    - (id)setPrivateHelperDirectory:(id)arg1;
    - (id)sha256ForFileAtPath:(id)arg1;
    - (id)signBinary:(id)arg1 withLdid:(id)arg2 entitlementsPath:(id)arg3 error:(id)arg4;
    - (id)updateToVersion:(id)arg1 progress:(id)arg2 completion:(id)arg3;
    - (id)validatedCodexEntryFromManifestData:(id)arg1 error:(id)arg2;
    - (id)verifyBinaryLaunchability:(id)arg1 expectedVersion:(id)arg2 error:(id)arg3;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
