//
//  CATheosEnvironment.m — CATheosEnvironment 完整实现
//  从 CARuntimeEnvironments.m 拆出（唯一 @implementation，避免 duplicate symbol）。
//  对齐原包 152 选择器：路径族 / prepare / validate / rollback / 嵌入式 adapter 补丁 /
//  root 文件操作 / root 进程执行 / SHA256 / SDK 版本比较 / 身份指纹
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CARuntimeEnvironments.h"
#import "CARuntimeCatalog.h"
#import "CAArchiveExtractor.h"
#import "CAProcess.h"
#import "CALogger.h"
#import "CAStorageManager.h"
#import "CAUpdateManager.h"

#import <CommonCrypto/CommonDigest.h>

// 跨 TU 共享辅助（定义在 CARuntimeEnvironments.m）
extern NSString *CAParityTrimString(NSString *text);
extern NSString *CAParityHexDigestForData(NSData *data);
extern NSError *CAParityTheosErrorMake(NSInteger code, NSString *message);
extern BOOL CAParityPathReadable(NSString *path);
extern BOOL CAParityPathIsExecutable(NSString *path);

#pragma mark - Theos 专属静态辅助（真逻辑，强类型）

/// 嵌入式 adapter 幂等锚点
static NSString * const CAParityTheosAdapterMarker = @"// ==CA-THEOS-ADAPTER==";

/// Theos 必需可执行文件相对路径（validate 用）
static NSArray<NSString *> *CAParityTheosRequiredExecutables(void)
{
    static NSArray<NSString *> *paths;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = @[ @"bin/make", @"bin/perl", @"bin/dpkg-deb" ];
    });
    return paths;
}

static NSString *CAParityTheosRevisionMarkerPath(CATheosEnvironment *self)
{
    return [[self theosRoot] stringByAppendingPathComponent:@".ca-theos-revision"];
}

static NSString *CAParityTheosReadRevision(CATheosEnvironment *self)
{
    return CAParityTrimString([NSString stringWithContentsOfFile:CAParityTheosRevisionMarkerPath(self)
                                                        encoding:NSUTF8StringEncoding error:NULL]);
}

static NSString *CAParityTheosPreparedRoot(CATheosEnvironment *self)
{
    if (!CAParityPathReadable(CAParityTheosRevisionMarkerPath(self))) return nil;
    return [self theosRoot];
}

static NSString *CAParityTheosPrivateRoot(void)
{
    return [CARuntimePaths.supportDirectory stringByAppendingPathComponent:@"CodexApp/theos-private"];
}

static NSString *CAParityTheosWorkspaceRoot(void)
{
    return [CARuntimePaths.tmpDirectory stringByAppendingPathComponent:@"TheosPrepare"];
}

static NSString *CAParityTheosCacheRoot(void)
{
    return [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"theos-cache"];
}

static BOOL CAParityTheosValidate(CATheosEnvironment *self, NSString *root, NSError **error)
{
    if (!root.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"runtime root is empty");
        return NO;
    }
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) {
        if (error) *error = CAParityTheosErrorMake(404, [NSString stringWithFormat:@"runtime root missing: %@", root]);
        return NO;
    }
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *relative in CAParityTheosRequiredExecutables()) {
        if (!CAParityPathIsExecutable([root stringByAppendingPathComponent:relative])) [missing addObject:relative];
    }
    if (!CAParityPathReadable([root stringByAppendingPathComponent:@"toolchain"])) [missing addObject:@"toolchain"];
    if (!CAParityPathReadable([root stringByAppendingPathComponent:@"sdks"])) [missing addObject:@"sdks"];
    if (missing.count) {
        if (error) *error = CAParityTheosErrorMake(422, [NSString stringWithFormat:@"runtime incomplete, missing: %@",
                                                        [missing componentsJoinedByString:@", "]]);
        return NO;
    }
    return YES;
}

static BOOL CAParityTheosPatchFile(NSString *path, NSDictionary<NSString *, NSString *> *replacements, NSError **error)
{
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!text.length) {
        if (error) *error = CAParityTheosErrorMake(404, [NSString stringWithFormat:@"cannot read %@", path]);
        return NO;
    }
    NSString *patched = text;
    for (NSString *needle in replacements) {
        NSString *replacement = replacements[needle];
        if (needle.length && [patched containsString:needle]) {
            patched = [patched stringByReplacingOccurrencesOfString:needle withString:replacement ?: @""];
        }
    }
    if ([patched isEqualToString:text]) return YES; // 幂等：无变化不写
    NSError *writeError = nil;
    if (![patched writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        if (error) *error = writeError ?: CAParityTheosErrorMake(500, @"patch write failed");
        return NO;
    }
    return YES;
}

