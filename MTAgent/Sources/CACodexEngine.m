//
//  CACodexEngine.m
//  对齐原包：codex 可执行查找顺序、-c 覆盖集、CODEX_HOME/CODEX_CUSTOM_API_KEY/PATH 环境、
//           app-server --stdio 常驻会话 + exec --json 回退、login 四种方式（8s 状态超时）、
//           provider 密钥写入 CAProviderConfiguration（文件）+ 注入 env、模型目录 json 落盘
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CACodexEngine.h"
#import "CAProviderConfiguration.h"
#import "CAExecutionEnvironment.h"
#import "CALogger.h"

static const NSTimeInterval kLoginStatusTimeout = 8.0;

@implementation CACodexEngine

+ (instancetype)sharedEngine
{
    static CACodexEngine *engine; static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [CACodexEngine new]; });
    return engine;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _retiringAppServers = [NSMutableSet set];
        _useThirdPartyProvider = [NSUserDefaults.standardUserDefaults boolForKey:CADefaultsUseThirdPartyProvider];
        _thirdPartyProviderName = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsThirdPartyProviderName];
        _persistsProviderPreferences = YES;
        _sandboxMode = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsSandboxMode] ?: @"workspace-write";
    }
    return self;
}

#pragma mark - 可执行查找（原包候选：runtime 安装、/var/jb/usr/bin/codex、/usr/libexec/codex/codex、/usr/bin/codex）

- (NSString *)resolveCodexExecutable
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *installed = [[CARuntimePaths runtimeRootForID:@"codex"] stringByAppendingPathComponent:@"bin/codex"];
    [candidates addObject:installed];
    [candidates addObject:@"/var/jb/usr/bin/codex"];
    [candidates addObject:@"/var/jb/usr/local/bin/codex"];
    [candidates addObject:@"/usr/libexec/codex/codex"];
    [candidates addObject:@"/usr/bin/codex"];
    [candidates addObject:@"/usr/local/bin/codex"];
    for (NSString *c in candidates) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:c]) return c;
    }
    CALog(CALogLevelError, @"RUNTIME", @"login status failed: missing codex binary");
    return nil;
}

- (NSString *)codexLogDirectory
{
    NSString *dir = [CARuntimePaths.documentsCodexDirectory stringByAppendingPathComponent:@"log"];
    [CARuntimePaths ensureDirectory:dir mode:0700 error:NULL];
    return dir;
}

- (NSString *)thirdPartyModelCatalogPath
{
    return CARuntimePaths.thirdPartyCatalogPath;
}

#pragma mark - 环境（原包：CODEX_HOME / CODEX_CUSTOM_API_KEY / PATH / SSL_CERT_FILE）

- (NSDictionary<NSString *, NSString *> *)environmentForCodexInvocation
{
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[CAEnvCodexHome] = CARuntimePaths.codexHome;
    env[CAEnvHelpers]   = CARuntimePaths.helpersDirectory;
    env[CAEnvTheosHelper] = CARuntimePaths.theosHelperPath;
    env[CAEnvTheosBash] = CARuntimePaths.bashPath;
    env[CAEnvTheosRuntime] = CARuntimePaths.runtimeDownloadsDirectory;
    env[CAEnvTheosSDKRoot] = [CARuntimePaths.runtimeRootForID:@"theos"];

    NSString *path = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
    env[@"PATH"] = path;
    env[CAEnvTheosPath] = path;

    // CA 束：仅在用户未显式覆盖时注入（原包 CA_NOTICE.txt 的约定）
    if (!env[CAEnvCACertificate] && !env[CAEnvSSLCertFile]) {
        env[CAEnvSSLCertFile] = CARuntimePaths.bundledCACertPath;
    }
    env[@"GIT_SSL_CAINFO"] = env[CAEnvCACertificate] ?: env[CAEnvSSLCertFile];
    env[@"GIT_TERMINAL_PROMPT"] = @"0";

    if (self.useThirdPartyProvider) {
        NSString *key = [self thirdPartyAPIKeyForInternalUse];
        if (key.length) env[CAEnvCustomAPIKey] = key;
    }
    [env addEntriesFromDictionary:[CAExecutionEnvironment.sharedEnvironment environmentVariablesForRuntime]];
    env[CAEnvWorkspaceHost] = @"local-ios";
    return env;
}

