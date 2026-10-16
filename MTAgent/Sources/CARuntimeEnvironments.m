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
#import "CARuntimeCatalog.h"
#import "CAUpdateManager.h"
#import "CAArchiveExtractor.h"
#import "CAStorageManager.h"
#import "CALogger.h"
#import "CAEmbeddedResignEntitlements.h"
#import "CAProcess.h"

#import <CommonCrypto/CommonDigest.h>

#pragma mark - Parity 共享辅助（静态 C 函数；CATheosEnvironment.m 专属辅助在彼文件内）

static NSString *CAParityTrimmed(NSString *text)
{
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *CAParityHexDigest(NSData *data)
{
    if (!data.length) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSError *CAParityRuntimeError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"CodexApp.Runtime" code:code userInfo:@{ NSLocalizedDescriptionKey: message ?: @"" }];
}

static BOOL CAParityFileReadable(NSString *path)
{
    return path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:path];
}

static NSDictionary *CAParityReadManifest(NSString *path)
{
    if (!path.length) return @{};
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @{};
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] ?: @{};
}

// 供 CATheosEnvironment.m 复用的通用辅助（非 static：跨 TU 共享）
NSString *CAParityTrimString(NSString *text) { return CAParityTrimmed(text); }
NSString *CAParityHexDigestForData(NSData *data) { return CAParityHexDigest(data); }
NSError *CAParityTheosErrorMake(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"CodexApp.Theos" code:code userInfo:@{ NSLocalizedDescriptionKey: message ?: @"" }];
}
BOOL CAParityPathReadable(NSString *path) { return CAParityFileReadable(path); }
BOOL CAParityPathIsExecutable(NSString *path)
{
    return path.length > 0 && [NSFileManager.defaultManager isExecutableFileAtPath:path];
}

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
            NSString *entitlements = CAResignEntitlementsPathForRuntime();
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

#pragma mark - Parity 方法合并（parity 任务追加；不改上面已有逻辑）

/// 便携环境键白名单（PATH / HOME / TMPDIR / 语言 / 代理）
- (BOOL)isAllowedPortableEnvironmentKey:(NSString *)key
{
    static NSArray<NSString *> *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = @[ @"PATH", @"HOME", @"TMPDIR", @"LANG", @"LC_ALL", @"http_proxy", @"https_proxy", @"HTTP_PROXY", @"HTTPS_PROXY",
                     @"CODEX_HOME", @"PYTHONHOME", @"PYTHONPATH", @"THEOS", @"CA_THEOS_RUNTIME" ];
    });
    return key.length > 0 && [allowed containsObject:key];
}

- (NSString *)safeID:(NSString *)identifier
{
    NSMutableString *safe = [(identifier ?: @"") mutableCopy];
    while (safe.length && [safe hasPrefix:@"."]) [safe deleteCharactersInRange:NSMakeRange(0, 1)];
    [safe replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@".." withString:@"_" options:0 range:NSMakeRange(0, safe.length)];
    return safe;
}

- (NSString *)safeRelativePath:(NSString *)relative
{
    return [CARuntimePaths safeRelativePath:relative ?: @"" inRoot:[CARuntimePaths runtimeRootForID:self.runtimeID] error:NULL] ?: @"";
}

- (NSString *)rootForID:(NSString *)runtimeID
{
    return [CARuntimePaths runtimeRootForID:[self safeID:runtimeID] ?: self.runtimeID];
}

- (BOOL)isInstalled:(NSString *)runtimeID
{
    return CAParityFileReadable([CARuntimePaths installedManifestPathForRuntimeID:runtimeID ?: self.runtimeID]);
}

- (BOOL)isRecoveryExpectedOrInProgressForEntry:(CARuntimeCatalogEntry *)entry
{
    return self.isDownloading || (entry != nil && self.remoteRevision.length > 0);
}

- (NSDictionary *)mutableState:(NSString *)runtimeID
{
    return [[self stateForRuntimeID:runtimeID] mutableCopy];
}

- (NSDictionary *)stateForRuntimeID:(NSString *)runtimeID
{
    NSDictionary *state = self.states[[self safeID:runtimeID] ?: self.runtimeID];
    return state ?: @{};
}

- (void)publishState:(NSString *)runtimeID busy:(BOOL)busy progress:(double)progress stage:(NSString *)stage error:(NSError *)error
{
    NSMutableDictionary *payload = [[self stateForRuntimeID:runtimeID] mutableCopy];
    payload[@"busy"] = @(busy);
    payload[@"progress"] = @(progress);
    payload[@"stage"] = stage ?: @"";
    if (error.localizedDescription.length) payload[@"error"] = error.localizedDescription;
    NSMutableDictionary *updated = [self.states mutableCopy];
    updated[[self safeID:runtimeID] ?: self.runtimeID] = payload;
    [self setStates:updated];
    [self publishDownload:stage ?: @"" progress:progress];
}

