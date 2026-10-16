//
//  CAStorageManager.m — 目录治理：首次创建、配额、缓存清理、遗留残留清理
//  原包观测：/var/mobile/Library/{Application Support,Caches}/CodexApp、/var/mobile/Library/Preferences/wiki.qaq.codexapp.plist、
//           purge failed %@: %@、cleanupLegacyExternalResidue
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAConversationStore.h"
#import "CAStorageManager.h"
#import "CALogger.h"

@implementation CAStorageManager
{
    NSString *_supportRoot;
    NSString *_temporaryRoot;
    NSString *_cachesRoot;
    NSString *_cliLogsRoot;
}

+ (instancetype)sharedManager
{
    static CAStorageManager *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [CAStorageManager new]; });
    return m;
}

- (BOOL)prepareDirectoriesWithError:(NSError **)error
{
    NSArray<NSString *> *dirs = @[
        CARuntimePaths.supportDirectory,
        CARuntimePaths.cachesDirectory,
        CARuntimePaths.documentsCodexDirectory,
        CARuntimePaths.documentsCodexLogDirectory,
        CARuntimePaths.documentsHelpersDirectory,
        CARuntimePaths.conversationsDirectory,
        CARuntimePaths.artifactsDirectory,
        CARuntimePaths.runtimeDownloadsDirectory,
        CARuntimePaths.composerCatalogCacheDirectory,
        CARuntimePaths.logsDirectory,
        CARuntimePaths.diagnosticsDirectory,
        CARuntimePaths.runtimeProbeDirectory,
    ];
    for (NSString *d in dirs) {
        if (![CARuntimePaths ensureDirectory:d mode:0700 error:error]) return NO;
    }
    return YES;
}

- (void)purgeCachesWithCompletion:(void (^)(NSError *))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSArray<NSString *> *targets = @[ CARuntimePaths.logsCacheDirectory, CARuntimePaths.diagnosticsDirectory,
                                          CARuntimePaths.tmpDirectory ];
        for (NSString *t in targets) {
            if (![NSFileManager.defaultManager removeItemAtPath:t error:&error] && error.code != NSFileNoSuchFileError) {
                CALog(CALogLevelError, @"GENERAL", @"purge failed %@: %@", t, error);
            }
        }
        if (completion) completion(error);
    });
}

#pragma mark - 遗留残留（原包：Codex-mt / CodexHelpers / .codex/log）

- (void)cleanupLegacyExternalResidue
{
    [self cleanupLegacyExternalResidueAtPath:CARuntimePaths.legacyExternalDeviceGroupIDPath];
    [self cleanupLegacyExternalResidueAtPath:CARuntimePaths.legacyExternalDiagnosticsDirectory];
}

- (void)cleanupLegacyExternalResidueAtPath:(NSString *)path
{
    if (!path.length) return;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return;
    NSError *error = nil;
    if ([NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
        CALog(CALogLevelInfo, @"GENERAL", @"protected remove path=%@ success=YES", path);
    } else {
        CALog(CALogLevelWarn, @"GENERAL", @"protected remove path=%@ success=NO error=%@", path, error);
    }
}

#pragma mark - 体积统计

- (unsigned long long)directorySizeAtPath:(NSString *)path
{
    unsigned long long total = 0;
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtPath:path];
    for (NSString *rel in e) {
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:NULL];
        if ([attrs[NSFileType] isEqual:NSFileTypeRegular]) total += [attrs[NSFileSize] unsignedLongLongValue];
    }
    return total;
}

- (void)clearRuntimeDownloadCaches
{
    NSError *error = nil;
    [NSFileManager.defaultManager removeItemAtPath:CARuntimePaths.runtimeDownloadsDirectory error:&error];
    [CARuntimePaths ensureDirectory:CARuntimePaths.runtimeDownloadsDirectory mode:0700 error:&error];
    CALog(CALogLevelInfo, @"RUNTIME", @"runtime download caches cleared");
}

#pragma mark - P2 补齐（原包方法对齐）

static NSString * const kCAStoragePurgeFailedFormat = @"purge failed %@: %@";

#pragma mark 初始化 / 属性

- (instancetype)initWithSupport:(NSString *)support
                      temporary:(NSString *)temporary
                         caches:(NSString *)caches
                       cliLogs:(NSString *)cliLogs
{
    if ((self = [super init])) {
        _supportRoot   = support.length   ? support   : CARuntimePaths.supportDirectory;
        _temporaryRoot = temporary.length ? temporary : CARuntimePaths.tmpDirectory;
        _cachesRoot    = caches.length    ? caches    : CARuntimePaths.cachesDirectory;
        _cliLogsRoot   = cliLogs.length   ? cliLogs   : CARuntimePaths.documentsCodexLogDirectory;
    }
    return self;
}

- (NSString *)support
{
    return _supportRoot ?: CARuntimePaths.supportDirectory;
}