static BOOL CAParityTheosAppendBlock(NSString *path, NSString *marker, NSString *block, NSError **error)
{
    NSString *anchor = marker.length ? marker : CAParityTheosAdapterMarker;
    NSString *existing = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    if ([existing containsString:anchor]) return YES; // 幂等
    NSString *combined = existing.length
        ? [NSString stringWithFormat:@"%@\n%@\n%@\n", existing, anchor, block ?: @""]
        : [NSString stringWithFormat:@"%@\n%@\n", anchor, block ?: @""];
    NSError *writeError = nil;
    if (![combined writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        if (error) *error = writeError ?: CAParityTheosErrorMake(500, @"append write failed");
        return NO;
    }
    return YES;
}

static BOOL CAParityTheosApplyMakefileCompat(CATheosEnvironment *self, NSString *root, NSError **error)
{
    NSString *makefilesDirectory = [root stringByAppendingPathComponent:@"makefiles"];
    [NSFileManager.defaultManager createDirectoryAtPath:makefilesDirectory
                            withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *common = [makefilesDirectory stringByAppendingPathComponent:@"common.mk"];
    NSString *block = [NSString stringWithFormat:
        @"CA_THEOS_EMBEDDED := 1\n"
        @"export CA_THEOS_RUNTIME ?= %@\n"
        @"export PATH := $(CA_THEOS_RUNTIME)/bin:$(PATH)\n",
        [self theosRoot]];
    return CAParityTheosAppendBlock(common, CAParityTheosAdapterMarker, block, error);
}

static BOOL CAParityTheosWriteText(NSString *text, NSString *path, NSError **error)
{
    if (!path.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"write path is empty");
        return NO;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *writeError = nil;
    BOOL ok = [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!ok && error) *error = writeError ?: CAParityTheosErrorMake(500, @"writeText failed");
    return ok;
}

static BOOL CAParityTheosMovePath(NSString *source, NSString *destination, NSError **error)
{
    if (!source.length || !destination.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"move path is empty");
        return NO;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:destination error:NULL];
    NSError *moveError = nil;
    BOOL ok = [NSFileManager.defaultManager moveItemAtPath:source toPath:destination error:&moveError];
    if (!ok && error) *error = moveError ?: CAParityTheosErrorMake(500, @"movePath failed");
    return ok;
}

static BOOL CAParityTheosClonePath(NSString *source, NSString *destination, NSError **error)
{
    if (!source.length || !destination.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"clone path is empty");
        return NO;
    }
    NSError *copyError = nil;
    BOOL ok = [NSFileManager.defaultManager copyItemAtPath:source toPath:destination error:&copyError];
    if (!ok && error) *error = copyError ?: CAParityTheosErrorMake(500, @"clonePath failed");
    return ok;
}

static BOOL CAParityTheosResign(CATheosEnvironment *self, NSString *root, NSError **error)
{
    NSString *signer = CARuntimePaths.codexSignPath;
    if (!CAParityPathIsExecutable(signer)) {
        if (error) *error = CAParityTheosErrorMake(404, @"codex-sign is not executable");
        return NO;
    }
    NSArray<NSString *> *executables = [self installedExecutableMachOPathsAtRoot:root ?: [self theosRoot]];
    if (!executables.count) {
        CALog(CALogLevelWarn, @"THEOS", @"no executables to resign at %@", root ?: @"");
        return YES;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:signer];
    task.arguments = [@[ @"--adhoc-only" ] arrayByAddingObjectsFromArray:executables];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PATH"] = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    environment[CAEnvHelpers] = CARuntimePaths.helpersDirectory;
    environment[CAEnvTheosHelper] = CARuntimePaths.theosHelperPath;
    task.environment = environment;
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError ?: CAParityTheosErrorMake(500, @"codex-sign launch failed");
        return NO;
    }
    [task waitUntilExit];
    BOOL ok = (task.terminationStatus == 0);
    CALog(ok ? CALogLevelInfo : CALogLevelError, @"THEOS", @"resign %lu executables status=%d",
          (unsigned long)executables.count, task.terminationStatus);
    if (!ok && error) *error = CAParityTheosErrorMake(task.terminationStatus ?: 500, @"runtime resign failed");
    return ok;
}

