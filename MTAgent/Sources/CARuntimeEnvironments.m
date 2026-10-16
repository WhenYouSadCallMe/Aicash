//
//  CARuntimeEnvironments.m
//  对齐原包：
//    - 四个环境类共用清单条目（CARuntimeCatalogEntry）：archive_url / archive_sha256 / revision
//    - 下载走 CAUpdateManager（直连 + 代理前缀），校验 SHA256 后才解包签名
//    - Python：PYTHONHOME/PYTHONPATH；Theos：THEOS/SDK 路径与 CA_THEOS_* 变量；逆向工具：R2_PREFIX / CA_REVERSE_TOOLS_STAGING
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CARuntimeEnvironments.h"
#import "CAUpdateManager.h"
#import "CAArchiveExtractor.h"
#import "CAStorageManager.h"
#import "CALogger.h"

@implementation CARuntimeEnvironmentBase

+ (instancetype)sharedEnvironment
{
    static NSMutableDictionary<NSString *, CARuntimeEnvironmentBase *> *instances;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instances = [NSMutableDictionary dictionary]; });
    NSString *key = [self runtimeIdentifier];
    @synchronized (instances) {
        CARuntimeEnvironmentBase *env = instances[key];
        if (!env) { env = [self new]; instances[key] = env; }
        return env;
    }
}

+ (NSString *)runtimeIdentifier { return @"runtime"; }

- (instancetype)init
{
    if ((self = [super init])) {
        _runtimeID = [[self.class runtimeIdentifier] copy];
        _downloadProxyPrefixes = CADownloadProxyPrefixes();
        _runtimeRoot = [[CARuntimePaths runtimeRootForID:_runtimeID] copy];
        _downloadProgress = 0.0;
    }
    return self;
}

#pragma mark - 路径

- (NSString *)installedManifestPath { return [CARuntimePaths installedManifestPathForRuntimeID:self.runtimeID]; }
- (NSString *)cacheDirectoryForEntry:(CARuntimeCatalogEntry *)entry
{
    NSString *dir = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:entry.runtimeID ?: self.runtimeID];
    [CARuntimePaths ensureDirectory:dir mode:0700 error:NULL];
    return dir;
}
- (NSArray<NSString *> *)localStateDirectory:(NSString *)directory
{
    NSString *path = [CARuntimePaths.supportDirectory stringByAppendingPathComponent:directory ?: @"RuntimeState"];
    [CARuntimePaths ensureDirectory:path mode:0700 error:NULL];
    return @[ path ];
}

#pragma mark - 状态

- (BOOL)hasInstalledRuntime { return [NSFileManager.defaultManager fileExistsAtPath:self.installedManifestPath]; }
- (BOOL)hasCachedArchiveForRemoteEntry
{
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:CARuntimePaths.runtimeDownloadsDirectory error:NULL]) {
        if ([name hasSuffix:@".tar.gz"] && [name containsString:self.runtimeID]) return YES;
    }
    return NO;
}
- (NSString *)revisionPathForID:(NSString *)revisionID
{
    return [[CARuntimePaths runtimeRootForID:self.runtimeID] stringByAppendingPathComponent:revisionID ?: @"installed"];
}
- (NSString *)installedRevisionForEntry:(CARuntimeCatalogEntry *)entry
{
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:self.installedManifestPath] options:0 error:NULL];
    NSString *revision = manifest[@"revision"] ?: manifest[@"installed_revision"];
    if (revision && entry.revision && revision.integerValue == entry.revision) return revision;
    return revision;
}
- (unsigned long long)installedSizeForEntry:(CARuntimeCatalogEntry *)entry
{
    return [[CAStorageManager sharedManager] directorySizeAtPath:[CARuntimePaths runtimeRootForID:entry.runtimeID ?: self.runtimeID]];
}
- (BOOL)updateAvailable
{
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:self.runtimeID];
    NSString *installed = [self installedRevisionForEntry:entry];
    if (!entry) return NO;
    if (!installed.length) return YES;
    return installed.integerValue != entry.revision;
}
- (void)setStates:(NSDictionary *)states { self.installedManifest = states; }
- (NSDictionary *)states { return self.installedManifest ?: @{}; }
- (void)setSlug:(NSString *)slug { _runtimeID = [slug copy]; }

