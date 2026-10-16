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

@interface CAUpdateManager ()
@property (nonatomic, assign) unsigned long long latestDownloadSizeBytes;
@end

@implementation CAUpdateManager

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
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe];
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
    NSString *entitlements = [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ResignEntitlements/helper.entitlements.plist"] copy];
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[ @"--adhoc-only", @"--entitlements", entitlements ]];
    [arguments addObjectsFromArray:paths];

    NSTask *task = [NSTask new];
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

@end
