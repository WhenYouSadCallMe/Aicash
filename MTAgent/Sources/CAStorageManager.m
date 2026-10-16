//
//  CAStorageManager.m — 目录治理：首次创建、配额、缓存清理、遗留残留清理
//  原包观测：/var/mobile/Library/{Application Support,Caches}/CodexApp、/var/mobile/Library/Preferences/wiki.qaq.codexapp.plist、
//           purge failed %@: %@、cleanupLegacyExternalResidue
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAStorageManager.h"

@implementation CAStorageManager

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

@end