#pragma mark - 下载

- (NSArray<NSString *> *)downloadCandidates:(NSString *)urlString
{
    return [[CAUpdateManager sharedManager] downloadCandidatesForURL:urlString];
}

- (void)publishDownload:(NSString *)stage progress:(double)progress
{
    self.downloadStage = stage;
    self.downloadProgress = progress;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CARuntimeDownloadDidChange" object:self
                                                      userInfo:@{ @"runtime": self.runtimeID, @"stage": stage ?: @"", @"progress": @(progress) }];
}

- (BOOL)download:(NSString *)urlString to:(NSString *)destination error:(NSError **)error
{
    return [[CAUpdateManager sharedManager] downloadAssetURL:urlString destinationPath:destination
                                                   progress:^(double f, NSString *stage) { [self publishDownload:stage progress:f]; }
                                                      error:error];
}

- (BOOL)downloadURLString:(NSString *)urlString toPath:(NSString *)path progress:(CARuntimeProgressHandler)progress error:(NSError **)error
{
    return [[CAUpdateManager sharedManager] downloadAssetURL:urlString destinationPath:path
                                                   progress:^(double f, NSString *stage) {
        if (progress) progress(f, stage);
        [self publishDownload:stage progress:f];
    } error:error];
}

- (BOOL)isValidHTTPSURL:(NSURL *)url { return [url.scheme.lowercaseString isEqualToString:@"https"]; }

#pragma mark - 探测 / 安装 / 卸载

- (void)probeEntry:(CARuntimeCatalogEntry *)entry completion:(void (^)(BOOL, NSString *))completion
{
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSString *codexPath = [[CARuntimePaths runtimeRootForID:entry.runtimeID ?: self.runtimeID] stringByAppendingPathComponent:@"bin/codex"];
    if ([self isKindOfClass:CAManagedRuntimeEnvironment.class] && ![NSFileManager.defaultManager isExecutableFileAtPath:codexPath]) {
        [missing addObject:@"bin/codex"];
    }
    NSString *detail = missing.count ? [NSString stringWithFormat:@"missing:%@", [missing componentsJoinedByString:@","]] : @"ok";
    if (completion) completion(missing.count == 0, detail);
}

- (void)removeRuntimeID:(NSString *)runtimeID error:(NSError **)error
{
    NSString *root = [CARuntimePaths runtimeRootForID:runtimeID ?: self.runtimeID];
    [[NSFileManager defaultManager] removeItemAtPath:root error:error];
}

- (BOOL)removeInstalledRuntime:(NSError **)error
{
    [self removeRuntimeID:self.runtimeID error:error];
    self.installedManifest = nil;
    self.installedRevision = nil;
    return YES;
}

- (NSArray<NSString *> *)installedPathDirectories
{
    return @[ [CARuntimePaths runtimeRootForID:self.runtimeID] ];
}

- (NSDictionary<NSString *, NSString *> *)installedEnvironmentValues
{
    return @{ @"CA_THEOS_RUNTIME": [CARuntimePaths runtimeRootForID:self.runtimeID] };
}

