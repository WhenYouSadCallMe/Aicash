//
//  CARuntimeEnvironments.h — 运行时环境（Codex / Python / Theos / 逆向工具）安装与探测
//  对齐原包类：CAManagedRuntimeEnvironment、CAPythonEnvironment、CATheosEnvironment、CAReverseToolsEnvironment
//

#import <Foundation/Foundation.h>
#import "CARuntimeCatalog.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^CARuntimeProgressHandler)(double fraction, NSString *stage);

@interface CARuntimeEnvironmentBase : NSObject

@property (nonatomic, copy, readonly) NSString *runtimeID;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) double downloadProgress;
@property (nonatomic, copy, nullable) NSString *downloadStage;
@property (nonatomic, assign) unsigned long long remoteDownloadSizeBytes;
@property (nonatomic, copy, nullable) NSArray<NSString *> *downloadProxyPrefixes;
@property (nonatomic, copy, nullable) NSString *remoteRevision;
@property (nonatomic, copy, nullable) NSString *installedRevision;
@property (nonatomic, copy, nullable) NSString *runtimeRoot;
@property (nonatomic, copy, nullable) NSString *pythonHome;
@property (nonatomic, copy, nullable) NSDictionary *installedManifest;

+ (instancetype)sharedEnvironment;
+ (NSString *)runtimeIdentifier;

- (NSString *)installedManifestPath;
- (NSString *)cacheDirectoryForEntry:(CARuntimeCatalogEntry *)entry;
- (NSArray<NSString *> *)localStateDirectory:(NSString *)directory;

- (BOOL)hasCachedArchiveForRemoteEntry;
- (BOOL)hasInstalledRuntime;
- (NSString *)revisionPathForID:(NSString *)revisionID;
- (NSString *)installedRevisionForEntry:(CARuntimeCatalogEntry *)entry;
- (unsigned long long)installedSizeForEntry:(CARuntimeCatalogEntry *)entry;
- (BOOL)updateAvailable;
- (void)setStates:(NSDictionary *)states;
- (NSDictionary *)states;
- (void)setSlug:(NSString *)slug;

- (NSArray<NSString *> *)downloadCandidates:(NSString *)urlString;
- (void)publishDownload:(NSString *)stage progress:(double)progress;
- (BOOL)download:(NSString *)urlString to:(NSString *)destination error:(NSError **)error;
- (BOOL)downloadURLString:(NSString *)urlString toPath:(NSString *)path progress:(nullable CARuntimeProgressHandler)progress error:(NSError **)error;

- (void)probeEntry:(CARuntimeCatalogEntry *)entry completion:(void (^)(BOOL ok, NSString *_Nullable detail))completion;
- (void)removeRuntimeID:(NSString *)runtimeID error:(NSError **)error;
- (NSArray<NSString *> *)installedPathDirectories;
- (NSDictionary<NSString *, NSString *> *)installedEnvironmentValues;
- (BOOL)removeInstalledRuntime:(NSError **)error;

- (void)downloadAndInstallEntry:(CARuntimeCatalogEntry *)entry completion:(void (^)(BOOL ok, NSError *_Nullable error))completion;
- (void)downloadAndInstallLatestRuntimeWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion;
- (void)setIsRecoveringRuntime:(BOOL)recovering;
- (BOOL)isValidHTTPSURL:(NSURL *)url;

@end

@interface CAManagedRuntimeEnvironment : CARuntimeEnvironmentBase
@property (nonatomic, copy, nullable) NSString *desiredRuntime;

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)executionEnvironment;
    - (id)isAllowedPortableEnvironmentKey:(id)arg1;
    - (id)isRecoveryExpectedOrInProgressForEntry:(id)arg1;
    - (id)mutableState:(id)arg1;
    - (id)probePayloadForEntry:(id)arg1 error:(id)arg2;
    - (id)publishState:(id)arg1 busy:(id)arg2 progress:(id)arg3 stage:(id)arg4 error:(id)arg5;
    - (id)restoreCachedRuntimesIfNeeded;
    - (id)rootForID:(id)arg1;
    - (id)runRoot:(id)arg1 args:(id)arg2 cwd:(id)arg3 timeout:(id)arg4 output:(id)arg5 error:(id)arg6;
    - (id)safeID:(id)arg1;
    - (id)stateForRuntimeID:(id)arg1;
    - (id)validateEntry:(id)arg1 staging:(id)arg2 signPaths:(id)arg3 error:(id)arg4;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