- (NSString *)legacyHelpers
{
    return CARuntimePaths.legacyCodexHelpersDirectory ?: _legacyHelpers;
}

- (NSString *)temporary   { return _temporaryRoot ?: _temporary ?: CARuntimePaths.tmpDirectory; }
- (NSString *)caches      { return _cachesRoot ?: _caches ?: CARuntimePaths.cachesDirectory; }
- (NSString *)cliLogs     { return _cliLogsRoot ?: _cliLogs ?: CARuntimePaths.documentsCodexLogDirectory; }

#pragma mark 体积 / 文件统计

- (unsigned long long)bytesBelow:(NSString *)path
{
    return [self bytesBelow:path excluding:@""];
}

- (unsigned long long)bytesBelow:(NSString *)path excluding:(NSString *)excluding
{
    unsigned long long total = 0;
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtPath:path];
    for (NSString *rel in e) {
        if (excluding.length && [rel hasPrefix:excluding]) {
            e.skipDescendants;
            (void)e;
            continue;
        }        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:NULL];
        if ([attrs[NSFileType] isEqual:NSFileTypeRegular]) total += [attrs[NSFileSize] unsignedLongLongValue];
    }
    return total;
}

- (NSUInteger)regularFilesBelow:(NSString *)path complete:(NSError **)error
{
    NSUInteger count = 0;
    NSDirectoryEnumerator *e = [NSFileManager.defaultManager enumeratorAtPath:path];
    if (!e && error) {
        *error = [NSError errorWithDomain:@"CodexApp.Storage" code:404
                                userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"directory missing path=%@", path ?: @"(none)"] }];
        return 0;
    }
    for (NSString *rel in e) {
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:NULL];
        if ([attrs[NSFileType] isEqual:NSFileTypeRegular]) count++;
    }
    return count;
}

#pragma mark 删除安全校验

- (NSString *)ownedBaseRootForDeletionPath:(NSString *)path
{
    if (!path.length) return nil;
    NSArray<NSString *> *roots = @[ self.support, self.caches, self.temporary, self.cliLogs,
                                    CARuntimePaths.runtimeDownloadsDirectory,
                                    CARuntimePaths.conversationsDirectory,
                                    CARuntimePaths.legacyCodexHelpersDirectory ];
    NSString *full = path.stringByStandardizingPath;
    for (NSString *root in roots) {
        NSString *std = root.stringByStandardizingPath;
        if ([full isEqualToString:std] || [full hasPrefix:[std stringByAppendingString:@"/"]]) return std;
    }
    return nil;
}

- (BOOL)validateDeletionPath:(NSString *)path forTraversal:(BOOL)traversal error:(NSError **)error
{
    if (!path.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Storage" code:400
                                            userInfo:@{ NSLocalizedDescriptionKey: @"validate failed: empty path" }];
        return NO;
    }
    NSString *root = [self ownedBaseRootForDeletionPath:path];
    if (!root) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Storage" code:403
                                            userInfo:@{ NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"validate failed: path outside managed roots path=%@", path] }];
        return NO;
    }
    // traversal=YES：允许删除目录内容；NO：根目录本身不许整删（只许清内容）
    NSString *full = path.stringByStandardizingPath;
    if (!traversal && [full isEqualToString:root]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Storage" code:403
                                            userInfo:@{ NSLocalizedDescriptionKey: @"validate failed: refusing to delete base root" }];
        return NO;
    }
    return YES;
}

- (BOOL)removePath:(NSString *)path bytes:(unsigned long long *)bytes count:(NSUInteger *)count error:(NSError **)error
{
    if (![self validateDeletionPath:path forTraversal:YES error:error]) return NO;
    if (bytes) *bytes = [self bytesBelow:path];
    NSUInteger files = [self regularFilesBelow:path complete:nil];
    NSError *removeError = nil;
    BOOL ok = [NSFileManager.defaultManager removeItemAtPath:path error:&removeError];
    if (!ok && removeError.code != NSFileNoSuchFileError) {
        if (error) *error = removeError;
        CALog(CALogLevelWarn, @"GENERAL", kCAStoragePurgeFailedFormat, path, removeError);
        return NO;
    }
    if (count) *count = files;
    return YES;
}

#pragma mark 清理

- (NSArray<NSString *> *)cacheRoots
{
    return @[ CARuntimePaths.runtimeDownloadsDirectory,
              CARuntimePaths.logsCacheDirectory,
              CARuntimePaths.diagnosticsDirectory,
              CARuntimePaths.runtimeProbeDirectory,
              [CARuntimePaths.conversationsDirectory stringByAppendingPathComponent:@"migration-journal"],
              self.cliLogs,
              self.temporary ];
}