- (void)downloadAndInstallEntry:(CARuntimeCatalogEntry *)entry completion:(void (^)(BOOL, NSError *))completion
{
    if (!entry.archiveURL.length) {
        if (completion) completion(NO, [NSError errorWithDomain:@"CodexApp.Runtime" code:400 userInfo:@{ NSLocalizedDescriptionKey: @"manifest entry has no archive_url" }]);
        return;
    }
    NSURL *url = [NSURL URLWithString:entry.archiveURL];
    if (![self isValidHTTPSURL:url]) {
        if (completion) completion(NO, [NSError errorWithDomain:@"CodexApp.Runtime" code:400 userInfo:@{ NSLocalizedDescriptionKey: @"archive url rejected" }]);
        return;
    }
    self.isDownloading = YES;
    self.remoteDownloadSizeBytes = entry.downloadSize;
    self.remoteRevision = [NSString stringWithFormat:@"%ld", (long)entry.revision];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self publishDownload:@"download" progress:0.0];
        NSString *packagePath = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%ld.tar.gz", entry.runtimeID, (long)entry.revision]];
        NSError *error = nil;
        BOOL ok = [self downloadURLString:entry.archiveURL toPath:packagePath progress:nil error:&error];
        if (ok && entry.archiveSHA256.length) {
            [self publishDownload:@"verify" progress:0.5];
            ok = [[CAUpdateManager sharedManager] cachedPackageAtPath:packagePath matchesSHA256:entry.archiveSHA256];
            if (!ok) error = [NSError errorWithDomain:@"CodexApp.Runtime" code:422 userInfo:@{ NSLocalizedDescriptionKey: @"sha256 mismatch" }];
            CALog(ok ? CALogLevelInfo : CALogLevelError, @"RUNTIME", @"%@ archive sha256 check %@", entry.runtimeID, ok ? @"passed" : @"failed");
        }
        if (ok) {
            [self publishDownload:@"install" progress:0.7];
            NSString *entitlements = [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ResignEntitlements/runtime.entitlements.plist"] copy];
            ok = [[CAUpdateManager sharedManager] installPackageAtPath:packagePath runtimeID:entry.runtimeID entitlements:entitlements
                                                              progress:^(double f, NSString *stage) { [self publishDownload:stage progress:0.7 + f * 0.25]; }
                                                                 error:&error];
        }
        if (ok) {
            NSDictionary *manifest = @{ @"runtime_id": entry.runtimeID, @"revision": @(entry.revision),
                                        @"version": entry.version ?: @"", @"installed_at": @([[NSDate date] timeIntervalSince1970]) };
            NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:NULL];
            [CARuntimePaths writeFileAtomically:self.installedManifestPath contents:data mode:0644 error:NULL];
            self.installedManifest = manifest;
            self.installedRevision = manifest[@"revision"];
            [self publishDownload:@"complete" progress:1.0];
        }
        self.isDownloading = NO;
        CALog(ok ? CALogLevelInfo : CALogLevelError, @"RUNTIME", @"%@ install %@ %@", entry.runtimeID, ok ? @"completed" : @"failed", error.localizedDescription ?: @"");
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, error); });
    });
}

- (void)downloadAndInstallLatestRuntimeWithCompletion:(void (^)(BOOL, NSError *))completion
{
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:self.runtimeID];
    if (!entry) {
        if (completion) completion(NO, [NSError errorWithDomain:@"CodexApp.Runtime" code:404 userInfo:@{ NSLocalizedDescriptionKey: @"runtime not present in manifest" }]);
        return;
    }
    [self downloadAndInstallEntry:entry completion:completion];
}

- (void)setIsRecoveringRuntime:(BOOL)recovering { CALog(CALogLevelInfo, @"RUNTIME", @"recovering runtime=%@ state=%d", self.runtimeID, recovering); }

@end

@implementation CAManagedRuntimeEnvironment
+ (NSString *)runtimeIdentifier { return @"codex"; }
@end

@implementation CAPythonEnvironment
+ (NSString *)runtimeIdentifier { return @"python"; }
- (NSString *)pythonHome
{
    return [[CARuntimePaths runtimeRootForID:self.runtimeID] stringByAppendingPathComponent:@"lib/python3.13"];
}
- (NSString *)pythonExecutablePath
{
    return [[CARuntimePaths runtimeRootForID:self.runtimeID] stringByAppendingPathComponent:@"bin/python3"];
}
- (NSDictionary<NSString *, NSString *> *)installedEnvironmentValues
{
    NSString *home = [self pythonHome];
    return @{ @"PYTHONHOME": home, @"PYTHONPATH": [home stringByAppendingPathComponent:@"site-packages"], @"CA_THEOS_RUNTIME": [CARuntimePaths runtimeRootForID:self.runtimeID] };
}
@end