static BOOL CAParityTheosRunRoot(CATheosEnvironment *self, NSString *executable, NSArray<NSString *> *arguments,
                                 NSString *currentDirectory, NSDictionary<NSString *, NSString *> *environment,
                                 NSTimeInterval timeout, NSString **output, NSError **error)
{
    if (!executable.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"executable path is empty");
        return NO;
    }
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments ?: @[];
    if (currentDirectory.length) task.currentDirectoryURL = [NSURL fileURLWithPath:currentDirectory];

    NSString *root = [self theosRoot];
    NSMutableDictionary<NSString *, NSString *> *merged = [NSProcessInfo.processInfo.environment mutableCopy];
    NSMutableArray<NSString *> *pathComponents = [NSMutableArray arrayWithObjects:
        [root stringByAppendingPathComponent:@"bin"],
        [root stringByAppendingPathComponent:@"usr/bin"],
        CARuntimePaths.helpersDirectory, nil];
    for (NSString *component in [(environment[@"PATH"] ?: @"") componentsSeparatedByString:@":"]) {
        if (component.length) [pathComponents addObject:component];
    }
    merged[@"PATH"] = [pathComponents componentsJoinedByString:@":"];
    merged[CAEnvTheosRuntime] = root;
    merged[CAEnvTheosSDKRoot] = [self theosSDKPath];
    merged[CAEnvTheosHelper] = CARuntimePaths.theosHelperPath;
    merged[CAEnvTheosMake] = [self theosMakePath];
    merged[CAEnvTheosEmbedded] = @"1";
    merged[CAEnvTheosPackageMode] = @"native";
    merged[@"THEOS"] = root;
    merged[@"THEOS_SDK_ROOT"] = [self theosSDKPath];
    for (NSString *key in environment) merged[key] = environment[key];
    task.environment = merged;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error) *error = launchError ?: CAParityTheosErrorMake(500, @"launch failed");
        return NO;
    }
    int status = [task waitUntilExitWithTimeout:timeout > 0 ? timeout : 300.0];
    NSString *text = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
    if (output) *output = text;
    BOOL ok = (status == 0);
    if (!ok && error) {
        *error = CAParityTheosErrorMake(status ?: 500,
            [NSString stringWithFormat:@"exit %d: %@", status, [text substringToIndex:MIN(text.length, (NSUInteger)400)]]);
    }
    return ok;
}