#pragma mark - -c 覆盖集（原包逐条）

- (NSArray<NSString *> *)configOverridesWithBaseURL:(NSString *)baseURL
                                              model:(NSString *)model
                                        catalogPath:(NSString *)catalogPath
                                      contextWindow:(NSUInteger)contextWindow
                                             logDir:(NSString *)logDir
                              developerInstructions:(NSString *)instructions
{
    NSMutableArray<NSString *> *overrides = [NSMutableArray array];
    void (^add)(NSString *) = ^(NSString *kv) { [overrides addObject:@"-c"]; [overrides addObject:kv]; };

    add([NSString stringWithFormat:CACodexConfigLogDir, logDir ?: [self codexLogDirectory]]);

    if ([self hasThirdPartyAPIKey] && baseURL.length) {
        add(CACodexConfigModelProvider);
        add([NSString stringWithFormat:CACodexConfigProviderLine, self.thirdPartyProviderName ?: @"custom", baseURL]);
        add(CACodexConfigCodeMode);
        add(CACodexConfigWebSearchFeat);
        add(CACodexConfigWebSearchLive);
    }
    if (model.length) add([NSString stringWithFormat:@"model=\"%@\"", model]);
    if (catalogPath.length) add([NSString stringWithFormat:CACodexConfigModelCatalog, catalogPath]);
    if (contextWindow > 0) add([NSString stringWithFormat:CACodexConfigContextWindow, (unsigned long)contextWindow]);
    if (instructions.length) add([NSString stringWithFormat:CACodexConfigInstructions, instructions]);
    add(CACodexConfigNoLoginShell);
    return overrides;
}

#pragma mark - provider 密钥（写入文件，与原包一致）

- (BOOL)saveThirdPartyAPIKey:(NSString *)key error:(NSError **)error
{
    NSString *trimmed = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed isEqualToString:self.apiKey ?: @""]) return YES;
    self.apiKey = trimmed;
    BOOL ok = [CAProviderConfiguration.sharedConfiguration saveAPIKey:trimmed error:error];
    if (ok) {
        CALog(CALogLevelInfo, @"GENERAL", @"third-party API key changed");
        [NSUserDefaults.standardUserDefaults setBool:self.useThirdPartyProvider forKey:CADefaultsUseThirdPartyProvider];
        [NSUserDefaults.standardUserDefaults setObject:self.thirdPartyProviderName ?: @"" forKey:CADefaultsThirdPartyProviderName];
    }
    return ok;
}

- (BOOL)hasThirdPartyAPIKey
{
    NSString *key = [CAProviderConfiguration.sharedConfiguration readAPIKeyWithError:NULL];
    return key.length > 0;
}

- (NSString *)thirdPartyAPIKeyForInternalUse
{
    return [CAProviderConfiguration.sharedConfiguration readAPIKeyWithError:NULL] ?: @"";
}

#pragma mark - 模型目录

- (BOOL)writeCatalogForModels:(NSArray<NSDictionary *> *)models
                selectedModel:(NSString *)slug
                contextWindow:(NSUInteger)contextWindow
                        error:(NSError **)error
{
    NSDictionary *catalog = @{ @"models": models ?: @[], @"selected": slug ?: @"", @"context_window": @(contextWindow) };
    NSData *data = [NSJSONSerialization dataWithJSONObject:catalog options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return [CARuntimePaths writeFileAtomically:self.thirdPartyModelCatalogPath contents:data mode:0644 error:error];
}

#pragma mark - app-server 会话

- (void)preparePersistentAppServerWithCompletion:(void (^)(BOOL, NSError *))completion preserveCatalogSession:(BOOL)preserve
{
    NSString *exe = [self resolveCodexExecutable];
    if (!exe) {
        NSError *error = [NSError errorWithDomain:@"CodexApp.Codex" code:404 userInfo:@{ NSLocalizedDescriptionKey: @"missing codex binary" }];
        if (completion) completion(NO, error);
        return;
    }
    if (_persistentAppServer.isRunning) {
        if (completion) completion(YES, nil);
        return;
    }

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObject:CACodexSubcommandAppServer];
    [args addObject:CACodexFlagStdio];
    [args addObjectsFromArray:[self configOverridesWithBaseURL:[NSUserDefaults.standardUserDefaults stringForKey:CADefaultsAPIBaseURL]
                                                        model:[NSUserDefaults.standardUserDefaults stringForKey:CADefaultsSelectedModel]
                                                  catalogPath:nil
                                                contextWindow:0
                                                       logDir:[self codexLogDirectory]
                                        developerInstructions:nil]];

    CAAppServerSession *session = [[CAAppServerSession alloc] initWithExecutable:exe
                                                                       arguments:args
                                                                     environment:[self environmentForCodexInvocation]
                                                               workingDirectory:CARuntimePaths.codexHome];
    session.delegate = self;
    _persistentAppServer = session;
    CALog(CALogLevelInfo, @"APP-SERVER", @"command backend runtime=native app-server executable=%@", exe);
    [session startWithCompletion:^(BOOL ok, NSError *error) {
        if (!ok && completion) completion(NO, error);
        else if (completion) completion(YES, nil);
    }];
}

