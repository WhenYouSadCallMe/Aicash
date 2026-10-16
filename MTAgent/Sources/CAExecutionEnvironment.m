//
//  CAExecutionEnvironment.m
//  对齐原包：越狱品牌/家族、TrollStore 风格、RootHide 三条证据、launcher 探测、root 模式、
//           shell 探针（EUID/SHELL_OK/DOCS_READ/DOCS_WRITE）、spawn 模式（forkless-posix_spawn / native-fork）
//

#import <objc/message.h>
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAExecutionEnvironment.h"
#import <sys/stat.h>
#import "CAProcess.h"

@implementation CAExecutionEnvironmentProfile
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

@implementation CAExecutionEnvironment

+ (instancetype)sharedEnvironment
{
    static CAExecutionEnvironment *env; static dispatch_once_t once;
    dispatch_once(&once, ^{ env = [CAExecutionEnvironment new]; [env refresh]; });
    return env;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _shellExecutable = CARuntimePaths.bashPath;
        _shellSpawnMode = @"forkless-posix_spawn";
        _profile = [CAExecutionEnvironmentProfile new];
    }
    return self;
}

- (void)refresh
{
    NSArray<NSString *> *evidence = [self scanApplicationEvidence];
    CAExecutionEnvironmentProfile *profile = [CAExecutionEnvironmentProfile new];

    BOOL jbRuntime  = [self hasRootHideRuntimeFilesystemEvidence];
    BOOL jbIdentity = [self hasRootHideIdentityFilesystemEvidence];
    BOOL jbPreboot  = [self hasRootHidePrebootEvidence];
    BOOL rootless   = [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb"];

    profile.hasJailbreakEvidence = (jbRuntime || jbIdentity || jbPreboot || rootless);
    profile.rootMode = rootless ? CARootModeRootless : (profile.hasJailbreakEvidence ? CARootModeRootful : CARootModeUnknown);
    profile.rootModeString = (profile.rootMode == CARootModeRootless) ? @"rootless" : (profile.rootMode == CARootModeUnknown ? @"unknown" : @"rootful");
    profile.trollStoreFlavor = [self detectTrollStoreFlavorWithApplicationEvidence:evidence];
    profile.hasTrollStore = (profile.trollStoreFlavor != nil);
    profile.familyName = rootless ? @"RootHide" : (profile.hasTrollStore ? @"TrollStore" : @"Traditional");
    profile.brandName = [self resolvedBrandWithApplicationEvidence:evidence legacyName:profile.familyName];
    for (NSString *item in evidence) {
        if ([item hasPrefix:@"launcher:"]) {
            NSArray *parts = [item componentsSeparatedByString:@"|"];
            profile.launcherDisplayName = parts.count > 0 ? parts[0] : nil;
            profile.launcherBundleId    = parts.count > 1 ? parts[1] : nil;
            profile.launcherAppPath     = parts.count > 2 ? parts[2] : nil;
        }
    }
    profile.prefersNativeTheosPackaging = profile.hasTrollStore || profile.hasJailbreakEvidence;
    profile.environmentKind = profile.hasTrollStore ? @"trollstore" : (profile.hasJailbreakEvidence ? @"jailbroken" : @"standalone");
    profile.evidenceSummary = [evidence componentsJoinedByString:@","];

    self.profile = profile;
    self.runtimeEnvironmentKind = profile.environmentKind;
    self.runtimeHasJailbreakEvidence = profile.hasJailbreakEvidence;
    self.runtimeHasTrollStore = profile.hasTrollStore;
    self.runtimeJailbreakBrand = profile.brandName;
    self.runtimeJailbreakFamily = profile.familyName;
    self.runtimeJailbreakLauncher = profile.launcherDisplayName ?: @"none";
    self.runtimeJailbreakLauncherBundle = profile.launcherBundleId ?: @"none";
    self.runtimeEnvironmentEvidence = profile.evidenceSummary;
    self.runtimeRootMode = profile.rootMode;
    self.runtimeTrollStoreFlavor = profile.trollStoreFlavor ?: @"none";

    CALog(CALogLevelInfo, @"RUNTIME", @"jailbreak brand raw=%@ app=%@ bundle=%@ legacy=%@ result=%@ reason=%@ path=%@",
          profile.brandName, profile.launcherDisplayName ?: @"none", profile.launcherBundleId ?: @"none",
          profile.familyName, profile.environmentKind, profile.evidenceSummary, profile.launcherAppPath ?: @"none");
    CALog(CALogLevelInfo, @"RUNTIME", @"environment profile kind=%@ jailbreak=%d trollstore=%d flavor=%@ brand=%@ family=%@ root=%@ launcher=%@ bundle=%@ evidence=%@ theos=%@",
          profile.environmentKind, profile.hasJailbreakEvidence, profile.hasTrollStore, profile.trollStoreFlavor ?: @"none",
          profile.brandName, profile.familyName, profile.rootModeString, profile.launcherDisplayName ?: @"none",
          profile.launcherBundleId ?: @"none", profile.evidenceSummary, profile.prefersNativeTheosPackaging ? @"native" : @"bundled");
}

#pragma mark - 环境变量导出（原包 CA_RUNTIME_* 全套）

- (NSDictionary<NSString *, NSString *> *)environmentVariablesForRuntime
{
    CAExecutionEnvironmentProfile *p = self.profile;
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[CAEnvRuntimeEnvKind] = p.environmentKind ?: @"standalone";
    env[CAEnvRuntimeJailbreakBrand] = p.brandName ?: @"none";
    env[CAEnvRuntimeJailbreakFamily] = p.familyName ?: @"none";
    env[CAEnvRuntimeRootMode] = p.rootModeString ?: @"unknown";
    env[CAEnvRuntimeTrollStoreFlavor] = p.trollStoreFlavor ?: @"none";
    return env;
}

#pragma mark - 证据扫描（原包：/var/jb、roothide、ellekit、libhooker、dopamine …）

- (NSArray<NSString *> *)scanApplicationEvidence
{
    NSMutableArray<NSString *> *evidence = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *markers = @[
        @"/var/jb/usr/lib/libhooker.dylib", @"/var/jb/usr/lib/libsubstrate.dylib",
        @"/var/jb/usr/lib/libellekit.dylib", @"/var/jb/usr/lib/libjailbreak.dylib",
        @"/var/jb/basebin", @"/var/jb/usr/bin", @"/private/preboot", @"/var/containers/Bundle/Application",
    ];
    for (NSString *m in markers) {
        if ([fm fileExistsAtPath:m]) [evidence addObject:[NSString stringWithFormat:@"path:%@", m]];
    }
    // launcher 探测（原包：LSApplicationProxy.applicationProxyForIdentifier: / dataContainerURL）
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (proxyClass) {
        NSArray<NSString *> *launcherIDs = @[ @"com.opa334.TrollStore", @"com.opa334.Dopamine",
                                              @"org.coolstar.SileoStore", @"com.saurik.Cydia" ];
        for (NSString *identifier in launcherIDs) {
            @try {
                id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, NSSelectorFromString(@"applicationProxyForIdentifier:"), identifier);
                if (!proxy) continue;
                NSString *path = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleURL"));
                NSString *name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName"));
                [evidence addObject:[NSString stringWithFormat:@"launcher:%@|%@|%@", name ?: @"launcher", identifier, path ?: @""]];
            } @catch (__unused NSException *e) {}
        }
    }
    return evidence;
}

