//
//  CACommon.m — 常量定义 + 多调用分发入口
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import <spawn.h>
#import <sys/wait.h>

NSString *const CAEnvCodexHome             = @"CODEX_HOME";
NSString *const CAEnvCustomAPIKey          = @"CODEX_CUSTOM_API_KEY";
NSString *const CAEnvCACertificate         = @"CODEX_CA_CERTIFICATE";
NSString *const CAEnvSSLCertFile           = @"SSL_CERT_FILE";
NSString *const CAEnvWorkspacePath         = @"CODEXAPP_WORKSPACE_PATH";
NSString *const CAEnvWorkspaceName         = @"CODEXAPP_WORKSPACE_NAME";
NSString *const CAEnvWorkspaceHost         = @"CODEXAPP_WORKSPACE_HOST";
NSString *const CAEnvManagedSkillsPath     = @"CODEXAPP_MANAGED_SKILLS_PATH";
NSString *const CAEnvSpawnExternal         = @"CODEXAPP_SPAWN_EXTERNAL";
NSString *const CAEnvUpdateTmpRoot         = @"CODEXAPP_UPDATE_TMP_ROOT";
NSString *const CAEnvHelpers               = @"CA_HELPERS";
NSString *const CAEnvTheosHelper           = @"CA_THEOS_HELPER";
NSString *const CAEnvTheosBash             = @"CA_THEOS_BASH";
NSString *const CAEnvTheosRuntime          = @"CA_THEOS_RUNTIME";
NSString *const CAEnvTheosSDKRoot          = @"CA_THEOS_SDKROOT";
NSString *const CAEnvTheosEmbedded         = @"CA_THEOS_EMBEDDED";
NSString *const CAEnvTheosPackageMode      = @"CA_THEOS_PACKAGE_MODE";
NSString *const CAEnvTheosPath             = @"CA_THEOS_PATH";
NSString *const CAEnvTheosClang            = @"CA_THEOS_CLANG";
NSString *const CAEnvTheosMake             = @"CA_THEOS_MAKE";
NSString *const CAEnvTheosPerl             = @"CA_THEOS_PERL";
NSString *const CAEnvTheosDpkgDeb          = @"CA_THEOS_DPKG_DEB";
NSString *const CAEnvTheosTar              = @"CA_THEOS_TAR";
NSString *const CAEnvTheosGzip             = @"CA_THEOS_GZIP";
NSString *const CAEnvTheosXz               = @"CA_THEOS_XZ";
NSString *const CAEnvTheosZsh              = @"CA_THEOS_ZSH";
NSString *const CAEnvTheosModuleCache      = @"CA_THEOS_MODULE_CACHE";
NSString *const CAEnvTheosTarABI           = @"CA_THEOS_TAR_ABI";
NSString *const CAEnvTheosSequenceDir      = @"CA_THEOS_SEQUENCE_DIR";
NSString *const CAEnvRuntimeEnvKind        = @"CA_RUNTIME_ENV_KIND";
NSString *const CAEnvRuntimeJailbreakBrand = @"CA_RUNTIME_JAILBREAK_BRAND";
NSString *const CAEnvRuntimeJailbreakFamily= @"CA_RUNTIME_JAILBREAK_FAMILY";
NSString *const CAEnvRuntimeRootMode       = @"CA_RUNTIME_ROOT_MODE";
NSString *const CAEnvRuntimeTrollStoreFlavor = @"CA_RUNTIME_TROLLSTORE_FLAVOR";
NSString *const CAEnvReverseToolsStaging   = @"CA_REVERSE_TOOLS_STAGING";
NSString *const CAEnvGitProbe              = @"CA_GIT_PROBE";
NSString *const CAEnvUserlandProbe         = @"CA_USERLAND_PROBE";
NSString *const CAEnvProbeFile             = @"CA_PROBE_FILE";
NSString *const CAEnvPipeRedirectDir       = @"CA_PIPE_REDIRECT_DIR";
NSString *const CAEnvRedirectProbe         = @"CA_REDIRECT_PROBE";
NSString *const CAEnvGitConfigCount        = @"GIT_CONFIG_COUNT";
NSString *const CAEnvGitTerminalPrompt     = @"GIT_TERMINAL_PROMPT";
NSString *const CAEnvGitSSLCAlinfo         = @"GIT_SSL_CAINFO";

NSArray<NSString *> *CADownloadProxyPrefixes(void)
{
    return @[ @"https://gh-proxy.org/", @"https://ghproxy.net/" ];
}

NSString *CACurrentInvocationName(void)
{
    static NSString *name;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *arg0 = NSProcessInfo.processInfo.arguments.firstObject ?: @"";
        name = arg0.lastPathComponent.length ? arg0.lastPathComponent : @"CodexApp";
    });
    return name;
}