@interface CAPythonEnvironment : CARuntimeEnvironmentBase
@property (nonatomic, copy, nullable) NSString *pythonVersion;
- (NSString *)pythonHome;
- (NSString *)pythonExecutablePath;

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)activateStaging:(id)arg1 revision:(id)arg2 error:(id)arg3;
    - (id)publishPreparation:(id)arg1 stage:(id)arg2 error:(id)arg3;
    - (id)refreshRemoteManifestWithCompletion:(id)arg1;
    - (id)remoteEntry;
    - (id)setRemoteEntry:(id)arg1;
    - (id)validateStaging:(id)arg1 remote:(id)arg2 signPaths:(id)arg3 error:(id)arg4;
    - (id)validatedEntryFromManifestData:(id)arg1 error:(id)arg2;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

@interface CATheosEnvironment : CARuntimeEnvironmentBase
- (NSString *)theosRoot;
- (NSString *)theosMakePath;
- (NSString *)downloadedArchivePath;
- (NSString *)downloadedMetadataPath;
- (NSString *)bundledArchivePath;
- (BOOL)hasDownloadedPackage;
- (BOOL)downloadedPackageMatchesRemoteManifest;
- (NSArray<NSString *> *)installedExecutableMachOPathsAtRoot:(NSString *)root;
- (NSString *)theosSDKPath;

// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSString * compilerPath;
    @property (nonatomic, strong, nullable) NSString * defaultSDKPath;
    @property (nonatomic, assign) BOOL desiredRemoteRuntimeAccessAllowed;
    @property (nonatomic, strong, nullable) NSString * dpkgDebPath;
    @property (nonatomic, assign) BOOL forceNextPreparation;
    @property (nonatomic, assign) unsigned long long installedSizeCache;
    @property (nonatomic, assign) BOOL installedSizeCacheValid;
    @property (nonatomic, assign) BOOL isPreparing;
    @property (nonatomic, assign) BOOL isRepairingEmbeddedAdapter;
    @property (nonatomic, strong, nullable) NSString * lastQueuedPreparationStage;
    @property (nonatomic, assign) int lastQueuedPreparationTime;
    @property (nonatomic, strong, nullable) NSString * linkerPath;
    @property (nonatomic, strong, nullable) NSString * makePath;
    @property (nonatomic, strong, nullable) NSString * moduleCachePath;
    @property (nonatomic, strong, nullable) NSString * packageBuilderPath;
    @property (nonatomic, strong, nullable) NSArray * pathDirectories;
    @property (nonatomic, strong, nullable) NSMutableArray * pendingCompletions;
    @property (nonatomic, strong, nullable) NSString * perlPath;
    @property (nonatomic, strong, nullable) NSString * preparationError;
    @property (nonatomic, assign) double preparationProgress;
    @property (nonatomic, strong, nullable) NSObject<OS_dispatch_queue> * preparationQueue;
    @property (nonatomic, strong, nullable) NSString * preparationStage;
    @property (nonatomic, assign) unsigned long long remoteExpandedSizeBytes;
    @property (nonatomic, strong, nullable) NSDictionary * remoteManifest;
    @property (nonatomic, strong, nullable) NSString * remoteManifestError;
    @property (nonatomic, assign) BOOL remoteRuntimeAccessAllowed;
    @property (nonatomic, strong, nullable) NSString * remoteVersion;
    @property (nonatomic, strong, nullable) NSString * sdkRoot;
    @property (nonatomic, strong, nullable) NSString * signerPath;
    @property (nonatomic, strong, nullable) NSString * usrPath;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)absolutePathsForRelativePaths:(id)arg1 root:(id)arg2 error:(id)arg3;
    - (id)appendEmbeddedRuntimeBlock:(id)arg1 marker:(id)arg2 toPath:(id)arg3 error:(id)arg4;
    - (id)applyEmbeddedMakefileCompatibilityAtRoot:(id)arg1 error:(id)arg2;
    - (id)bundleMetadata;
    - (id)bundleMetadataPath;
    - (id)bundleRevision;
    - (id)bundledMetadataPath;
    - (id)cachePreparedRuntimeFromRoot:(id)arg1 revision:(id)arg2 error:(id)arg3;
    - (id)clonePathAsRoot:(id)arg1 toPath:(id)arg2 error:(id)arg3;
    - (id)compareSDKName:(id)arg1 to:(id)arg2;
    - (id)downloadURL:(id)arg1 toPath:(id)arg2 progress:(id)arg3 error:(id)arg4;
    - (id)embeddedAdapterCurrentAtRoot:(id)arg1;
    - (id)embeddedAdapterMarkerAtRoot:(id)arg1;
    - (id)embeddedAdapterRevisionAtRoot:(id)arg1;
    - (id)entitlementUpgradeExecutablePathsAtRoot:(id)arg1 relativeExecutables:(id)arg2;
    - (id)environmentByAugmentingEnvironment:(id)arg1;
    - (id)finishPreparation:(id)arg1 error:(id)arg2;
    - (id)firstExecutable:(id)arg1;
    - (id)hasAvailablePackage;
    - (id)hasCompiler;
    - (id)hasLinker;
    - (id)hasMake;
    - (id)hasPackageTools;
    - (id)hasPerl;
    - (id)hasPreparedRuntime;
    - (id)hasSDK;
    - (id)hasSigner;
    - (id)installationEnvironmentForRoot:(id)arg1;
    - (id)isInstalledRevisionCurrent;
    - (id)isValidHTTPSURLString:(id)arg1;
    - (id)moduleInputFingerprint;
    - (id)movePathAsRoot:(id)arg1 toPath:(id)arg2 error:(id)arg3;
    - (id)numericVersionForSDKName:(id)arg1;
    - (id)patchEmbeddedRuntimeFile:(id)arg1 replacements:(id)arg2 error:(id)arg3;
    - (id)preparationWorkspaceRoot;
    - (id)prepareBundledRuntimeIfNeededWithCompletion:(id)arg1;
    - (id)preparedRuntimeMatchesRevision:(id)arg1;
    - (id)preparedRuntimeRevision;
    - (id)preparedRuntimeRoot;
    - (id)privateRuntimeRoot;
    - (id)publishDownloadProgress:(id)arg1 stage:(id)arg2;
    - (id)publishPreparationProgress:(id)arg1 error:(id)arg2;
    - (id)publishPreparationProgress:(id)arg1 stage:(id)arg2 error:(id)arg3;
    - (id)refreshRuntimeIdentityIfNeeded;
    - (id)reinstallAvailableRuntimeWithCompletion:(id)arg1;
    - (id)remoteManifestURL;
    - (id)removeInstalledRuntimeWithCompletion:(id)arg1;
    - (id)resignInstalledRuntimeExecutablesAtRoot:(id)arg1 error:(id)arg2;
    - (id)rollbackRuntimeRoot:(id)arg1 backup:(id)arg2 failed:(id)arg3 hadOld:(id)arg4;
    - (id)runtimeCacheRoot;
    - (id)setTheosPath:(id)arg1;
    - (id)sha256ForString:(id)arg1;
    - (id)theosPath;
    - (id)validateRuntimeAtRoot:(id)arg1 error:(id)arg2;
    - (id)validatedTheosEntryFromManifestData:(id)arg1 error:(id)arg2;
    - (id)writeTextAsRoot:(id)arg1 toPath:(id)arg2 error:(id)arg3;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

@interface CAReverseToolsEnvironment : CARuntimeEnvironmentBase
- (NSString *)radare2Prefix;
- (NSString *)stagingPath;
- (void)migrateLegacyCacheIfNeeded;

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)binPath;
    - (id)downloadArchiveForEntry:(id)arg1 toPath:(id)arg2 error:(id)arg3;
    - (id)executionEnvironmentWithStaging:(id)arg1;
    - (id)pathForTool:(id)arg1;
    - (id)refreshPaths;
    - (id)setBinPath:(id)arg1;
    - (id)statusSummary;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
