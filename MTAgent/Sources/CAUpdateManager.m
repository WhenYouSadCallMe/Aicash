//
//  CAUpdateManager.m
//  对齐原包：
//    - 下载候选：https://github.com/<owner>/<repo>/releases/download/... 直连 + 代理前缀（gh-proxy.org / ghproxy.net）
//    - 完整性：SHA256SUMS（同 release 获取）+ CC_SHA256 本地比对；cachedPackageAtPath:matchesSHA256:
//    - 解包：tar.gz / deb → CAArchiveExtractor
//    - 签名：Helpers/codex-sign --entitlements <plist>（adhoc / CoreTrust 路径）
//    - 缓存：RuntimeDownloads、pruneRuntimeDownloadCacheExceptVersion:
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAUpdateManager.h"
#import "CAArchiveExtractor.h"
#import "CAExecutionEnvironment.h"
#import "CALogger.h"
#import <CommonCrypto/CommonDigest.h>
#import "CAProcess.h"
#import "CAEmbeddedResignEntitlements.h"
#import "CAStorageManager.h"

@interface CAUpdateManager ()
@property (nonatomic, assign) unsigned long long latestDownloadSizeBytes;
@end

@implementation CAUpdateManager
{
    NSString *_cachedInstalledVersion;
    BOOL _isRecoveringRuntime;
    NSMutableArray *_runtimeRecoveryWaiters;
    BOOL _updateInProgress;
    NSObject<OS_dispatch_queue> *_workQueue;
    NSString *_privateHelperDirectory;
    unsigned long long _latestDownloadSizeBytes;
}

+ (instancetype)sharedManager
{
    static CAUpdateManager *manager; static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [CAUpdateManager new]; });
    return manager;
}

- (NSString *)runtimeDownloadCacheRoot { return CARuntimePaths.runtimeDownloadsDirectory; }

#pragma mark - 下载候选（直连 + 代理）

- (NSArray<NSString *> *)downloadCandidatesForURL:(NSString *)urlString
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSString *prefix in CADownloadProxyPrefixes()) {
        if ([urlString hasPrefix:@"https://github.com/"] || [urlString hasPrefix:@"https://raw.githubusercontent.com/"]) {
            [candidates addObject:[prefix stringByAppendingString:urlString]];
        }
    }
    [candidates addObject:urlString];
    return candidates;
}

- (NSArray<NSString *> *)downloadCandidatesForGitHubURLString:(NSString *)urlString
{
    return [self downloadCandidatesForURL:urlString];
}

#pragma mark - SHA256SUMS

- (void)fetchOfficialSHA256ForAsset:(NSString *)asset version:(NSString *)version completion:(void (^)(NSString *, NSError *))completion
{
    NSString *urlString = [NSString stringWithFormat:CAGitHubSumsFormat, CAUpdateOwner, CAUpdateRepo, version ?: @"latest"];
    NSArray<NSString *> *candidates = [self downloadCandidatesForURL:urlString];
    [self fetchSHA256SumsFromCandidates:candidates index:0 asset:asset completion:completion];
}

- (void)fetchSHA256SumsFromCandidates:(NSArray<NSString *> *)candidates index:(NSUInteger)index asset:(NSString *)asset completion:(void (^)(NSString *, NSError *))completion
{
    if (index >= candidates.count) {
        NSError *error = [NSError errorWithDomain:@"CodexApp.Update" code:404 userInfo:@{ NSLocalizedDescriptionKey: @"SHA256SUMS unavailable" }];
        if (completion) completion(nil, error);
        return;
    }
    NSURL *url = [NSURL URLWithString:candidates[index]];
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSString *text = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (error || http.statusCode >= 400 || !text.length) {
            [self fetchSHA256SumsFromCandidates:candidates index:index + 1 asset:asset completion:completion];
            return;
        }
        NSString *match = nil;
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSArray<NSString *> *parts = [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSArray<NSString *> *filtered = [parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
            if (filtered.count >= 2 && [filtered.lastObject containsString:asset]) {
                match = filtered.firstObject.lowercaseString;
                break;
            }
        }
        if (completion) completion(match, match ? nil : [NSError errorWithDomain:@"CodexApp.Update" code:404 userInfo:@{ NSLocalizedDescriptionKey: @"asset not listed in SHA256SUMS" }]);
    }];
    [task resume];
}

#pragma mark - 下载