static BOOL CAParityTheosFinishPreparation(CATheosEnvironment *self, NSString *revision, NSError *error)
{
    if (!error) {
        NSString *marker = [NSString stringWithFormat:@"%@\n", revision ?: @"unknown"];
        [marker writeToFile:CAParityTheosRevisionMarkerPath(self) atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [NSUserDefaults.standardUserDefaults setObject:[self theosRoot] forKey:CATheosLastBundlePath];
    }
    self.isPreparing = NO;
    [self publishPreparationProgress:@1.0 stage:(error ? @"failed" : @"complete") error:error];
    [[NSNotificationCenter defaultCenter] postNotificationName:CATheosEnvironmentDidChangeNotification object:self];
    return error == nil;
}

#pragma mark - 类实现（基础方法沿用原 CARuntimeEnvironments.m 实现，parity 方法追加）

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

#pragma mark - Parity：路径族

- (NSString *)privateRuntimeRoot { return CAParityTheosPrivateRoot(); }
- (NSString *)preparationWorkspaceRoot { return CAParityTheosWorkspaceRoot(); }
- (NSString *)runtimeCacheRoot { return CAParityTheosCacheRoot(); }
- (NSString *)preparedRuntimeRoot { return CAParityTheosPreparedRoot(self); }
- (NSString *)preparedRuntimeRevision { return CAParityTheosReadRevision(self); }

- (BOOL)hasPreparedRuntime
{
    return [self preparedRuntimeRoot] != nil;
}

- (BOOL)preparedRuntimeMatchesRevision:(NSString *)revision
{
    NSString *current = [self preparedRuntimeRevision];
    return current.length > 0 && revision.length > 0 && [current isEqualToString:revision];
}

#pragma mark - Parity：bundle 元数据 / 安装态

- (NSString *)bundledMetadataPath
{
    return [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Helpers/theos-runtime.bundle.json"] copy];
}

- (NSDictionary *)bundleMetadata
{
    NSData *data = [NSData dataWithContentsOfFile:self.bundledMetadataPath];
    if (!data.length) return @{};
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] ?: @{};
}

- (NSString *)bundleRevision
{
    id revision = self.bundleMetadata[@"revision"] ?: self.bundleMetadata[@"version"];
    return [revision isKindOfClass:NSString.class] ? revision
         : [revision respondsToSelector:@selector(stringValue)] ? [revision stringValue] : nil;
}

- (BOOL)isBundled
{
    return CAParityPathReadable(self.bundledArchivePath);
}

- (BOOL)isInstalled
{
    return CAParityPathReadable(self.installedManifestPath) || [self hasPreparedRuntime];
}

- (unsigned long long)installedSizeBytes
{
    if (self.installedSizeCacheValid) return self.installedSizeCache;
    unsigned long long size = [[CAStorageManager sharedManager] directorySizeAtPath:[self theosRoot]];
    self.installedSizeCache = size;
    self.installedSizeCacheValid = YES;
    return size;
}

#pragma mark - Parity：校验 / 能力探测

- (BOOL)validateRuntimeAtRoot:(NSString *)root error:(NSError **)error
{
    return CAParityTheosValidate(self, root, error);
}

- (void)refreshCapabilityCacheIfNeeded
{
    if (self.installedSizeCacheValid) return; // 能力缓存随 size 缓存一起失效
    NSString *root = [self theosRoot];
    self.compilerPath = CAParityPathIsExecutable([root stringByAppendingPathComponent:@"usr/bin/clang"])
                      ? [root stringByAppendingPathComponent:@"usr/bin/clang"] : nil;
    self.makePath = CAParityPathIsExecutable([root stringByAppendingPathComponent:@"bin/make"])
                  ? [root stringByAppendingPathComponent:@"bin/make"] : nil;
    self.perlPath = CAParityPathIsExecutable([root stringByAppendingPathComponent:@"bin/perl"])
                  ? [root stringByAppendingPathComponent:@"bin/perl"] : nil;
    self.linkerPath = CAParityPathIsExecutable([root stringByAppendingPathComponent:@"usr/bin/ld"])
                    ? [root stringByAppendingPathComponent:@"usr/bin/ld"] : nil;
    self.signerPath = CARuntimePaths.codexSignPath;
    self.dpkgDebPath = CAParityPathIsExecutable([root stringByAppendingPathComponent:@"bin/dpkg-deb"])
                     ? [root stringByAppendingPathComponent:@"bin/dpkg-deb"] : nil;
    self.packageBuilderPath = CAParityPathIsExecutable([root stringByAppendingPathComponent:@"bin/dpkg-deb"])
                            ? [root stringByAppendingPathComponent:@"bin/dpkg-deb"] : nil;
    self.sdkRoot = [self theosSDKPath];
    self.installedSizeCacheValid = YES;
}

- (BOOL)hasCompiler { [self refreshCapabilityCacheIfNeeded]; return self.compilerPath.length > 0; }
- (BOOL)hasMake     { [self refreshCapabilityCacheIfNeeded]; return self.makePath.length > 0; }
- (BOOL)hasPerl     { [self refreshCapabilityCacheIfNeeded]; return self.perlPath.length > 0; }
- (BOOL)hasLinker   { [self refreshCapabilityCacheIfNeeded]; return self.linkerPath.length > 0; }
- (BOOL)hasSigner   { [self refreshCapabilityCacheIfNeeded]; return CAParityPathIsExecutable(self.signerPath); }
- (BOOL)hasPackageTools { [self refreshCapabilityCacheIfNeeded]; return self.packageBuilderPath.length > 0; }
- (BOOL)hasSDK      { [self refreshCapabilityCacheIfNeeded]; return CAParityPathReadable(self.sdkRoot); }
- (BOOL)ready
{
    return [self hasMake] && [self hasPerl] && [self hasPackageTools] && [self hasSDK];
}

#pragma mark - Parity：URL / SHA256 / SDK 版本

- (BOOL)isValidHTTPSURLString:(NSString *)urlString
{
    if (!urlString.length) return NO;
    NSURL *url = [NSURL URLWithString:urlString];
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length > 0;
}

- (NSString *)remoteManifestURL { return CARuntimeManifestURL; }

- (NSArray<NSString *> *)downloadCandidatesForURL:(NSString *)urlString
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (urlString.length) [candidates addObject:urlString];
    for (NSString *prefix in CADownloadProxyPrefixes()) {
        [candidates addObject:[prefix stringByAppendingString:urlString ?: @""]];
    }
    return candidates;
}

- (NSString *)sha256ForFileAtPath:(NSString *)path
{
    return CAParityHexDigestForData([NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL]);
}

- (NSString *)sha256ForString:(NSString *)string
{
    return CAParityHexDigestForData([string dataUsingEncoding:NSUTF8StringEncoding]);
}

- (NSNumber *)numericVersionForSDKName:(NSString *)sdkName
{
    if (!sdkName.length) return @0;
    // iPhoneOS17.5.sdk → 17.5
    NSMutableString *base = [(sdkName.lastPathComponent ?: sdkName) mutableCopy];
    NSRange osRange = [base rangeOfString:@"iPhoneOS"];
    if (osRange.location != NSNotFound) [base deleteCharactersInRange:osRange];
    [base replaceOccurrencesOfString:@".sdk" withString:@"" options:0 range:NSMakeRange(0, base.length)];
    [base replaceOccurrencesOfString:@".SDK" withString:@"" options:0 range:NSMakeRange(0, base.length)];
    return @([base doubleValue]);
}