- (NSString *)sha256:(NSString *)string
{
    return CAParityHexDigest([string dataUsingEncoding:NSUTF8StringEncoding]);
}

- (BOOL)runRoot:(NSString *)executable args:(NSArray<NSString *> *)arguments cwd:(NSString *)cwd
        timeout:(NSTimeInterval)timeout output:(NSString **)output error:(NSError **)error
{
    if (!executable.length) {
        if (error) *error = CAParityRuntimeError(400, @"executable path is empty");
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments ?: @[];
    if (cwd.length) task.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    NSMutableDictionary *environment = [[self installedEnvironmentValues] ?: @{} mutableCopy];
    environment[@"PATH"] = [@[[CARuntimePaths runtimeRootForID:self.runtimeID], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    task.environment = environment;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError ?: CAParityRuntimeError(500, @"launch failed");
        return NO;
    }
    int status = [task waitUntilExitWithTimeout:timeout > 0 ? timeout : 300.0];
    NSString *text = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
    if (output) *output = text;
    if (status != 0 && error) *error = CAParityRuntimeError(status ?: 500, [NSString stringWithFormat:@"exit %d", status]);
    return status == 0;
}

- (BOOL)validateEntry:(CARuntimeCatalogEntry *)entry staging:(NSString *)staging signPaths:(NSArray<NSString *> *)signPaths error:(NSError **)error
{
    if (!entry.runtimeID.length) {
        if (error) *error = CAParityRuntimeError(400, @"entry has no runtime_id");
        return NO;
    }
    NSString *root = staging.length ? staging : [self rootForID:entry.runtimeID];
    if (![NSFileManager.defaultManager fileExistsAtPath:root]) {
        if (error) *error = CAParityRuntimeError(404, [NSString stringWithFormat:@"runtime root missing: %@", root]);
        return NO;
    }
    return YES;
}

- (BOOL)signPaths:(NSArray<NSString *> *)paths staging:(NSString *)staging error:(NSError **)error
{
    if (!paths.count) return YES;
    NSString *signer = CARuntimePaths.codexSignPath;
    if (!CAParityFileReadable(signer)) {
        if (error) *error = CAParityRuntimeError(404, @"codex-sign is not executable");
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:signer];
    task.arguments = [@[ @"--adhoc-only" ] arrayByAddingObjectsFromArray:paths];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PATH"] = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    task.environment = environment;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError ?: CAParityRuntimeError(500, @"codex-sign launch failed");
        return NO;
    }
    [task waitUntilExit];
    BOOL ok = (task.terminationStatus == 0);
    if (!ok && error) *error = CAParityRuntimeError(task.terminationStatus ?: 500, @"runtime signing failed");
    return ok;
}

- (NSDictionary *)probePayloadForEntry:(CARuntimeCatalogEntry *)entry error:(NSError **)error
{
    NSString *root = [self rootForID:entry.runtimeID ?: self.runtimeID];
    NSString *codex = [root stringByAppendingPathComponent:@"bin/codex"];
    BOOL ok = CAParityFileReadable(codex);
    if (!ok && error) *error = CAParityRuntimeError(404, @"bin/codex missing from runtime");
    return @{ @"runtime_id": entry.runtimeID ?: self.runtimeID ?: @"", @"ok": @(ok),
              @"root": root, @"codex_path": codex,
              @"revision": self.installedRevision ?: @"" };
}

- (void)restoreCachedRuntimesIfNeeded
{
    for (NSString *runtimeID in @[@"codex", @"python", @"theos", @"reverse-tools"]) {
        if ([self isInstalled:runtimeID]) continue;
        NSString *root = [CARuntimePaths runtimeRootForID:runtimeID];
        if ([NSFileManager.defaultManager fileExistsAtPath:root]) {
            CALog(CALogLevelInfo, @"RUNTIME", @"cached runtime found without manifest id=%@", runtimeID);
        }
    }
}

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

#pragma mark - Parity 方法合并（parity 任务追加；不改上面已有逻辑）

- (NSString *)executablePath { return self.pythonExecutablePath; }

- (BOOL)isInstalled
{
    return [NSFileManager.defaultManager isExecutableFileAtPath:self.pythonExecutablePath];
}

- (NSString *)installedVersion
{
    if (![self isInstalled]) return nil;
    NSDictionary *manifest = CAParityReadManifest(self.installedManifestPath);
    NSString *version = manifest[@"version"] ?: manifest[@"python_version"];
    if (version.length) return version;
    NSString *marker = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"python-version"];
    return CAParityTrimmed([NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL]) ?: nil;
}