- (BOOL)downloadAssetURL:(NSString *)urlString
         destinationPath:(NSString *)destination
                progress:(CAUpdateProgressHandler)progress
                   error:(NSError **)error
{
    __block NSError *lastError = nil;
    __block BOOL ok = NO;
    for (NSString *candidate in [self downloadCandidatesForURL:urlString]) {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithURL:[NSURL URLWithString:candidate]
            completionHandler:^(NSURL *location, NSURLResponse *response, NSError *taskError) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (taskError || http.statusCode >= 400 || !location) {
                lastError = taskError ?: [NSError errorWithDomain:@"CodexApp.Update" code:http.statusCode userInfo:nil];
                dispatch_semaphore_signal(semaphore);
                return;
            }
            [CARuntimePaths ensureDirectory:destination.stringByDeletingLastPathComponent mode:0700 error:NULL];
            NSError *moveError = nil;
            ok = [NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:destination] error:&moveError];
            if (!ok) lastError = moveError;
            dispatch_semaphore_signal(semaphore);
        }];
        [task resume];
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)));
        if (ok) break;
        if (progress) progress(0.0, [NSString stringWithFormat:@"retrying via proxy candidate=%@", candidate]);
    }
    if (!ok && error) *error = lastError ?: [NSError errorWithDomain:@"CodexApp.Update" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"download failed" }];
    if (ok) {
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:destination error:NULL];
        self.latestDownloadSizeBytes = [attrs[NSFileSize] unsignedLongLongValue];
        if (progress) progress(1.0, @"downloaded");
    }
    return ok;
}

- (BOOL)cachedPackageAtPath:(NSString *)path matchesSHA256:(NSString *)sha256
{
    if (!sha256.length) return NO;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex.lowercaseString isEqualToString:sha256.lowercaseString];
}

#pragma mark - 缓存治理

- (void)pruneRuntimeDownloadCacheExceptVersion:(NSString *)version
{
    NSString *root = [self runtimeDownloadCacheRoot];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL]) {
        if (version.length && [name containsString:version]) continue;
        if ([name hasSuffix:@".tar.gz"] || [name hasSuffix:@".deb"] || [name hasSuffix:@".gz"]) {
            [NSFileManager.defaultManager removeItemAtPath:[root stringByAppendingPathComponent:name] error:NULL];
        }
    }
}

- (NSArray<NSString *> *)findExtractedBinariesIn:(NSString *)root codexPath:(NSString **)codexPath hostPath:(NSString **)hostPath
{
    NSMutableArray<NSString *> *binaries = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:root];
    for (NSString *relative in enumerator) {
        NSString *full = [root stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:full isDirectory:&isDirectory] || isDirectory) continue;
        if ([NSFileManager.defaultManager isExecutableFileAtPath:full]) {
            [binaries addObject:full];
            if ([relative hasSuffix:@"/codex"] || [relative hasSuffix:@"/codex-aarch64"]) { if (codexPath) *codexPath = full; }
            if ([relative containsString:@"aarch64-linux"] || [relative containsString:@"x86_64-linux"]) { if (hostPath) *hostPath = full; }
        }
    }
    return binaries;
}

#pragma mark - 解包 + 签名

- (BOOL)installPackageAtPath:(NSString *)packagePath
                 runtimeID:(NSString *)runtimeID
               entitlements:(NSString *)entitlementsPath
                  progress:(CAUpdateProgressHandler)progress
                     error:(NSError **)error
{
    NSString *root = [CARuntimePaths runtimeRootForID:runtimeID];
    if (![CARuntimePaths ensureDirectory:root mode:0755 error:error]) return NO;

    BOOL ok = NO;
    if ([packagePath hasSuffix:@".deb"]) {
        ok = [CAArchiveExtractor extractRuntimeFromDeb:packagePath toDirectory:root progress:progress error:error];
    } else {
        ok = [CAArchiveExtractor extractTarGzip:packagePath toDirectory:root expectedExpandedSize:0 progress:progress error:error];
    }
    if (!ok) return NO;

    NSString *codexPath = nil, *hostPath = nil;
    NSArray<NSString *> *binaries = [self findExtractedBinariesIn:root codexPath:&codexPath hostPath:&hostPath];
    if (progress) progress(0.9, @"signing runtime executables");
    return [self signPaths:binaries staging:nil error:error];
}

- (BOOL)signPaths:(NSArray<NSString *> *)paths staging:(NSString *)staging error:(NSError **)error
{
    if (!paths.count) return YES;
    NSString *signer = CARuntimePaths.codexSignPath;
    if (![NSFileManager.defaultManager isExecutableFileAtPath:signer]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: @"codex-sign exists but is not executable" }];
        CALog(CALogLevelError, @"RUNTIME", @"codex-sign exists but is not executable path=%@", signer);
        return NO;
    }
    NSString *entitlements = CAResignEntitlementsPathForHelper();
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[ @"--adhoc-only", @"--entitlements", entitlements ]];
    [arguments addObjectsFromArray:paths];

    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:signer];
    task.arguments = arguments;
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PATH"] = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    environment[CAEnvHelpers] = CARuntimePaths.helpersDirectory;
    environment[CAEnvTheosHelper] = CARuntimePaths.theosHelperPath;
    task.environment = environment;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError;
        CALog(CALogLevelError, @"RUNTIME", @"codex-sign launch failed error=%@", launchError.localizedDescription);
        return NO;
    }
    [task waitUntilExit];
    BOOL ok = (task.terminationStatus == 0);
    CALog(ok ? CALogLevelInfo : CALogLevelError, @"RUNTIME", @"codex-sign signed %lu file(s) mode=coretrust status=%d",
          (unsigned long)paths.count, task.terminationStatus);
    if (!ok && error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:task.terminationStatus
                                               userInfo:@{ NSLocalizedDescriptionKey: @"CoreTrust bypass failed" }];
    return ok;
}