@implementation CATheosEnvironment
+ (NSString *)runtimeIdentifier { return @"theos"; }
- (NSString *)theosRoot { return [CARuntimePaths runtimeRootForID:self.runtimeID]; }
- (NSString *)theosMakePath { return [[self theosRoot] stringByAppendingPathComponent:@"usr/bin/make"]; }
- (NSString *)theosSDKPath { return [[self theosRoot] stringByAppendingPathComponent:@"sdks/iPhoneOS16.5.sdk"]; }
- (NSString *)downloadedArchivePath { return [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"TheosRuntime.tar.gz"]; }
- (NSString *)downloadedMetadataPath { return [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"TheosRuntime.bundle.json"]; }
- (NSString *)bundledArchivePath { return [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Helpers/theos-runtime.tar.gz"] copy]; }
- (BOOL)hasDownloadedPackage { return [NSFileManager.defaultManager fileExistsAtPath:self.downloadedArchivePath]; }
- (BOOL)downloadedPackageMatchesRemoteManifest
{
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:self.runtimeID];
    if (!entry.archiveSHA256.length) return NO;
    return [[CAUpdateManager sharedManager] cachedPackageAtPath:self.downloadedArchivePath matchesSHA256:entry.archiveSHA256];
}
- (NSArray<NSString *> *)installedExecutableMachOPathsAtRoot:(NSString *)root
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *relative in [NSFileManager.defaultManager enumeratorAtPath:root]) {
        NSString *full = [root stringByAppendingPathComponent:relative];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:full]) [paths addObject:full];
    }
    return paths;
}
- (NSDictionary<NSString *, NSString *> *)installedEnvironmentValues
{
    NSString *root = [self theosRoot];
    return @{
        CAEnvTheosRuntime: root,
        CAEnvTheosSDKRoot: [self theosSDKPath],
        CAEnvTheosMake: [self theosMakePath],
        CAEnvTheosEmbedded: @"1",
        CAEnvTheosPackageMode: @"native",
        CAEnvTheosSequenceDir: [root stringByAppendingPathComponent:@"sequence"],
    };
}
@end

@implementation CAReverseToolsEnvironment
+ (NSString *)runtimeIdentifier { return @"reverse-tools"; }
- (NSString *)radare2Prefix { return [[CARuntimePaths runtimeRootForID:self.runtimeID] stringByAppendingPathComponent:@"r2"]; }
- (NSString *)stagingPath
{
    NSString *path = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"ReverseTools"];
    [CARuntimePaths ensureDirectory:path mode:0700 error:NULL];
    return path;
}
- (void)migrateLegacyCacheIfNeeded
{
    NSString *legacy = [CARuntimePaths.cachesDirectory stringByAppendingPathComponent:@"ReverseTools"];
    if (![NSFileManager.defaultManager fileExistsAtPath:legacy]) return;
    NSError *error = nil;
    [[NSFileManager defaultManager] moveItemAtPath:legacy toPath:[CARuntimePaths.reverseToolsDirectory] error:&error];
    if (!error) CALog(CALogLevelInfo, @"RUNTIME", @"migrated ReverseTools cache to Application Support");
    else CALog(CALogLevelDebug, @"RUNTIME", @"ReverseTools cache migration skipped: %@", error);
}
- (NSDictionary<NSString *, NSString *> *)installedEnvironmentValues
{
    return @{ @"R2_PREFIX": [self radare2Prefix], CAEnvReverseToolsStaging: [self stagingPath] };
}
@end