- (void)invalidatePersistentServerWithReason:(NSString *)reason
{
    if (!_persistentAppServer) return;
    CALog(CALogLevelInfo, @"APP-SERVER", @"invalidating persistent session reason=%@", reason);
    [_retiringAppServers addObject:_persistentAppServer];
    [_persistentAppServer stop];
    _persistentAppServer = nil;
}

- (void)ensureMCPCatalogThreadWithCompletion:(void (^)(BOOL, NSError *))completion
{
    if (self.mcpCatalogThreadId.length) {
        if (completion) completion(YES, nil);
        return;
    }
    [self preparePersistentAppServerWithCompletion:^(BOOL ok, NSError *error) {
        if (!ok) { if (completion) completion(NO, error); return; }
        [self.persistentAppServer callMethod:CARPCMethodThreadResume
                                  parameters:@{ @"thread_id": @"mcp-catalog", @"collaboration_mode": @{ @"sandbox_policy": self.sandboxMode ?: @"workspace-write" } }
                                  completion:^(id result, NSError *rpcError) {
            if (rpcError) { if (completion) completion(NO, rpcError); return; }
            self.mcpCatalogThreadId = result[@"thread_id"] ?: result[@"threadId"];
            if (completion) completion(self.mcpCatalogThreadId.length > 0, nil);
        }];
    } preserveCatalogSession:YES];
}

- (void)reloadMCPConfigurationWithCompletion:(void (^)(BOOL))completion
{
    [self invalidatePersistentServerWithReason:@"configuration changed"];
    [self preparePersistentAppServerWithCompletion:^(BOOL ok, NSError *error) {
        if (completion) completion(ok);
    } preserveCatalogSession:NO];
}

- (void)readConnectedMCPServerStatusesForNames:(NSArray<NSString *> *)names
                                    completion:(void (^)(NSDictionary<NSString *, NSNumber *> *))completion
{
    [self.persistentAppServer callMethod:@"mcp/servers/status" parameters:@{ @"names": names ?: @[] }
                              completion:^(id result, NSError *error) {
        if (completion) completion([result isKindOfClass:NSDictionary.class] ? result : @{});
    }];
}

#pragma mark - 执行