#pragma mark - P2 补齐（原包方法对齐）

static NSString * const kCAUpdateBackupDirectoryName = @"backup";
static NSString * const kCAUpdateInstalledVersionDefaultsKey = @"CodexManagedRuntimeInstalledVersion";
static NSString * const kCAUpdateLegacyVersionRecordPath = @"/var/mobile/Documents/Codex-mt/runtime-version";

#pragma mark 属性

- (NSObject<OS_dispatch_queue> *)workQueue
{
    if (!_workQueue) _workQueue = dispatch_queue_create("wiki.qaq.codexapp.update", DISPATCH_QUEUE_SERIAL);
    return _workQueue;
}

- (NSMutableArray *)runtimeRecoveryWaiters
{
    if (!_runtimeRecoveryWaiters) _runtimeRecoveryWaiters = [NSMutableArray array];
    return _runtimeRecoveryWaiters;
}

- (NSString *)privateHelperDirectory
{
    if (_privateHelperDirectory.length) return _privateHelperDirectory;
    return [CARuntimePaths.helpersDirectory stringByAppendingPathComponent:@"private"];
}

- (NSString *)cachedInstalledVersion
{
    if (_cachedInstalledVersion.length) return _cachedInstalledVersion;
    return [NSUserDefaults.standardUserDefaults stringForKey:kCAUpdateInstalledVersionDefaultsKey];
}

- (void)setCachedInstalledVersion:(NSString *)version
{
    _cachedInstalledVersion = [version copy];
    if (version.length) [NSUserDefaults.standardUserDefaults setObject:version forKey:kCAUpdateInstalledVersionDefaultsKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kCAUpdateInstalledVersionDefaultsKey];
}

- (BOOL)updateInProgress { return _updateInProgress; }
- (void)setUpdateInProgress:(BOOL)value { _updateInProgress = value; }
- (BOOL)isRecoveringRuntime { return _isRecoveringRuntime; }
- (void)setIsRecoveringRuntime:(BOOL)value { _isRecoveringRuntime = value; }
- (unsigned long long)latestDownloadSizeBytes { return _latestDownloadSizeBytes; }
- (void)setLatestDownloadSizeBytes:(unsigned long long)value { _latestDownloadSizeBytes = value; }

#pragma mark 版本语义

- (NSArray<NSNumber *> *)numericComponentsForVersion:(NSString *)version
{
    if (!version.length) return @[];
    NSMutableArray<NSNumber *> *components = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSUInteger index = 0; index <= version.length; index++) {
        unichar ch = index < version.length ? [version characterAtIndex:index] : 0;
        if (ch >= '0' && ch <= '9') {
            [current appendFormat:@"%C", ch];
        } else {
            if (current.length) { [components addObject:@(current.integerValue)]; [current setString:@""]; }
            else if (index < version.length && ch == '.') { /* 连续分隔符跳过 */ }
        }
    }
    if (components.count == 0 && current.length) [components addObject:@(current.integerValue)];
    return components;
}

- (NSComparisonResult)compareVersion:(NSString *)left toVersion:(NSString *)right
{
    NSArray<NSNumber *> *l = [self numericComponentsForVersion:left];
    NSArray<NSNumber *> *r = [self numericComponentsForVersion:right];
    NSUInteger count = MAX(l.count, r.count);
    for (NSUInteger index = 0; index < count; index++) {
        long long lv = index < l.count ? l[index].longLongValue : 0;
        long long rv = index < r.count ? r[index].longLongValue : 0;
        if (lv < rv) return NSOrderedAscending;
        if (lv > rv) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (BOOL)isValidVersionTag:(NSString *)version
{
    if (!version.length) return NO;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^[0-9]+(\\.[0-9]+)*$"];
    return [predicate evaluateWithObject:version];
}

- (NSString *)logicalVersionForRuntimeReleaseTag:(NSString *)tag
{
    if (!tag.length) return nil;
    // runtime-1.2.3 / v1.2.3 / 1.2.3 → 1.2.3
    NSString *logical = tag;
    if ([logical hasPrefix:@"runtime-"]) logical = [logical substringFromIndex:@"runtime-".length];
    if ([logical hasPrefix:@"v"] && logical.length > 1 && isdigit((int)[logical characterAtIndex:1])) {
        logical = [logical substringFromIndex:1];
    }
    return [self isValidVersionTag:logical] ? logical : nil;
}

- (NSString *)runtimeReleaseTagForVersion:(NSString *)version
{
    if (![self isValidVersionTag:version]) return version;
    return [@"runtime-" stringByAppendingString:version];
}

#pragma mark 探测 / 版本状态

- (BOOL)prefersBundledCodexTestRuntime
{
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"CodexPreferBundledCodexTestRuntime"]) return YES;
    return (NSProcessInfo.processInfo.environment[CAEnvRuntimeEnvKind].length > 0);
}