- (NSDictionary *)cleanDirectory:(NSString *)directory
                 preservingNames:(NSArray<NSString *> *)preservingNames
                           bytes:(unsigned long long *)bytes
                           count:(NSUInteger *)count
                           error:(NSError **)error
{
    if (![self validateDeletionPath:directory forTraversal:YES error:error]) return nil;
    unsigned long long freedBytes = 0;
    NSUInteger freedCount = 0;
    NSMutableSet<NSString *> *preserve = [NSMutableSet setWithArray:preservingNames ?: @[]];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL]) {
        if ([preserve containsObject:name]) continue;
        NSString *full = [directory stringByAppendingPathComponent:name];
        freedBytes += [self bytesBelow:full];
        freedCount += [self regularFilesBelow:full complete:nil] ?: 1;
        NSError *removeError = nil;
        if (![NSFileManager.defaultManager removeItemAtPath:full error:&removeError] && removeError.code != NSFileNoSuchFileError) {
            CALog(CALogLevelWarn, @"GENERAL", kCAStoragePurgeFailedFormat, full, removeError);
        }
    }
    if (bytes) *bytes = freedBytes;
    if (count) *count = freedCount;
    return @{ @"path": directory ?: @"", @"bytes": @(freedBytes), @"count": @(freedCount) };
}

- (BOOL)cleanExpiredCaches
{
    // 运行时下载缓存：保留被 prune 显式管理的（由 UpdateManager 调），这里清明显过期的临时包
    [self cleanDirectory:CARuntimePaths.runtimeDownloadsDirectory preservingNames:nil bytes:NULL count:NULL error:NULL];
    // 旧日志 / 诊断 / 运行时探针
    [self cleanDirectory:CARuntimePaths.logsCacheDirectory preservingNames:nil bytes:NULL count:NULL error:NULL];
    [self cleanDirectory:CARuntimePaths.runtimeProbeDirectory preservingNames:nil bytes:NULL count:NULL error:NULL];
    // 迁移 journal 残留（cleanupMigrationJournal 已恢复或孤儿文件）
    [self cleanDirectory:[CARuntimePaths.conversationsDirectory stringByAppendingPathComponent:@"migration-journal"]
         preservingNames:nil bytes:NULL count:NULL error:NULL];
    // 临时附件（tmp 下 ca- 前缀的散件）
    [self cleanDirectory:self.temporary preservingNames:nil bytes:NULL count:NULL error:NULL];
    CALog(CALogLevelInfo, @"GENERAL", @"expired caches cleaned roots=%lu", (unsigned long)self.cacheRoots.count);
    return YES;
}

- (BOOL)resetLocalStatePreservingCredentials
{
    // 清会话 / 缓存 / 日志，保留 auth.json 与 preferences
    NSError *error = nil;
    NSString *auth = CARuntimePaths.authJSONPath;
    NSData *authData = [NSData dataWithContentsOfFile:auth];

    [self cleanDirectory:CARuntimePaths.conversationsDirectory preservingNames:nil bytes:NULL count:NULL error:NULL];
    [self cleanDirectory:CARuntimePaths.cachesDirectory preservingNames:nil bytes:NULL count:NULL error:NULL];
    [self cleanDirectory:CARuntimePaths.runtimeDownloadsDirectory preservingNames:nil bytes:NULL count:NULL error:NULL];
    [self cleanDirectory:self.cliLogs preservingNames:nil bytes:NULL count:NULL error:NULL];
    [self prepareDirectoriesWithError:&error];

    if (authData) {
        [CARuntimePaths writeFileAtomically:auth contents:authData mode:0600 error:NULL];
    }
    CALog(CALogLevelInfo, @"GENERAL", @"local state reset credentials preserved=%@", authData ? @"YES" : @"NO");
    return YES;
}

#pragma mark 快照

- (NSDictionary *)snapshotWithProgress:(void (^)(double, NSString *))progress
{
    NSDictionary<NSString *, NSString *> *paths = @{
        @"support": self.support,
        @"caches": self.caches,
        @"cliLogs": self.cliLogs,
        @"runtimeDownloads": CARuntimePaths.runtimeDownloadsDirectory,
        @"conversations": CARuntimePaths.conversationsDirectory,
    };
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    NSUInteger index = 0;
    for (NSString *key in paths) {
        if (progress) progress((double)index / paths.count, key);
        snapshot[key] = @([self bytesBelow:paths[key]]);
        index++;
    }
    if (progress) progress(1.0, @"complete");
    return snapshot;
}

- (NSDictionary *)protectedPathsComplete:(BOOL)complete conversationBytes:(unsigned long long)conversationBytes livePaths:(NSArray<NSString *> *)livePaths
{
    return @{
        @"complete": @(complete),
        @"conversation_bytes": @(conversationBytes),
        @"live_paths": livePaths ?: @[],
        @"protected": @[ CARuntimePaths.authJSONPath, CARuntimePaths.configTOMLPath, CARuntimePaths.preferencesPlistPath ],
    };
}

@end