- (NSComparisonResult)compareSDKName:(NSString *)a to:(NSString *)b
{
    double va = [[self numericVersionForSDKName:a] doubleValue];
    double vb = [[self numericVersionForSDKName:b] doubleValue];
    if (va < vb) return NSOrderedAscending;
    if (va > vb) return NSOrderedDescending;
    return NSOrderedSame;
}

#pragma mark - Parity：进度发布（头文件占位原型为 (id) 参数）

- (void)publishPreparationProgress:(id)fraction stage:(id)stage error:(id)error
{
    double value = [fraction respondsToSelector:@selector(doubleValue)] ? [fraction doubleValue] : 0.0;
    NSString *stageText = [stage isKindOfClass:NSString.class] ? stage : nil;
    NSError *errorObject = [error isKindOfClass:NSError.class] ? error : nil;
    self.preparationProgress = value;
    if (stageText.length) self.preparationStage = stageText;
    if (errorObject) self.preparationError = errorObject.localizedDescription;
    [[NSNotificationCenter defaultCenter] postNotificationName:CATheosPreparationProgress object:self
                                                      userInfo:@{ @"stage": stageText ?: @"", @"fraction": @(value),
                                                                  @"status": errorObject.localizedDescription ?: (stageText ?: @""),
                                                                  @"error": errorObject.localizedDescription ?: @"" }];
}

- (void)publishPreparationProgress:(id)fraction error:(id)error
{
    [self publishPreparationProgress:fraction stage:self.preparationStage ?: @"" error:error];
}

- (void)publishDownloadProgress:(id)fraction stage:(id)stage
{
    double value = [fraction respondsToSelector:@selector(doubleValue)] ? [fraction doubleValue] : 0.0;
    [self publishDownload:[stage isKindOfClass:NSString.class] ? stage : @"" progress:value];
}

#pragma mark - Parity：嵌入式 adapter（幂等文本补丁）

- (NSString *)embeddedAdapterMarkerAtRoot:(NSString *)root
{
    NSString *common = [root stringByAppendingPathComponent:@"makefiles/common.mk"];
    NSString *text = [NSString stringWithContentsOfFile:common encoding:NSUTF8StringEncoding error:NULL];
    return [text containsString:CAParityTheosAdapterMarker] ? CAParityTheosAdapterMarker : nil;
}

- (NSString *)embeddedAdapterRevisionAtRoot:(NSString *)root
{
    NSString *common = [root stringByAppendingPathComponent:@"makefiles/common.mk"];
    NSString *text = [NSString stringWithContentsOfFile:common encoding:NSUTF8StringEncoding error:NULL];
    if (!text.length) return nil;
    NSRange markerRange = [text rangeOfString:CAParityTheosAdapterMarker];
    if (markerRange.location == NSNotFound) return nil;
    NSRange lineEnd = [text rangeOfString:@"\n" options:0 range:NSMakeRange(markerRange.location, text.length - markerRange.location)];
    NSString *line = [text substringWithRange:NSMakeRange(markerRange.location,
                        (lineEnd.location == NSNotFound ? text.length : lineEnd.location) - markerRange.location)];
    NSRange revRange = [line rangeOfString:@"rev="];
    return revRange.location == NSNotFound ? nil : CAParityTrimString([line substringFromIndex:NSMaxRange(revRange)]);
}

- (BOOL)embeddedAdapterCurrentAtRoot:(NSString *)root
{
    NSString *applied = [self embeddedAdapterRevisionAtRoot:root];
    return applied.length > 0 && [applied isEqualToString:[self sha256ForString:self.runtimeID ?: @"theos"]];
}

- (BOOL)patchEmbeddedRuntimeFile:(NSString *)path replacements:(NSDictionary *)replacements error:(NSError **)error
{
    return CAParityTheosPatchFile(path, replacements, error);
}

- (BOOL)appendEmbeddedRuntimeBlock:(NSString *)block marker:(NSString *)marker toPath:(NSString *)path error:(NSError **)error
{
    return CAParityTheosAppendBlock(path, marker, block, error);
}

- (BOOL)applyEmbeddedMakefileCompatibilityAtRoot:(NSString *)root error:(NSError **)error
{
    return CAParityTheosApplyMakefileCompat(self, root, error);
}

#pragma mark - Parity：root 文件操作

- (BOOL)writeTextAsRoot:(NSString *)text toPath:(NSString *)path error:(NSError **)error
{
    return CAParityTheosWriteText(text, path, error);
}

- (BOOL)movePathAsRoot:(NSString *)source toPath:(NSString *)destination error:(NSError **)error
{
    return CAParityTheosMovePath(source, destination, error);
}