- (NSString *)activeExecutablePath
{
    NSString *codex = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"codex-aarch64-linux-android"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:codex]) return codex;
    NSString *bundleCodex = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Helpers/codex"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:bundleCodex]) return bundleCodex;
    return nil;
}

- (NSString *)executablePathWithFallback
{
    NSString *primary = [self activeExecutablePath];
    if (primary) return primary;
    for (NSString *candidate in @[ @"/var/jb/usr/bin/codex", @"/usr/local/bin/codex", @"/usr/bin/codex" ]) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

- (BOOL)hasActiveHelper
{
    NSString *executable = [self activeExecutablePath];
    return executable != nil;
}

- (NSDictionary *)helperExecutionEnvironmentWithStaging:(NSString *)staging
{
    NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PATH"] = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    environment[CAEnvHelpers] = CARuntimePaths.helpersDirectory;
    environment[CAEnvTheosHelper] = CARuntimePaths.theosHelperPath;
    if (staging.length) environment[CAEnvUpdateTmpRoot] = staging;
    environment[CAEnvRuntimeRootMode] = @"managed";
    return environment;
}

- (NSString *)installedVersion
{
    if (self.cachedInstalledVersion.length) return self.cachedInstalledVersion;
    NSString *record = [self legacyInstalledVersionRecord];
    if (record.length) { self.cachedInstalledVersion = record; return record; }
    if ([self isManagedRuntime]) return @"unknown";
    return nil;
}

- (BOOL)isInstalled
{
    return [self activeExecutablePath] != nil;
}

- (BOOL)isManagedRuntime
{
    return [NSFileManager.defaultManager fileExistsAtPath:
            [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"codex-aarch64-linux-android"]];
}

- (BOOL)isManagedRuntimeVersion:(NSString *)version
{
    if (![self isManagedRuntime]) return NO;
    NSString *installed = [self installedVersion];
    return installed.length && version.length && [installed isEqualToString:version];
}

- (unsigned long long)installedSizeBytes
{
    return [CAStorageManager.sharedManager directorySizeAtPath:CARuntimePaths.runtimeDownloadsDirectory];
}

- (NSString *)legacyInstalledVersionRecord
{
    NSString *path = kCAUpdateLegacyVersionRecordPath;
    NSString *text = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return text.length ? [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
}

- (void)saveLegacyVersionRecord:(NSString *)version
{
    if (!version.length) return;
    [CARuntimePaths writeFileAtomically:kCAUpdateLegacyVersionRecordPath
                               contents:[version dataUsingEncoding:NSUTF8StringEncoding]
                                   mode:0600
                                  error:NULL];
    self.cachedInstalledVersion = version;
}

- (NSString *)cachedDebPathForVersion:(NSString *)version
{
    if (!version.length) return nil;
    NSString *root = [self runtimeDownloadCacheRoot];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL]) {
        if (![name hasSuffix:@".deb"]) continue;
        if ([name containsString:version]) return [root stringByAppendingPathComponent:name];
    }
    return nil;
}

- (NSString *)locateToolNamed:(NSString *)name
{
    if (!name.length) return nil;
    for (NSString *directory in @[ CARuntimePaths.helpersDirectory,
                                   CARuntimePaths.reverseToolsDirectory,
                                   @"/var/jb/usr/bin", @"/usr/local/bin", @"/usr/bin" ]) {
        NSString *candidate = [directory stringByAppendingPathComponent:name];
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

- (NSString *)resolvedBundledSignerPath
{
    NSString *signer = CARuntimePaths.codexSignPath;
    return [NSFileManager.defaultManager isExecutableFileAtPath:signer] ? signer : nil;
}

- (NSString *)resolvedEntitlementsPathInWorkDir:(NSString *)workDirectory
{
    NSString *inWork = [workDirectory stringByAppendingPathComponent:@"entitlements.plist"];
    if ([NSFileManager.defaultManager fileExistsAtPath:inWork]) return inWork;
    return CAResignEntitlementsPathForRuntime();
}

#pragma mark 哈希 / 签名 / 执行

- (NSString *)sha256ForFileAtPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex.lowercaseString;
}

- (BOOL)signBinary:(NSString *)path withLdid:(NSString *)ldidPath entitlementsPath:(NSString *)entitlementsPath error:(NSError **)error
{
    if (!path.length) return NO;
    // 优先内嵌 codex-sign（CoreTrust 路径）；显式 ldid 时走 ldid -S
    if (!ldidPath.length && [self resolvedBundledSignerPath]) {
        return [self signPaths:@[ path ] staging:nil error:error];
    }
    NSString *ldid = ldidPath.length ? ldidPath : [self locateToolNamed:@"ldid"];
    if (!ldid.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: @"signing tool unavailable (codex-sign/ldid)" }];
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:ldid];
    NSMutableArray *arguments = [NSMutableArray array];
    if (entitlementsPath.length) [arguments addObjectsFromArray:@[ @"-S", entitlementsPath ]];
    else [arguments addObject:@"-S"];
    [arguments addObject:path];
    task.arguments = arguments;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) { if (error) *error = launchError; return NO; }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:task.terminationStatus
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"ldid sign failed status=%d", task.terminationStatus] }];
        return NO;
    }
    CALog(CALogLevelInfo, @"RUNTIME", @"verify launchable sign binary path=%@ tool=ldid status=0", path);
    return YES;
}