- (unsigned long long)installedSizeBytes
{
    return [[CAStorageManager sharedManager] directorySizeAtPath:[CARuntimePaths runtimeRootForID:self.runtimeID]];
}

- (void)publishPreparation:(double)fraction stage:(NSString *)stage error:(NSError *)error
{
    [self publishDownload:stage ?: @"" progress:fraction];
    if (error.localizedDescription.length) {
        CALog(CALogLevelError, @"PYTHON", @"prepare stage=%@ error=%@", stage ?: @"", error.localizedDescription);
    }
}

- (NSString *)sha256ForFileAtPath:(NSString *)path
{
    return CAParityHexDigest([NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL]);
}

- (NSString *)cacheRoot
{
    return [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"python"];
}

- (NSDictionary<NSString *, NSString *> *)executionEnvironment
{
    return [self installedEnvironmentValues];
}

- (BOOL)runRootExecutable:(NSString *)executable arguments:(NSArray<NSString *> *)arguments cwd:(NSString *)cwd
                  timeout:(NSTimeInterval)timeout output:(NSString **)output error:(NSError **)error
{
    if (![self isInstalled]) {
        if (error) *error = CAParityRuntimeError(404, @"python runtime is not installed");
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:executable ?: self.pythonExecutablePath];
    task.arguments = arguments ?: @[];
    if (cwd.length) task.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    NSMutableDictionary *environment = [[self installedEnvironmentValues] mutableCopy];
    environment[@"PATH"] = [@[[CARuntimePaths runtimeRootForID:self.runtimeID], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    task.environment = environment;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError ?: CAParityRuntimeError(500, @"python launch failed");
        return NO;
    }
    int status = [task waitUntilExitWithTimeout:timeout > 0 ? timeout : 300.0];
    NSString *text = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
    if (output) *output = text;
    if (status != 0 && error) *error = CAParityRuntimeError(status ?: 500, [NSString stringWithFormat:@"exit %d: %@", status, text]);
    return status == 0;
}

- (BOOL)validateStaging:(NSString *)staging remote:(CARuntimeCatalogEntry *)remote signPaths:(NSArray<NSString *> *)signPaths error:(NSError **)error
{
    NSString *python = [staging stringByAppendingPathComponent:@"bin/python3"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:python]) {
        if (error) *error = CAParityRuntimeError(422, @"staging missing bin/python3");
        return NO;
    }
    return YES;
}

- (BOOL)signPaths:(NSArray<NSString *> *)paths staging:(NSString *)staging error:(NSError **)error
{
    return [[CAManagedRuntimeEnvironment sharedEnvironment] signPaths:paths staging:staging error:error];
}

- (BOOL)activateStaging:(NSString *)staging revision:(NSString *)revision error:(NSError **)error
{
    if (!CAParityFileReadable(staging)) {
        if (error) *error = CAParityRuntimeError(404, @"staging path missing");
        return NO;
    }
    NSString *root = [CARuntimePaths runtimeRootForID:self.runtimeID];
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:staging toPath:root error:error];
    if (ok && revision.length) {
        NSDictionary *manifest = @{ @"runtime_id": self.runtimeID, @"revision": revision, @"installed_at": @(NSDate.date.timeIntervalSince1970) };
        NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:NULL];
        [CARuntimePaths writeFileAtomically:self.installedManifestPath contents:data mode:0644 error:NULL];
        [[NSNotificationCenter defaultCenter] postNotificationName:CAPythonEnvironmentDidChangeNotification object:self];
    }
    return ok;
}

- (void)restoreCachedRuntimeIfNeededWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion
{
    BOOL installed = [self isInstalled];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(installed, installed ? nil : CAParityRuntimeError(404, @"python runtime not installed"));
    });
}
@end

// （CATheosEnvironment 完整实现——基础方法 + parity 方法——已迁移至 CATheosEnvironment.m）

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
    [[NSFileManager defaultManager] moveItemAtPath:legacy toPath:CARuntimePaths.reverseToolsDirectory error:&error];
    if (!error) CALog(CALogLevelInfo, @"RUNTIME", @"migrated ReverseTools cache to Application Support");
    else CALog(CALogLevelDebug, @"RUNTIME", @"ReverseTools cache migration skipped: %@", error);
}
- (NSDictionary<NSString *, NSString *> *)installedEnvironmentValues
{
    return @{ @"R2_PREFIX": [self radare2Prefix], CAEnvReverseToolsStaging: [self stagingPath] };
}

#pragma mark - Parity 方法合并（parity 任务追加；不改上面已有逻辑）

- (NSString *)binPath
{
    return [[CARuntimePaths runtimeRootForID:self.runtimeID] stringByAppendingPathComponent:@"bin"];
}

