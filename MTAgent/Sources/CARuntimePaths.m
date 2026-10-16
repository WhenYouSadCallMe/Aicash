//
//  CARuntimePaths.m — 路径与目录契约（原包观测：/var/mobile/... 、CodexHelpers、RuntimeDownloads …）
//

#import "CACommon.h"
#import "CARuntimePaths.h"

@implementation CARuntimePaths

#pragma mark - 固定根

+ (NSString *)documentsDirectory        { return @"/var/mobile/Documents"; }
+ (NSString *)documentsCodexDirectory   { return @"/var/mobile/Documents/.codex"; }
+ (NSString *)documentsCodexLogDirectory{ return @"/var/mobile/Documents/.codex/log"; }
+ (NSString *)documentsHelpersDirectory  { return @"/var/mobile/Documents/CodexHelpers"; }
+ (NSString *)documentsCodexMTDirectory  { return @"/var/mobile/Documents/Codex-mt"; }

+ (NSString *)supportDirectory           { return @"/var/mobile/Library/Application Support/CodexApp"; }
+ (NSString *)cachesDirectory            { return @"/var/mobile/Library/Caches/CodexApp"; }
+ (NSString *)preferencesPlistPath       { return @"/var/mobile/Library/Preferences/wiki.qaq.codexapp.plist"; }

// 原包观测字面量：.mt-device-group-id-v1（当前）/ Codex-mt/…（旧位置，需清理）
+ (NSString *)deviceGroupIDPath          { return @"/var/mobile/Documents/.mt-device-group-id-v1"; }
+ (NSString *)legacyExternalDeviceGroupIDPath { return @"/var/mobile/Documents/Codex-mt/device-group-id-v1"; }
+ (NSString *)legacyExternalDiagnosticsDirectory { return @"/var/mobile/Documents/Codex-mt/Diagnostics"; }
+ (NSString *)legacyCodexHelpersDirectory { return @"/var/mobile/Documents/CodexHelpers"; }

#pragma mark - Codex Home / 工作区

+ (NSString *)codexHome
{
    NSString *env = NSProcessInfo.processInfo.environment[CAEnvCodexHome];
    if (env.length) return env;
    NSString *pref = [NSUserDefaults.standardUserDefaults stringForKey:@"CodexHome"];
    if (pref.length) return pref;
    return @"/var/mobile/Documents/.codex";
}

+ (NSString *)authJSONPath          { return [[self codexHome] stringByAppendingPathComponent:@"auth.json"]; }
+ (NSString *)configTOMLPath        { return [[self codexHome] stringByAppendingPathComponent:@"config.toml"]; }
+ (NSString *)thirdPartyCatalogPath { return [[self supportDirectory] stringByAppendingPathComponent:@"third-party-models.json"]; }
+ (NSString *)sessionsDirectory     { return [[self codexHome] stringByAppendingPathComponent:@"sessions"]; }
+ (NSString *)archivedSessionsDirectory { return [[self codexHome] stringByAppendingPathComponent:@"archived_sessions"]; }
+ (NSString *)conversationsDirectory { return [[self supportDirectory] stringByAppendingPathComponent:@"CodexApp/Conversations"]; }
+ (NSString *)artifactsDirectory     { return [[self supportDirectory] stringByAppendingPathComponent:@"CodexApp/Conversations/Artifacts"]; }
+ (NSString *)composerCatalogCacheDirectory { return [[self supportDirectory] stringByAppendingPathComponent:@"CodexApp/ComposerCatalog"]; }
+ (NSString *)logsDirectory          { return [[self supportDirectory] stringByAppendingPathComponent:@"CodexApp/Logs"]; }
+ (NSString *)legacyLogsDirectory    { return @"/var/mobile/Documents/.codex/log"; }
+ (NSString *)runtimeDownloadsDirectory { return [[self supportDirectory] stringByAppendingPathComponent:@"RuntimeDownloads"]; }
+ (NSString *)reverseToolsDirectory  { return [[self runtimeDownloadsDirectory] stringByAppendingPathComponent:@"ReverseTools"]; }
+ (NSString *)logsCacheDirectory     { return [[self cachesDirectory] stringByAppendingPathComponent:@"Logs"]; }
+ (NSString *)diagnosticsDirectory   { return [[self cachesDirectory] stringByAppendingPathComponent:@"Diagnostics"]; }
+ (NSString *)runtimeProbeDirectory  { return [[self diagnosticsDirectory] stringByAppendingPathComponent:@"RuntimeProbe"]; }
+ (NSString *)tmpDirectory           { return NSTemporaryDirectory(); }
+ (NSString *)globalTmpDirectory     { return @"/private/tmp"; }