- (BOOL)runExecutable:(NSString *)executable
            arguments:(NSArray<NSString *> *)arguments
           environment:(NSDictionary<NSString *, NSString *> *)environment
              timeout:(NSTimeInterval)timeout
               output:(NSString **)output
                error:(NSError **)error
{
    if (!executable.length || ![NSFileManager.defaultManager isExecutableFileAtPath:executable]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"executable missing path=%@", executable ?: @"(none)"] }];
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments ?: @[];
    task.environment = environment ?: NSProcessInfo.processInfo.environment;
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError;
        return NO;
    }
    int status = [task waitUntilExitWithTimeout:timeout > 0 ? timeout : 30.0];
    NSData *outData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    NSData *errData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
    NSString *combined = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *errText = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
    if (errText.length) combined = [combined stringByAppendingString:errText];
    if (output) *output = combined;
    if (status != 0) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:status
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"executable failed path=%@ status=%d output=%@", executable, status, combined] }];
        return NO;
    }
    return YES;
}

- (NSString *)verifyBinaryLaunchability:(NSString *)binaryPath expectedVersion:(NSString *)expectedVersion error:(NSError **)error
{
    NSString *output = nil;
    NSError *runError = nil;
    BOOL ok = [self runExecutable:binaryPath
                        arguments:@[ @"--version" ]
                      environment:[self helperExecutionEnvironmentWithStaging:nil]
                          timeout:30.0
                           output:&output
                            error:&runError];
    if (!ok) {
        if (error) *error = runError;
        CALog(CALogLevelWarn, @"RUNTIME", @"verify launchable failed path=%@ error=%@", binaryPath, runError.localizedDescription ?: @"unknown");
        return nil;
    }
    // 从输出里解析版本（codex --version → "codex x.y.z ..."）
    NSString *version = nil;
    for (NSString *token in [output componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if ([self isValidVersionTag:token]) { version = token; break; }
    }
    if (expectedVersion.length && version && [self compareVersion:version toVersion:expectedVersion] != NSOrderedSame) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:1
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"verify launchable version mismatch expected=%@ actual=%@", expectedVersion, version] }];
        return version;
    }
    CALog(CALogLevelInfo, @"RUNTIME", @"verify launchable ok path=%@ version=%@", binaryPath, version ?: @"(unknown)");
    return version;
}

- (NSString *)validateBinaryLaunchability:(NSString *)binaryPath expectedVersion:(NSString *)expectedVersion error:(NSError **)error
{
    // validate 是 verify 的严格包装：版本必须解析成功且匹配
    NSString *version = [self verifyBinaryLaunchability:binaryPath expectedVersion:expectedVersion error:error];
    if (!version && error && *error) return nil;
    if (!version) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:1
                                            userInfo:@{ NSLocalizedDescriptionKey: @"validate launchable: version output missing" }];
        return nil;
    }
    return version;
}

- (NSString *)validatedCodexEntryFromManifestData:(NSData *)manifestData error:(NSError **)error
{
    if (!manifestData.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:400
                                            userInfo:@{ NSLocalizedDescriptionKey: @"manifest data empty" }];
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:400
                                                       userInfo:@{ NSLocalizedDescriptionKey: @"manifest is not an object" }];
        return nil;
    }
    NSString *entry = ((NSDictionary *)json)[@"codex_entry"];
    if (![entry isKindOfClass:NSString.class] || !entry.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: @"manifest missing codex_entry" }];
        return nil;
    }
    return entry;
}

#pragma mark 解包 / 原子交换 / 回滚

- (BOOL)extractDebPath:(NSString *)debPath toDirectory:(NSString *)destination progress:(CAUpdateProgressHandler)progress error:(NSError **)error
{
    if (![debPath hasSuffix:@".deb"] || ![NSFileManager.defaultManager fileExistsAtPath:debPath]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"deb missing path=%@", debPath ?: @"(none)"] }];
        return NO;
    }
    // CAArchiveExtractor 已支持 deb（ar 容器 → data.tar.{gz,xz,zst}），直接调
    return [CAArchiveExtractor extractRuntimeFromDeb:debPath toDirectory:destination progress:progress error:error];
}