- (void)startExecWithPrompt:(NSString *)prompt
                  workspace:(NSString *)workspace
                      model:(NSString *)model
             executionMode:(NSString *)executionMode
                   sandbox:(NSString *)sandbox
                     output:(CACodexTurnOutputHandler)output
                 completion:(CACodexTurnCompletion)completion
{
    NSString *exe = [self resolveCodexExecutable];
    if (!exe) {
        if (completion) completion(127, @"runtime unavailable");
        return;
    }
    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithObject:CACodexSubcommandExec];
    [args addObject:CACodexFlagJSON];
    [args addObject:CACodexFlagSkipGitRepo];
    [args addObject:CACodexFlagDangerous];   // 原包观测：exec 路径带该标志
    [args addObjectsFromArray:[self configOverridesWithBaseURL:[NSUserDefaults.standardUserDefaults stringForKey:CADefaultsAPIBaseURL]
                                                        model:model
                                                  catalogPath:self.thirdPartyModelCatalogPath
                                                contextWindow:0
                                                       logDir:[self codexLogDirectory]
                                        developerInstructions:nil]];
    [args addObject:prompt];

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:exe];
    task.arguments = args;
    task.currentDirectoryURL = [NSURL fileURLWithPath:workspace.length ? workspace : CARuntimePaths.documentsDirectory];
    NSMutableDictionary *env = [[self environmentForCodexInvocation] mutableCopy];
    env[CAEnvWorkspacePath] = workspace ?: CARuntimePaths.documentsDirectory;
    task.environment = env;

    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;
    outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        for (NSString *line in [s componentsSeparatedByString:@"\n"]) if (line.length) output(line, NO);
    };
    errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        for (NSString *line in [s componentsSeparatedByString:@"\n"]) if (line.length) output(line, YES);
    };

    task.terminationHandler = ^(NSTask *t) {
        outPipe.fileHandleForReading.readabilityHandler = nil;
        errPipe.fileHandleForReading.readabilityHandler = nil;
        CALog(CALogLevelInfo, @"CHAT-TERMINAL", @"exec exited status=%d execution=%@", t.terminationStatus, executionMode ?: @"agent");
        if (completion) completion(t.terminationStatus, nil);
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        CALog(CALogLevelError, @"CHAT-TERMINAL", @"exec launch failed error=%@", error.localizedDescription);
        if (completion) completion(-1, error.localizedDescription);
        return;
    }
    CALog(CALogLevelInfo, @"CHAT-TERMINAL", @"exec launched pid=%d resume=%@ model=%@", task.processIdentifier, @"NO", model ?: @"default");
}

- (void)sendPromptViaPersistentAppServer:(NSString *)prompt threadId:(NSString *)threadId completion:(CACodexTurnCompletion)completion
{
    [self.persistentAppServer callMethod:CARPCMethodTurnStart
                              parameters:@{ @"thread_id": threadId ?: self.mcpCatalogThreadId ?: @"",
                                            @"input": @[ @{ @"type": @"text", @"text": prompt } ],
                                            @"collaboration_mode": @{ @"sandbox_policy": self.sandboxMode ?: @"workspace-write" } }
                              completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(-1, error.localizedDescription); return; }
        if (completion) completion(0, nil);
    }];
}

#pragma mark - 登录（原包四种方式 + 8s 状态超时）

- (void)checkLoginStatusWithCompletion:(void (^)(BOOL, NSString *))completion
{
    NSString *exe = [self resolveCodexExecutable];
    if (!exe) {
        self.isLoggedIn = NO;
        self.loginStatusText = @"missing codex binary";
        if (completion) completion(NO, self.loginStatusText);
        return;
    }
    CALog(CALogLevelInfo, @"ACCOUNT", @"starting login status query");
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:exe];
    task.arguments = @[ CACodexSubcommandLogin, @"status" ];
    task.environment = [self environmentForCodexInvocation];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe; task.standardError = pipe;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.loginStatusText = @"login status runtime launch failed";
        if (completion) completion(NO, self.loginStatusText);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLoginStatusTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (task.isRunning) {
            [task terminate];
            self.loginStatusText = @"timed out";
            CALog(CALogLevelWarn, @"ACCOUNT", @"login status timed out after 8s pid=%d", task.processIdentifier);
            if (completion) completion(NO, self.loginStatusText);
        }
    });
    [task waitUntilExit];
    NSString *output = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
    BOOL loggedIn = [output.lowercaseString containsString:@"logged in"] && ![output.lowercaseString containsString:@"not logged in"];
    self.isLoggedIn = loggedIn;
    self.loginStatusText = output;
    CALog(CALogLevelInfo, @"ACCOUNT", @"login status CLI exited status=%d loggedIn=%@ output=%@", task.terminationStatus, loggedIn ? @"YES" : @"NO", output);
    if (completion) completion(loggedIn, output);
}

- (void)loginWithAPIKey:(NSString *)apiKey completion:(void (^)(BOOL, NSString *))completion
{
    [self runLoginArguments:@[ CACodexSubcommandLogin, CACodexFlagWithAPIKey, apiKey ?: @"" ]
                      label:@"API Key"
              codeHandler:nil
                 completion:completion];
}