- (BOOL)clonePathAsRoot:(NSString *)source toPath:(NSString *)destination error:(NSError **)error
{
    return CAParityTheosClonePath(source, destination, error);
}

- (NSArray<NSString *> *)absolutePathsForRelativePaths:(NSArray<NSString *> *)relativePaths root:(NSString *)root error:(NSError **)error
{
    NSMutableArray<NSString *> *absolute = [NSMutableArray array];
    for (NSString *relative in relativePaths) {
        NSString *resolved = [CARuntimePaths safeRelativePath:relative ?: @"" inRoot:root ?: @"" error:error];
        if (!resolved.length) return @[];
        [absolute addObject:[root stringByAppendingPathComponent:resolved]];
    }
    return absolute;
}

#pragma mark - Parity：可执行文件 / 签名

- (NSArray<NSString *> *)entitlementUpgradeExecutablePathsAtRoot:(NSString *)root relativeExecutables:(NSArray<NSString *> *)relativeExecutables
{
    if (relativeExecutables.count) return [self absolutePathsForRelativePaths:relativeExecutables root:root error:NULL];
    return [self installedExecutableMachOPathsAtRoot:root];
}

- (BOOL)resignInstalledRuntimeExecutablesAtRoot:(NSString *)root error:(NSError **)error
{
    return CAParityTheosResign(self, root, error);
}

#pragma mark - Parity：准备流程（内置归档优先，缺失走清单下载复用 CAUpdateViewController.installRuntimeEntry:）

- (NSString *)archivePath { return self.downloadedArchivePath; }

- (BOOL)hasAvailablePackage
{
    return [self isBundled] || [self hasDownloadedPackage] || [self hasCachedArchiveForRemoteEntry];
}

- (void)finishPreparation:(NSString *)revision error:(NSError *)error
{
    CAParityTheosFinishPreparation(self, revision, error);
}

- (void)restoreCachedRuntimeIfNeededWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion
{
    NSError *error = nil;
    if (CAParityTheosValidate(self, [self theosRoot], &error)) {
        if (![self hasPreparedRuntime]) CAParityTheosFinishPreparation(self, self.installedRevision, nil);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(YES, nil); });
        return;
    }
    CALog(CALogLevelInfo, @"THEOS", @"cached runtime invalid error=%@", error.localizedDescription ?: @"(none)");
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, error); });
}

- (void)prepareBundledRuntimeIfNeededWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion
{
    if (self.isPreparing) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(YES, nil); });
        return;
    }
    NSString *root = [self theosRoot];
    CARuntimeCatalogEntry *catalogEntry = [[CARuntimeCatalog sharedCatalog] entryForID:self.runtimeID];
    NSString *bundleRevision = [self bundleRevision];
    NSString *revision = bundleRevision.length ? bundleRevision : [@((long)catalogEntry.revision) stringValue];

    if (CAParityTheosValidate(self, root, NULL) && !self.forceNextPreparation) {
        // 已就绪：补齐 adapter 兼容块（幂等）后直接完成
        CAParityTheosApplyMakefileCompat(self, root, NULL);
        CAParityTheosFinishPreparation(self, revision, nil);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(YES, nil); });
        return;
    }

    self.isPreparing = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        BOOL ok = NO;
        NSString *archive = self.bundledArchivePath;

        // 1) bundle 内置归档（Helpers/theos-runtime.tar.gz）
        if (CAParityPathReadable(archive)) {
            [self publishPreparationProgress:@0.05 stage:@"extract-bundled" error:nil];
            [CARuntimePaths ensureDirectory:root mode:0755 error:&error];
            NSString *workspace = CAParityTheosWorkspaceRoot();
            [NSFileManager.defaultManager removeItemAtPath:workspace error:NULL];
            [CARuntimePaths ensureDirectory:workspace mode:0755 error:NULL];
            ok = [CAArchiveExtractor extractTarGzip:archive toDirectory:workspace expectedExpandedSize:0
                                           progress:^(double f, NSString *stage) {
                                               [self publishPreparationProgress:@(0.05 + f * 0.35)
                                                                          stage:stage ?: @"extract" error:nil];
                                           } error:&error];
            if (ok) ok = CAParityTheosMovePath(workspace, root, &error);
            if (ok) CAParityTheosApplyMakefileCompat(self, root, NULL);
            if (ok) ok = CAParityTheosValidate(self, root, &error);
        } else {
            // 2) 清单条目下载 → 复用 CAUpdateViewController 分阶段安装（公开类方法，NSInvocation 弱耦合）
            [self publishPreparationProgress:@0.02 stage:@"fetch-manifest" error:nil];
            if (!catalogEntry) {
                error = CAParityTheosErrorMake(404, @"theos entry not present in runtime manifest");
            } else {
                Class controllerClass = NSClassFromString(@"CAUpdateViewController");
                void (^progress)(id) = ^(id p) {
                    double fraction = [p respondsToSelector:@selector(valueForKey:)] ? [[p valueForKey:@"fraction"] doubleValue] : 0.0;
                    NSString *status = [p respondsToSelector:@selector(valueForKey:)] ? [p valueForKey:@"status"] : nil;
                    [self publishPreparationProgress:@(0.02 + fraction * 0.9) stage:status ?: @"download" error:nil];
                };
                SEL installer = @selector(installRuntimeEntry:progress:error:);
                NSMethodSignature *signature = [controllerClass methodSignatureForSelector:installer];
                if (signature) {
                    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                    [invocation setSelector:installer];
                    [invocation setArgument:&catalogEntry atIndex:2];
                    [invocation setArgument:&progress atIndex:3];
                    [invocation setArgument:&error atIndex:4];
                    [invocation invoke];
                    [invocation getReturnValue:&ok];
                } else {
                    error = CAParityTheosErrorMake(500, @"CAUpdateViewController unavailable");
                }
                if (ok) CAParityTheosApplyMakefileCompat(self, root, NULL);
            }
        }

        if (ok) ok = CAParityTheosValidate(self, root, &error);
        NSError *finalError = ok ? nil : (error ?: CAParityTheosErrorMake(500, @"theos preparation failed"));
        CAParityTheosFinishPreparation(self, revision, finalError);
        CALog(ok ? CALogLevelInfo : CALogLevelError, @"THEOS", @"prepare %@", ok ? @"completed" : @"failed");
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, finalError); });
    });
}

- (void)reinstallAvailableRuntimeWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion
{
    self.forceNextPreparation = YES;
    [self prepareBundledRuntimeIfNeededWithCompletion:completion];
}

- (void)removeInstalledRuntimeWithCompletion:(void (^)(BOOL ok, NSError *_Nullable error))completion
{
    NSError *error = nil;
    BOOL ok = [NSFileManager.defaultManager removeItemAtPath:[self theosRoot] error:&error];
    [NSFileManager.defaultManager removeItemAtPath:CAParityTheosRevisionMarkerPath(self) error:NULL];
    self.installedSizeCacheValid = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:CATheosEnvironmentDidChangeNotification object:self];
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, ok ? nil : error); });
}

#pragma mark - Parity：回滚

- (BOOL)rollbackRuntimeRoot:(NSString *)root backup:(NSString *)backup failed:(BOOL)failed hadOld:(BOOL)hadOld
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if (failed) {
        // 安装失败：丢弃新根，恢复备份
        if (backup.length && [fm fileExistsAtPath:backup]) {
            [fm removeItemAtPath:root error:NULL];
            return [fm moveItemAtPath:backup toPath:root error:NULL];
        }
        return hadOld ? NO : YES; // hadOld 且备份缺失 → 无法回滚
    }
    // 成功：清理备份
    if (backup.length && [fm fileExistsAtPath:backup]) [fm removeItemAtPath:backup error:NULL];
    return YES;
}

#pragma mark - Parity：清单条目校验 / 缓存

- (CARuntimeCatalogEntry *)validatedTheosEntryFromManifestData:(NSData *)data error:(NSError **)error
{
    if (!data.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"manifest data is empty");
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = CAParityTheosErrorMake(422, @"manifest is not a JSON object");
        return nil;
    }
    for (NSDictionary *raw in object[@"runtimes"] ?: @[ object ]) {
        if (![raw isKindOfClass:NSDictionary.class]) continue;
        if (![raw[@"runtime_id"] isEqualToString:self.runtimeID]) continue;
        NSError *entryError = nil;
        CARuntimeCatalogEntry *entry = [CARuntimeCatalogEntry entryWithDictionary:raw error:&entryError];
        if (!entry) {
            if (error) *error = entryError ?: CAParityTheosErrorMake(422, @"theos entry validation failed");
            return nil;
        }
        if (!entry.archiveURL.length || ![self isValidHTTPSURLString:entry.archiveURL]) {
            if (error) *error = CAParityTheosErrorMake(422, @"theos archive url must be https");
            return nil;
        }
        return entry;
    }
    if (error) *error = CAParityTheosErrorMake(404, @"theos entry missing from manifest");
    return nil;
}