- (BOOL)atomicSwapStagingCodex:(NSString *)stagingCodexPath
                   stagingHost:(NSString *)stagingHostPath
                       version:(NSString *)version
                         error:(NSError **)error
{
    if (![NSFileManager.defaultManager isExecutableFileAtPath:stagingCodexPath]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: @"staging codex missing" }];
        return NO;
    }
    // 校验 staging 产物
    NSString *entry = [self verifyBinaryLaunchability:stagingCodexPath expectedVersion:version error:error];
    if (!entry) return NO;

    NSString *downloads = CARuntimePaths.runtimeDownloadsDirectory;
    [CARuntimePaths ensureDirectory:downloads mode:0755 error:error];
    NSString *targetCodex = [downloads stringByAppendingPathComponent:@"codex-aarch64-linux-android"];
    NSString *targetHost  = [downloads stringByAppendingPathComponent:@"code-mode-host"];
    NSString *backupRoot  = [downloads stringByAppendingPathComponent:kCAUpdateBackupDirectoryName];
    [CARuntimePaths ensureDirectory:backupRoot mode:0755 error:NULL];

    // 1) 旧文件挪进 backup/
    NSMutableArray<NSDictionary *> *backups = [NSMutableArray array];
    for (NSString *target in @[ targetCodex, targetHost ]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:target]) continue;
        NSString *backup = [backupRoot stringByAppendingPathComponent:target.lastPathComponent];
        [NSFileManager.defaultManager removeItemAtPath:backup error:NULL];
        NSError *moveError = nil;
        if (![NSFileManager.defaultManager moveItemAtPath:target toPath:backup error:&moveError]) {
            // 回滚：把已挪走的搬回来
            for (NSDictionary *pair in backups) {
                [NSFileManager.defaultManager moveItemAtPath:pair[@"backup"] toPath:pair[@"target"] error:NULL];
            }
            if (error) *error = moveError;
            CALog(CALogLevelWarn, @"RUNTIME", @"atomic swap backup move failed path=%@ error=%@", target, moveError.localizedDescription ?: @"unknown");
            return NO;
        }
        [backups addObject:@{ @"backup": backup, @"target": target }];
    }

    // 2) staging 原子 rename 到目标
    NSError *swapError = nil;
    BOOL ok = [NSFileManager.defaultManager moveItemAtPath:stagingCodexPath toPath:targetCodex error:&swapError];
    if (ok && stagingHostPath.length && [NSFileManager.defaultManager fileExistsAtPath:stagingHostPath]) {
        ok = [NSFileManager.defaultManager moveItemAtPath:stagingHostPath toPath:targetHost error:&swapError];
    }

    // 3) 失败 → 从 backup 回滚
    if (!ok) {
        for (NSDictionary *pair in backups) {
            [NSFileManager.defaultManager removeItemAtPath:pair[@"target"] error:NULL];
            [NSFileManager.defaultManager moveItemAtPath:pair[@"backup"] toPath:pair[@"target"] error:NULL];
        }
        if (error) *error = swapError;
        CALog(CALogLevelError, @"RUNTIME", @"atomic swap failed rolled back error=%@", swapError.localizedDescription ?: @"unknown");
        return NO;
    }

    // 4) 成功 → 写版本记录，清 backup
    if (version.length) { [self saveLegacyVersionRecord:version]; }
    [NSFileManager.defaultManager removeItemAtPath:backupRoot error:NULL];
    CALog(CALogLevelInfo, @"RUNTIME", @"atomic swap ok version=%@", version ?: @"(none)");
    return YES;
}

- (BOOL)rollbackToPreviousVersion:(NSError **)error
{
    NSString *backupRoot = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:kCAUpdateBackupDirectoryName];
    NSString *targetCodex = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"codex-aarch64-linux-android"];
    NSString *backupCodex = [backupRoot stringByAppendingPathComponent:targetCodex.lastPathComponent];

    if ([NSFileManager.defaultManager fileExistsAtPath:backupCodex]) {
        NSError *moveError = nil;
        [NSFileManager.defaultManager removeItemAtPath:targetCodex error:NULL];
        if ([NSFileManager.defaultManager moveItemAtPath:backupCodex toPath:targetCodex error:&moveError]) {
            CALog(CALogLevelInfo, @"RUNTIME", @"rollback from backup ok");
            return YES;
        }
        if (error) *error = moveError;
    }

    // 从缓存同版本包重新安装
    NSString *version = [self installedVersion];
    NSString *cachedDeb = [self cachedDebPathForVersion:version];
    NSString *cachedTar = [CARuntimePaths archiveCachePathForEntry:version ?: @"default" sha256:nil];
    NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ca-rollback-staging"];
    [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
    [CARuntimePaths ensureDirectory:staging mode:0755 error:NULL];
    BOOL extracted = NO;
    if (cachedDeb) extracted = [self extractDebPath:cachedDeb toDirectory:staging progress:nil error:error];
    else if ([NSFileManager.defaultManager fileExistsAtPath:cachedTar]) {
        extracted = [CAArchiveExtractor extractTarGzip:cachedTar toDirectory:staging expectedExpandedSize:0 progress:nil error:error];
    }
    if (!extracted) {
        if (error && !*error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                                      userInfo:@{ NSLocalizedDescriptionKey: @"rollback: no backup or cached package" }];
        return NO;
    }
    NSString *codexPath = nil, *hostPath = nil;
    [self findExtractedBinariesIn:staging codexPath:&codexPath hostPath:&hostPath];
    if (!codexPath) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: @"rollback: codex binary not found in cached package" }];
        return NO;
    }
    BOOL swapped = [self atomicSwapStagingCodex:codexPath stagingHost:hostPath version:version error:error];
    [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
    if (swapped) CALog(CALogLevelInfo, @"RUNTIME", @"rollback from cache ok version=%@", version ?: @"(none)");
    return swapped;
}