#pragma mark - helper 可执行文件

+ (NSString *)helpersDirectory
{
    return [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Helpers"] copy];
}
+ (NSString *)bashRealPath      { return [[self helpersDirectory] stringByAppendingPathComponent:@"bash.real"]; }
+ (NSString *)bashPath          { return [[self helpersDirectory] stringByAppendingPathComponent:@"bash"]; }
+ (NSString *)shPath            { return [[self helpersDirectory] stringByAppendingPathComponent:@"sh"]; }
+ (NSString *)bashCodexPath     { return [[self helpersDirectory] stringByAppendingPathComponent:@"bash-codex"]; }
+ (NSString *)fileToolPath      { return [[self helpersDirectory] stringByAppendingPathComponent:@"ca-filetool"]; }
+ (NSString *)codexSignPath     { return [[self helpersDirectory] stringByAppendingPathComponent:@"codex-sign"]; }
+ (NSString *)theosHelperPath   { return [[self helpersDirectory] stringByAppendingPathComponent:@"theos-helper"]; }
+ (NSString *)bundledCACertPath { return [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"cacert.pem"] copy]; }

// 原包观测的 PATH 顺序
+ (NSString *)helperSearchPath
{
    return [@[ @"/usr/local/bin", @"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin",
               @"/var/jb/usr/bin", @"/var/jb/bin" ] componentsJoinedByString:@":"];
}