BOOL CAIsHelperInvocation(void)
{
    static NSSet<NSString *> *helperNames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        helperNames = [NSSet setWithArray:@[
            @"bash", @"sh", @"bash-codex", @"codex-code-mode-host", @"codex-sign",
            @"ca-filetool", @"theos-helper",
            @"cat", @"ls", @"grep", @"sed", @"find", @"tar", @"cp", @"mv", @"rm", @"mkdir", @"touch",
            @"stat", @"uname", @"which", @"xxd", @"od", @"wc", @"head", @"tail", @"sort", @"uniq", @"nl",
            @"du", @"basename", @"dirname", @"readlink", @"realpath", @"chmod", @"ln", @"tee", @"sysctl", @"date"
        ]];
    });
    return [helperNames containsObject:CACurrentInvocationName()];
}

#pragma mark - helper 进程派生工具（原包观测：forkless-posix_spawn / native-fork）

int CASpawnHelper(NSString *executable, NSArray<NSString *> *arguments, NSDictionary<NSString *> *environment, NSString *workingDirectory)
{
    const char *path = executable.fileSystemRepresentation;
    NSMutableArray<NSString *> *argvList = [NSMutableArray arrayWithObject:executable];
    [argvList addObjectsFromArray:arguments ?: @[]];
    char **argv = calloc(argvList.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvList.count; i++) argv[i] = strdup(argvList[i].UTF8String);
    argv[argvList.count] = NULL;

    NSDictionary *env = environment ?: NSProcessInfo.processInfo.environment;
    __block NSMutableArray<NSString *> *envList = [NSMutableArray array];
    [env enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [envList addObject:[NSString stringWithFormat:@"%@=%@", k, v]];
    }];
    char **envp = calloc(envList.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < envList.count; i++) envp[i] = strdup(envList[i].UTF8String);
    envp[envList.count] = NULL;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
    // posix_spawn_file_actions_addchdir_np 在较新 SDK 上标注 iOS 16+：必须做可用性守卫，
    // 否则以 iOS 15 为部署目标会直接编译报错（unavailable）。
    if (workingDirectory.length && @available(iOS 16.0, *)) {
        posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.fileSystemRepresentation);
    }
#endif
    (void)workingDirectory;   // 说明：本 helper 当前无调用点；调用方请用 NSTask.currentDirectoryURL 指定工作目录

    pid_t pid = 0;
    int rc = posix_spawn(&pid, path, &actions, NULL, argv, envp);
    posix_spawn_file_actions_destroy(&actions);

    for (NSUInteger i = 0; i <= argvList.count; i++) free(argv[i]);
    for (NSUInteger i = 0; i <= envList.count; i++) free(envp[i]);
    free(argv); free(envp);
    if (rc != 0) return -rc;
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128;
}

// 由 CAFileToolMain / CAAgentRuntimeMain 提供。
// 说明：ca-filetool 目标不含 CAAgentRuntimeMain.m，故此处用弱引用，未定义时回退（避免 Undefined symbols）。
int CAFileToolMain(int argc, char **argv);
int CAAgentRuntimeMain(int argc, char **argv) __attribute__((weak));

int CARunHelperInvocation(int argc, char **argv)
{
    NSString *invocation = CACurrentInvocationName();
    CALog(CALogLevelInfo, @"SHELL", @"helper invocation name=%@ argc=%d", invocation, argc);

    if ([invocation isEqualToString:@"bash"] || [invocation isEqualToString:@"sh"]) {
        // 原包布局：Helpers/bash、Helpers/sh → ../CodexApp（本进程），本分支 exec bash.real，参数原样透传
        NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObject:CARuntimePaths.bashPath];
        for (int i = 1; i < argc; i++) [args addObject:[NSString stringWithUTF8String:argv[i]]];
        char **forwarded = calloc(args.count + 1, sizeof(char *));
        for (NSUInteger index = 0; index < args.count; index++) forwarded[index] = strdup(args[index].UTF8String);
        forwarded[args.count] = NULL;
        execv(CARuntimePaths.bashRealPath.fileSystemRepresentation, forwarded);
        perror("execv bash.real");
        return 127;
    }
    if ([invocation isEqualToString:@"bash-codex"] || [invocation isEqualToString:@"codex-code-mode-host"]) {
        if (CAAgentRuntimeMain) return CAAgentRuntimeMain(argc, argv);
        // 弱符号未链接进本目标（如 ca-filetool）：退化到 bash -lc
        NSMutableArray<NSString *> *bashArgs = [NSMutableArray arrayWithObject:@"-lc"];
        [bashArgs addObject:argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @""];
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:CARuntimePaths.bashRealPath];
        task.arguments = bashArgs;
        NSError *error = nil;
        if ([task launchAndReturnError:&error]) {
            [task waitUntilExit];
            return task.terminationStatus;
        }
        CALog(CALogLevelError, @"RUNTIME", @"agent runtime unavailable error=%@", error.localizedDescription);
        return 127;
    }
    return CAFileToolMain(argc, argv);
}