- (void)restoreCachedRuntimeIfNeededWithCompletion:(void (^)(BOOL, NSError *))completion
{
    dispatch_async(self.workQueue, ^{
        if (self.isRecoveringRuntime) {
            if (completion) [self.runtimeRecoveryWaiters addObject:[completion copy]];
            return;
        }
        self.isRecoveringRuntime = YES;
        if ([self hasActiveHelper]) {
            self.isRecoveringRuntime = NO;
            for (void (^waiter)(BOOL, NSError *) in self.runtimeRecoveryWaiters) waiter(YES, nil);
            [self.runtimeRecoveryWaiters removeAllObjects];
            if (completion) completion(YES, nil);
            return;
        }
        NSString *version = [self installedVersion] ?: @"";
        NSString *cachedDeb = [self cachedDebPathForVersion:version];
        NSString *cachedTar = [CARuntimePaths archiveCachePathForEntry:version.length ? version : @"default" sha256:nil];
        NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ca-recovery-staging"];
        [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
        [CARuntimePaths ensureDirectory:staging mode:0755 error:NULL];
        NSError *error = nil;
        BOOL extracted = NO;
        if (cachedDeb) extracted = [self extractDebPath:cachedDeb toDirectory:staging progress:nil error:&error];
        else if ([NSFileManager.defaultManager fileExistsAtPath:cachedTar]) {
            extracted = [CAArchiveExtractor extractTarGzip:cachedTar toDirectory:staging expectedExpandedSize:0 progress:nil error:&error];
        }
        BOOL restored = NO;
        if (extracted) {
            NSString *codexPath = nil, *hostPath = nil;
            [self findExtractedBinariesIn:staging codexPath:&codexPath hostPath:&hostPath];
            if (codexPath) {
                restored = [self atomicSwapStagingCodex:codexPath stagingHost:hostPath version:version error:&error];
            }
        }
        [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
        self.isRecoveringRuntime = NO;
        for (void (^waiter)(BOOL, NSError *) in self.runtimeRecoveryWaiters) waiter(restored, error);
        [self.runtimeRecoveryWaiters removeAllObjects];
        if (completion) completion(restored, restored ? nil : error);
    });
}

- (BOOL)removeInstalledRuntime:(NSString *)runtimeID error:(NSError **)error
{
    NSString *root = runtimeID.length
        ? [CARuntimePaths runtimeRootForID:runtimeID]
        : CARuntimePaths.runtimeDownloadsDirectory;
    if (![NSFileManager.defaultManager fileExistsAtPath:root]) return YES;
    // 安全校验：目标必须在 RuntimeDownloads 目录内
    NSString *downloadsRoot = CARuntimePaths.runtimeDownloadsDirectory.stringByStandardizingPath;
    NSString *full = root.stringByStandardizingPath;
    if (![full hasPrefix:[downloadsRoot stringByAppendingString:@"/"]]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Update" code:403
                                            userInfo:@{ NSLocalizedDescriptionKey: @"remove rejected: path outside runtime root" }];
        return NO;
    }
    NSError *removeError = nil;
    BOOL ok = [NSFileManager.defaultManager removeItemAtPath:full error:&removeError];
    if (!ok) { if (error) *error = removeError; return NO; }
    if (!runtimeID.length) [NSFileManager.defaultManager createDirectoryAtPath:downloadsRoot withIntermediateDirectories:YES attributes:nil error:NULL];
    self.cachedInstalledVersion = nil;
    CALog(CALogLevelInfo, @"RUNTIME", @"runtime removed root=%@", full);
    return YES;
}

- (BOOL)removeManagedBundleRuntime:(NSString *)runtimeID
{
    return [self removeInstalledRuntime:runtimeID error:NULL];
}

#pragma mark 更新流程

- (void)checkLatestVersion:(NSString *)runtimeID completion:(void (^)(NSString *, NSError *))completion
{
    // runtime-manifest 路径：raw manifest（走代理候选）
    dispatch_async(self.workQueue, ^{
        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:CARuntimeManifestURL]
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (error || http.statusCode >= 400) {
                // 回退 GitHub API
                [self checkLatestVersionViaGitHubAPI:runtimeID completion:completion];
                return;
            }
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSString *version = nil;
            if ([json isKindOfClass:NSDictionary.class]) {
                for (NSDictionary *entry in ((NSDictionary *)json)[@"runtimes"]) {
                    if (![entry isKindOfClass:NSDictionary.class]) continue;
                    if (runtimeID.length && ![runtimeID isEqualToString:entry[@"runtime_id"]]) continue;
                    version = [self logicalVersionForRuntimeReleaseTag:entry[@"version"] ?: entry[@"archive_url"]];
                    if (version) break;
                }
            }
            if (version) { if (completion) completion(version, nil); }
            else [self checkLatestVersionViaGitHubAPI:runtimeID completion:completion];
        }];
        [task resume];
    });
}