+ (NSString *)jailbreakRootPath
{
    if ([NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/usr/bin"]) return @"/var/jb/usr/bin";
    if ([NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/bin"])     return @"/var/jb/bin";
    return @"/var/jb/usr/bin";
}

#pragma mark - 运行时安装位置

+ (NSString *)runtimeRootForID:(NSString *)runtimeID
{
    return [[self runtimeDownloadsDirectory] stringByAppendingPathComponent:runtimeID];
}
+ (NSString *)installedManifestPathForRuntimeID:(NSString *)runtimeID
{
    return [[self runtimeRootForID:runtimeID] stringByAppendingPathComponent:@"manifest.json"];
}
+ (NSString *)archiveCachePathForEntry:(NSString *)runtimeID sha256:(NSString *)sha
{
    NSString *name = sha.length ? [NSString stringWithFormat:@"runtime-%@.tar.gz", sha] : [NSString stringWithFormat:@"runtime-%@.tar.gz", runtimeID];
    return [[self runtimeDownloadsDirectory] stringByAppendingPathComponent:name];
}

#pragma mark - 常用构建

// P2 补齐（原包方法对齐）：PARITY-SELECTOR-PLACEHOLDER 12 个 + thirdPartyModelCatalogPath

+ (NSString *)appBundleRoot
{
    return [NSBundle.mainBundle.bundlePath copy];
}

+ (NSString *)applicationSupportRoot
{
    return [self supportDirectory];
}

+ (NSString *)codexHomeDirectory
{
    return [self codexHome];
}

+ (NSString *)bundleHelpersDirectory
{
    return [[self appBundleRoot] stringByAppendingPathComponent:@"Helpers"];
}

+ (NSString *)bundleCodexExecutable
{
    // 原包观测：内置 codex 位于 Helpers/codex（无后缀可执行）；缺失时返回 nil 由运行时安装兜底
    NSString *candidate = [[self bundleHelpersDirectory] stringByAppendingPathComponent:@"codex"];
    return [NSFileManager.defaultManager isExecutableFileAtPath:candidate] ? candidate : nil;
}

+ (NSString *)bundleCodeModeHostExecutable
{
    // 原包：code-mode host 对齐 activeCodeModeHostPath 语义（bash.real 承担）
    return [self bashRealPath];
}

+ (NSString *)bundlePythonRuntimeRoot
{
    // 原包观察 .PythonRuntime.backup / PythonHome/lib/python3.13 → 内置根为 bundle/PythonRuntime
    NSString *candidate = [[self appBundleRoot] stringByAppendingPathComponent:@"PythonRuntime"];
    return [NSFileManager.defaultManager fileExistsAtPath:candidate] ? candidate : nil;
}

+ (NSString *)bundleReverseToolsRuntimeRoot
{
    NSString *candidate = [[self appBundleRoot] stringByAppendingPathComponent:@"ReverseTools"];
    return [NSFileManager.defaultManager fileExistsAtPath:candidate] ? candidate : nil;
}

+ (NSString *)bundleTheosRuntimeRoot
{
    NSString *candidate = [[self appBundleRoot] stringByAppendingPathComponent:@"Theos"];
    return [NSFileManager.defaultManager fileExistsAtPath:candidate] ? candidate : nil;
}

+ (NSString *)remoteStateDirectory
{
    // 原包 remoteOperations 状态目录（对齐 support/CodexApp/Remote）
    return [[self supportDirectory] stringByAppendingPathComponent:@"Remote"];
}

+ (NSString *)runtimeConfigurationDirectory
{
    // 模型价格/运行时配置目录（原包 runtimeConfigurationDirectory 与 modelCosts 同层）
    return [[self supportDirectory] stringByAppendingPathComponent:@"RuntimeConfig"];
}

+ (NSString *)thirdPartyModelCatalogPath
{
    return [[self runtimeConfigurationDirectory] stringByAppendingPathComponent:@"third-party-models.json"];
}

+ (NSString *)executableNamed:(NSString *)name environment:(NSDictionary *)environment
{
    if (name.length == 0) return nil;
    if ([name hasPrefix:@"/"]) {
        return [NSFileManager.defaultManager isExecutableFileAtPath:name] ? name : nil;
    }
    NSMutableArray<NSString *> *searchPaths = [NSMutableArray array];
    [searchPaths addObject:[self bundleHelpersDirectory]];
    [searchPaths addObjectsFromArray:[self helperSearchPathComponents]];
    NSString *pathEnv = environment[@"PATH"];
    if ([pathEnv isKindOfClass:[NSString class]] && pathEnv.length) {
        [searchPaths addObjectsFromArray:[pathEnv componentsSeparatedByString:@":"]];
    }
    for (NSString *dir in searchPaths) {
        if (dir.length == 0) continue;
        NSString *candidate = [dir stringByAppendingPathComponent:name];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

+ (NSArray<NSString *> *)helperSearchPathComponents
{
    // 对齐原包 helperSearchPath（复用既有 PATH 顺序，拆成数组供 executableNamed:environment: 使用）
    return [[self helperSearchPath] componentsSeparatedByString:@":"];
}

+ (NSString *)safeRelativePath:(NSString *)relative inRoot:(NSString *)root error:(NSError **)error
{
    if (!relative.length) return nil;
    NSString *cleaned = relative.stringByStandardizingPath;
    while ([cleaned hasPrefix:@"/"]) cleaned = [cleaned substringFromIndex:1];
    NSArray<NSString *> *comps = cleaned.pathComponents;
    for (NSString *c in comps) {
        if ([c isEqualToString:@".."]) {
            if (error) *error = [NSError errorWithDomain:@"CodexApp.Path" code:403
                                                userInfo:@{ NSLocalizedDescriptionKey: @"policy rejected: path escapes root" }];
            return nil;
        }
    }
    NSString *full = [root stringByAppendingPathComponent:cleaned].stringByStandardizingPath;
    NSString *rootStd = root.stringByStandardizingPath;
    if (![full isEqualToString:rootStd] &&
        ![full hasPrefix:[rootStd stringByAppendingString:@"/"]]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Path" code:403
                                            userInfo:@{ NSLocalizedDescriptionKey: @"policy rejected: path outside root" }];
        return nil;
    }
    return full;
}

+ (BOOL)ensureDirectory:(NSString *)path mode:(mode_t)mode error:(NSError **)error
{
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) return YES;
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[NSFilePosixPermissions] = @(mode);
    return [NSFileManager.defaultManager createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:attrs
                                                        error:error];
}

+ (BOOL)writeFileAtomically:(NSString *)path contents:(NSData *)data mode:(mode_t)mode error:(NSError **)error
{
    NSString *dir = path.stringByDeletingLastPathComponent;
    if (![self ensureDirectory:dir mode:0700 error:error]) return NO;
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    chmod(path.fileSystemRepresentation, mode);
    return YES;
}

@end