- (void)loginWithAccessToken:(NSString *)token completion:(void (^)(BOOL, NSString *))completion
{
    [self runLoginArguments:@[ CACodexSubcommandLogin, CACodexFlagWithAccessToken, token ?: @"" ]
                      label:@"Access Token"
              codeHandler:nil
                 completion:completion];
}

- (void)startDeviceLoginWithCodeHandler:(void (^)(NSString *))codeHandler completion:(void (^)(BOOL, NSString *))completion
{
    [self runLoginArguments:@[ CACodexSubcommandLogin, CACodexFlagDeviceAuth ]
                      label:@"device"
              codeHandler:codeHandler
                 completion:completion];
}

- (void)startBrowserOAuthLoginWithUrlHandler:(void (^)(NSURL *))urlHandler completion:(void (^)(BOOL, NSString *))completion
{
    // 原包正则：(?i)https://auth\.openai\.com/oauth/authorize[^\s\r\n]+
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"https://auth\\.openai\\.com/oauth/authorize[^\\s\\r\\n]+" options:NSRegularExpressionCaseInsensitive error:NULL];
    [self runLoginArguments:@[ CACodexSubcommandLogin ]
                      label:@"browser OAuth"
              codeHandler:^(NSString *line) {
        NSTextCheckingResult *m = [re firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (m && urlHandler) urlHandler([NSURL URLWithString:[line substringWithRange:m.range]]);
    } completion:completion];
}

- (void)runLoginArguments:(NSArray<NSString *> *)arguments
                    label:(NSString *)label
              codeHandler:(void (^)(NSString *line))codeHandler
               completion:(void (^)(BOOL, NSString *))completion
{
    NSString *exe = [self resolveCodexExecutable];
    if (!exe) {
        if (completion) completion(NO, @"missing codex binary");
        return;
    }
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:exe];
    task.arguments = arguments;
    task.environment = [self environmentForCodexInvocation];
    NSPipe *outPipe = [NSPipe pipe], *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe; task.standardError = errPipe;
    __block NSMutableString *buffer = [NSMutableString string];
    void (^consume)(NSFileHandle *) = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        [buffer appendString:s];
        if (codeHandler) {
            for (NSString *line in [s componentsSeparatedByString:@"\n"]) if (line.length) codeHandler(line);
        }
    };
    outPipe.fileHandleForReading.readabilityHandler = consume;
    errPipe.fileHandleForReading.readabilityHandler = consume;
    self.loginTask = task;
    CALog(CALogLevelInfo, @"ACCOUNT", @"%@ login starting", label);
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        if (completion) completion(NO, error.localizedDescription);
        return;
    }
    [task waitUntilExit];
    self.loginTask = nil;
    BOOL ok = (task.terminationStatus == 0);
    CALog(CALogLevelInfo, @"ACCOUNT", @"%@ login exited status=%d pid=%d", label, task.terminationStatus, task.processIdentifier);
    if (completion) completion(ok, buffer);
}

- (void)logoutWithCompletion:(void (^)(BOOL))completion
{
    NSString *exe = [self resolveCodexExecutable];
    if (!exe) { if (completion) completion(NO); return; }
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:exe];
    task.arguments = @[ CACodexSubcommandLogin, @"--logout" ];
    task.environment = [self environmentForCodexInvocation];
    NSError *error = nil;
    BOOL ok = [task launchAndReturnError:&error];
    if (ok) [task waitUntilExit];
    self.isLoggedIn = NO;
    if (completion) completion(ok && task.terminationStatus == 0);
}

#pragma mark - CAAppServerSessionDelegate

- (void)appServerSession:(CAAppServerSession *)session didInvalidateWithReason:(NSString *)reason
{
    CALog(CALogLevelWarn, @"APP-SERVER", @"app-server.invalidated reason=%@", reason);
}

- (void)appServerSession:(CAAppServerSession *)session didRequestUserInput:(NSDictionary *)request
{
    CALog(CALogLevelInfo, @"APP-SERVER", @"plan user-input requested id=%@ questions=%lu",
          request[@"id"] ?: @"?", (unsigned long)[request[@"questions"] count]);
}

@end