- (void)checkLatestVersionViaGitHubAPI:(NSString *)runtimeID completion:(void (^)(NSString *, NSError *))completion
{
    NSString *urlString = [NSString stringWithFormat:CAGitHubReleasesFormat, CAUpdateOwner, CAUpdateRepo];
    dispatch_async(self.workQueue, ^{
        NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:urlString]
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            if (error || http.statusCode >= 400 || !data.length) {
                NSError *failure = error ?: [NSError errorWithDomain:@"CodexApp.Update" code:http.statusCode
                                                           userInfo:@{ NSLocalizedDescriptionKey: @"GitHub API latest release unavailable" }];
                if (completion) completion(nil, failure);
                return;
            }
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSString *version = nil;
            if ([json isKindOfClass:NSArray.class]) {
                for (NSDictionary *release in (NSArray *)json) {
                    if (![release isKindOfClass:NSDictionary.class]) continue;
                    NSString *tag = release[@"tag_name"];
                    if (![tag isKindOfClass:NSString.class]) continue;
                    if (runtimeID.length && ![tag.lowercaseString containsString:runtimeID.lowercaseString]) continue;
                    version = [self logicalVersionForRuntimeReleaseTag:tag] ?: tag;
                    break;
                }
            }
            if (completion) completion(version, version ? nil
                                                  : [NSError errorWithDomain:@"CodexApp.Update" code:404
                                                                       userInfo:@{ NSLocalizedDescriptionKey: @"no matching release" }]);
        }];
        [task resume];
    });
}

- (void)updateToVersion:(NSString *)version
               progress:(CAUpdateProgressHandler)progress
             completion:(void (^)(BOOL, NSError *))completion
{
    dispatch_async(self.workQueue, ^{
        if (self.updateInProgress) {
            if (completion) completion(NO, [NSError errorWithDomain:@"CodexApp.Update" code:409
                                                     userInfo:@{ NSLocalizedDescriptionKey: @"update already in progress" }]);
            return;
        }
        self.updateInProgress = YES;
        [self checkLatestVersion:@"" completion:^(NSString *_Nullable latest, NSError *_Nullable checkError) {
            if (checkError || !latest.length) {
                self.updateInProgress = NO;
                if (completion) completion(NO, checkError);
                return;
            }
            if ([self compareVersion:latest toVersion:version] != NSOrderedDescending) {
                self.updateInProgress = NO;
                if (completion) completion(YES, nil);   // 已是最新
                return;
            }
            NSString *tag = [self runtimeReleaseTagForVersion:latest];
            NSString *asset = [NSString stringWithFormat:@"codex-runtime-%@.tar.gz", latest];
            NSString *assetURL = [NSString stringWithFormat:CAGitHubAssetFormat, CAUpdateOwner, CAUpdateRepo, tag, asset];
            NSString *destination = [[self runtimeDownloadCacheRoot] stringByAppendingPathComponent:asset];
            __block NSString *sha256 = nil;
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);
            [self fetchOfficialSHA256ForAsset:asset version:tag completion:^(NSString *sum, NSError *err) {
                sha256 = sum;
                dispatch_group_leave(group);
            }];
            dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));
            if (![self downloadAssetURL:assetURL destinationPath:destination progress:progress error:&checkError]) {
                self.updateInProgress = NO;
                if (completion) completion(NO, checkError);
                return;
            }
            if (sha256.length && ![self cachedPackageAtPath:destination matchesSHA256:sha256]) {
                self.updateInProgress = NO;
                if (completion) completion(NO, [NSError errorWithDomain:@"CodexApp.Update" code:1
                                                        userInfo:@{ NSLocalizedDescriptionKey: @"sha256 mismatch" }]);
                return;
            }
            NSString *staging = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ca-update-staging"];
            [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
            [CARuntimePaths ensureDirectory:staging mode:0755 error:NULL];
            if (![CAArchiveExtractor extractTarGzip:destination toDirectory:staging expectedExpandedSize:0 progress:progress error:&checkError]) {
                self.updateInProgress = NO;
                if (completion) completion(NO, checkError);
                return;
            }
            NSString *codexPath = nil, *hostPath = nil;
            [self findExtractedBinariesIn:staging codexPath:&codexPath hostPath:&hostPath];
            if (progress) progress(0.8, @"signing");
            if (codexPath && ![self signBinary:codexPath withLdid:@"" entitlementsPath:@"" error:&checkError]) {
                self.updateInProgress = NO;
                if (completion) completion(NO, checkError);
                return;
            }
            BOOL swapped = [self atomicSwapStagingCodex:codexPath stagingHost:hostPath version:latest error:&checkError];
            [NSFileManager.defaultManager removeItemAtPath:staging error:NULL];
            [self pruneRuntimeDownloadCacheExceptVersion:latest];
            self.updateInProgress = NO;
            if (completion) completion(swapped, swapped ? nil : checkError);
        }];
    });
}

@end