- (BOOL)cachePreparedRuntimeFromRoot:(NSString *)sourceRoot revision:(NSString *)revision error:(NSError **)error
{
    [CARuntimePaths ensureDirectory:CAParityTheosCacheRoot() mode:0755 error:NULL];
    NSString *destination = [CAParityTheosCacheRoot() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"theos-%@.tar.gz", revision ?: @"unknown"]];
    [NSFileManager.defaultManager removeItemAtPath:destination error:NULL];
    BOOL ok = CAParityTheosClonePath(sourceRoot, destination, error);
    if (ok && revision.length) {
        NSString *marker = [NSString stringWithFormat:@"%@\n", revision];
        [marker writeToFile:[CAParityTheosCacheRoot() stringByAppendingPathComponent:@".ca-theos-revision"]
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    return ok;
}

- (BOOL)downloadArchiveForEntry:(CARuntimeCatalogEntry *)entry toPath:(NSString *)path error:(NSError **)error
{
    if (!entry.archiveURL.length) {
        if (error) *error = CAParityTheosErrorMake(400, @"entry has no archive_url");
        return NO;
    }
    return [self downloadURLString:entry.archiveURL toPath:path progress:nil error:error];
}

- (BOOL)downloadURL:(NSString *)urlString toPath:(NSString *)path progress:(id)progress error:(NSError **)error
{
    return [self downloadURLString:urlString toPath:path progress:nil error:error];
}

#pragma mark - Parity：root 进程执行

- (BOOL)runRootExecutable:(NSString *)executable
                arguments:(NSArray<NSString *> *)arguments
          currentDirectory:(NSString *)currentDirectory
               environment:(NSDictionary<NSString *, NSString *> *)environment
                   timeout:(NSTimeInterval)timeout
                    output:(NSString **)output
                     error:(NSError **)error
{
    return CAParityTheosRunRoot(self, executable, arguments, currentDirectory, environment, timeout, output, error);
}

#pragma mark - Parity：身份指纹

- (NSString *)moduleInputFingerprint
{
    NSString *revision = [self preparedRuntimeRevision] ?: self.installedRevision ?: @"none";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMddHHmmss";
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    return [self sha256ForString:[NSString stringWithFormat:@"%@|%@", revision, [formatter stringFromDate:NSDate.date]]];
}

- (void)refreshRuntimeIdentityIfNeeded
{
    NSString *revision = [self preparedRuntimeRevision];
    if (!revision.length) return;
    [NSUserDefaults.standardUserDefaults setObject:[self moduleInputFingerprint] forKey:CATheosLastModuleIdentity];
    [NSUserDefaults.standardUserDefaults setObject:[self theosRoot] forKey:CATheosLastBundlePath];
}

#pragma mark - Parity：通用补齐

- (void)refreshPaths
{
    self.runtimeRoot = [[CARuntimePaths runtimeRootForID:self.runtimeID] copy];
    self.installedSizeCacheValid = NO;
    self.sdkRoot = [self theosSDKPath];
}

- (NSString *)firstExecutable:(NSString *)root
{
    if (!root.length) return nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
    NSString *relative;
    while ((relative = [enumerator nextObject])) {
        NSString *full = [root stringByAppendingPathComponent:relative];
        if ([fm isExecutableFileAtPath:full]) return full;
    }
    return nil;
}

- (NSString *)statusSummary
{
    if ([self ready]) return [NSString stringWithFormat:@"theos ready revision=%@", [self preparedRuntimeRevision] ?: @"?"];
    if (self.isPreparing) return @"theos preparing";
    return @"theos not installed";
}

- (void)setRemoteRuntimeAccessAllowed:(BOOL)allowed
{
    self.remoteRuntimeAccessAllowed = allowed;
    self.desiredRemoteRuntimeAccessAllowed = allowed;
}

- (NSDictionary<NSString *, NSString *> *)installationEnvironmentForRoot:(NSString *)root
{
    NSMutableDictionary *environment = [[self installedEnvironmentValues] mutableCopy];
    if (root.length) environment[CAEnvTheosRuntime] = root;
    return environment;
}

- (NSDictionary<NSString *, NSString *> *)environmentByAugmentingEnvironment:(NSDictionary<NSString *, NSString *> *)base
{
    NSMutableDictionary *merged = [base ?: @{} mutableCopy];
    NSDictionary *values = [self installedEnvironmentValues];
    for (NSString *key in values) merged[key] = values[key];
    merged[@"PATH"] = [@[[[self theosRoot] stringByAppendingPathComponent:@"bin"], merged[@"PATH"] ?: @"/usr/bin:/bin"]
                       componentsJoinedByString:@":"];
    return merged;
}

- (BOOL)isInstalledRevisionCurrent
{
    NSString *installed = [self preparedRuntimeRevision] ?: self.installedRevision;
    if (!installed.length) return NO;
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:self.runtimeID];
    NSString *remote = [@((long)entry.revision) stringValue];
    return remote ? [installed isEqualToString:remote] : YES;
}

@end