- (BOOL)hasRootHideRuntimeFilesystemEvidence
{
    return [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/usr/lib/roothidehooks.dylib"] ||
           [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/.jbroot"];
}

- (BOOL)hasRootHideIdentityFilesystemEvidence
{
    return [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/preboot"] ||
           [NSFileManager.defaultManager fileExistsAtPath:@"/var/jb/.installed_roothide"];
}

- (BOOL)hasRootHidePrebootEvidence
{
    return [NSFileManager.defaultManager fileExistsAtPath:@"/private/preboot/roothide"];
}

- (NSString *)detectTrollStoreFlavorWithApplicationEvidence:(NSArray<NSString *> *)evidence
{
    for (NSString *item in evidence) {
        if ([item containsString:@"TrollStore"]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/Preferences/com.opa334.trollstore.plist"]) return @"full";
            return @"lite";
        }
    }
    return nil;
}

- (NSString *)resolvedBrandWithApplicationEvidence:(NSArray<NSString *> *)evidence legacyName:(NSString *)legacy
{
    if ([evidence containsObject:@"path:/var/jb/usr/lib/roothidehooks.dylib"]) return @"roothide";
    if ([evidence containsObject:@"path:/var/jb/basebin"]) return @"bootstrap";
    if ([evidence containsObject:@"path:/var/jb/usr/lib/libhooker.dylib"]) return @"libhooker";
    if ([evidence containsObject:@"path:/var/jb/usr/lib/libsubstrate.dylib"]) return @"substrate";
    return legacy ?: @"unknown";
}

#pragma mark - shell 探针（原包脚本逐字对齐）

- (NSString *)shellBootstrapProbeOutput
{
    NSString *probeFile = [CARuntimePaths.tmpDirectory stringByAppendingPathComponent:@"probe.txt"];
    NSString *script = [NSString stringWithFormat:
        @"printf 'EUID=%%s\\n' \"$EUID\"; printf 'SHELL_OK=1\\n'; "
        @"[ -r /var/mobile/Documents ] && printf 'DOCS_READ=1\\n' || printf 'DOCS_READ=0\\n'; "
        @"[ -w /var/mobile/Documents ] && printf 'DOCS_WRITE=1\\n' || printf 'DOCS_WRITE=0\\n'; "
        @"printf 'probe' > \"%@\" 2>/dev/null && printf 'PROBE_OK=1\\n' || printf 'PROBE_OK=0\\n'", probeFile];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[CAEnvProbeFile] = probeFile;
    env[CAEnvUserlandProbe] = @"1";
    NSString *output = [self runShell:script environment:env];
    CALog(CALogLevelInfo, @"SHELL", @"shell bootstrap probe output=%@", [output stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
    return output;
}

- (NSString *)runShell:(NSString *)script environment:(NSDictionary<NSString *, NSString *> *)environment
{
    CAProcess *task = [CAProcess new];
    task.executableURL = [NSURL fileURLWithPath:CARuntimePaths.bashRealPath];
    task.arguments = @[ @"-lc", script ];
    NSMutableDictionary *env = [(environment ?: NSProcessInfo.processInfo.environment) mutableCopy];
    env[CAEnvHelpers] = CARuntimePaths.helpersDirectory;
    env[CAEnvTheosHelper] = CARuntimePaths.theosHelperPath;
    env[CAEnvTheosBash] = CARuntimePaths.bashPath;
    env[@"PATH"] = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    task.environment = env;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        CALog(CALogLevelError, @"SHELL", @"shell launch failed error=%@ executable=%@", error.localizedDescription, CARuntimePaths.bashRealPath);
        return @"";
    }
    [task waitUntilExit];
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

#pragma mark - 工作区键（原包 resolvedWorkspaceKeys）

- (NSDictionary<NSString *, NSNumber *> *)resolvedWorkspaceKeys
{
    return @{
        @"readable":  @([NSFileManager.defaultManager isReadableFileAtPath:@"/var/mobile/Documents"]),
        @"writable":  @([NSFileManager.defaultManager isWritableFileAtPath:@"/var/mobile/Documents"]),
    };
}

@end