- (void)refreshPaths
{
    self.binPath = [[CARuntimePaths runtimeRootForID:self.runtimeID] stringByAppendingPathComponent:@"bin"];
    CALog(CALogLevelDebug, @"REVERSE", @"refreshed bin path %@", self.binPath);
}

- (BOOL)isInstalled
{
    return [NSFileManager.defaultManager fileExistsAtPath:self.installedManifestPath] ||
           [NSFileManager.defaultManager isExecutableFileAtPath:[[self binPath] stringByAppendingPathComponent:@"frida"]];
}

- (NSString *)installedVersion
{
    NSDictionary *manifest = CAParityReadManifest(self.installedManifestPath);
    return manifest[@"version"] ?: manifest[@"revision"] ?: nil;
}

- (unsigned long long)installedSizeBytes
{
    return [[CAStorageManager sharedManager] directorySizeAtPath:[CARuntimePaths runtimeRootForID:self.runtimeID]];
}

- (NSString *)pathForTool:(NSString *)toolName
{
    if (!toolName.length) return nil;
    for (NSString *candidate in @[ [[self binPath] stringByAppendingPathComponent:toolName],
                                   [[self radare2Prefix] stringByAppendingPathComponent:@"bin"],
                                   toolName ]) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

- (NSString *)sha256ForFileAtPath:(NSString *)path
{
    return CAParityHexDigest([NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL]);
}

- (NSString *)cacheRoot { return [CARuntimePaths.reverseToolsDirectory copy]; }

- (NSDictionary<NSString *, NSString *> *)executionEnvironmentWithStaging:(NSString *)staging
{
    NSMutableDictionary *values = [[self installedEnvironmentValues] mutableCopy];
    if (staging.length) values[CAEnvReverseToolsStaging] = staging;
    return values;
}

- (BOOL)runRootExecutable:(NSString *)executable arguments:(NSArray<NSString *> *)arguments cwd:(NSString *)cwd
                  timeout:(NSTimeInterval)timeout output:(NSString **)output error:(NSError **)error
{
    if (!executable.length) {
        if (error) *error = CAParityRuntimeError(400, @"executable path is empty");
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments ?: @[];
    if (cwd.length) task.currentDirectoryURL = [NSURL fileURLWithPath:cwd];
    NSMutableDictionary *environment = [[self installedEnvironmentValues] mutableCopy];
    environment[@"PATH"] = [@[[self binPath], [[self radare2Prefix] stringByAppendingPathComponent:@"bin"], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    task.environment = environment;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError ?: CAParityRuntimeError(500, @"launch failed");
        return NO;
    }
    int status = [task waitUntilExitWithTimeout:timeout > 0 ? timeout : 300.0];
    NSString *text = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
    if (output) *output = text;
    if (status != 0 && error) *error = CAParityRuntimeError(status ?: 500, [NSString stringWithFormat:@"exit %d", status]);
    return status == 0;
}

- (BOOL)downloadArchiveForEntry:(CARuntimeCatalogEntry *)entry toPath:(NSString *)path error:(NSError **)error
{
    if (!entry.archiveURL.length) {
        if (error) *error = CAParityRuntimeError(400, @"entry has no archive_url");
        return NO;
    }
    return [self downloadURLString:entry.archiveURL toPath:path progress:nil error:error];
}

- (BOOL)validateStaging:(NSString *)staging remote:(CARuntimeCatalogEntry *)remote signPaths:(NSArray<NSString *> *)signPaths error:(NSError **)error
{
    if (![NSFileManager.defaultManager fileExistsAtPath:staging]) {
        if (error) *error = CAParityRuntimeError(404, @"staging path missing");
        return NO;
    }
    return YES;
}

- (BOOL)signPaths:(NSArray<NSString *> *)paths staging:(NSString *)staging error:(NSError **)error
{
    return [[CAManagedRuntimeEnvironment sharedEnvironment] signPaths:paths staging:staging error:error];
}

- (BOOL)activateStaging:(NSString *)staging error:(NSError **)error
{
    if (!CAParityFileReadable(staging)) {
        if (error) *error = CAParityRuntimeError(404, @"staging path missing");
        return NO;
    }
    NSString *root = [CARuntimePaths runtimeRootForID:self.runtimeID];
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    return [[NSFileManager defaultManager] moveItemAtPath:staging toPath:root error:error];
}

- (NSString *)statusSummary
{
    if ([self isInstalled]) {
        return [NSString stringWithFormat:@"reverse-tools installed frida=%@ r2=%@",
                [self pathForTool:@"frida"] ?: @"-", [self pathForTool:@"radare2"] ?: @"-"];
    }
    return @"reverse-tools not installed";
}

- (void)restoreCachedRuntimeIfNeededWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion
{
    BOOL installed = [self isInstalled];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(installed, installed ? nil : CAParityRuntimeError(404, @"reverse-tools not installed"));
    });
}
@end
