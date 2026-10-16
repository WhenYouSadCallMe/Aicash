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
#import "CAProcess.h"

static const NSTimeInterval kLoginStatusTimeout = 8.0;
static const NSTimeInterval kPersistentTurnTimeout = 900.0;

NSNotificationName const CACodexEngineAppServerNotification = @"CACodexEngineAppServerNotification";
NSString *const CACodexEngineNotificationMethodKey = @"method";
NSString *const CACodexEngineNotificationParamsKey = @"params";

@interface CACodexEngine () {
    CACodexTurnCompletion _pendingTurnCompletion;
    NSString *_activeTurnId;
    NSString *_activeTurnThreadId;
    NSString *_lastTurnTerminalReason;
    NSUInteger _turnGeneration;
    BOOL _turnInFlight;
    CAProcess *_activeExecTask;
}
@end

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
    env[CAEnvTheosSDKRoot] = [CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"theos"];

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

    CAProcess *task = [CAProcess new];
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

    // 按行切分：readabilityHandler 每次给到的是一段字节流，可能把一行 JSON 拦腰截断，
    // 因此这里保留残行缓冲，只把完整行交给上层（保证每一行都是合法 JSON）。
    __block NSMutableString *outBuffer = [NSMutableString string];
    __block NSMutableString *errBuffer = [NSMutableString string];
    void (^drain)(NSMutableString *, BOOL) = ^(NSMutableString *buffer, BOOL isStderr) {
        NSRange newline;
        while ((newline = [buffer rangeOfString:@"\n"]).location != NSNotFound) {
            NSString *line = [buffer substringToIndex:newline.location];
            [buffer deleteCharactersInRange:NSMakeRange(0, newline.location + 1)];
            if (line.length > 0 && output) output(line, isStderr);
        }
    };
    outPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s.length) return;
        [outBuffer appendString:s];
        drain(outBuffer, NO);
    };
    errPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s.length) return;
        [errBuffer appendString:s];
        drain(errBuffer, YES);
    };

    task.terminationHandler = ^(CAProcess *t) {
        outPipe.fileHandleForReading.readabilityHandler = nil;
        errPipe.fileHandleForReading.readabilityHandler = nil;
        // 冲刷残行：进程结束时最后一行通常没有换行符
        drain(outBuffer, NO);
        drain(errBuffer, YES);
        CALog(CALogLevelInfo, @"CHAT-TERMINAL", @"exec exited status=%d execution=%@", t.terminationStatus, executionMode ?: @"agent");
        if (completion) completion(t.terminationStatus, nil);
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        CALog(CALogLevelError, @"CHAT-TERMINAL", @"exec launch failed error=%@", error.localizedDescription);
        if (completion) completion(-1, error.localizedDescription);
        return;
    }
    _activeExecTask = task;
    CALog(CALogLevelInfo, @"CHAT-TERMINAL", @"exec launched pid=%d resume=%@ model=%@", task.processIdentifier, @"NO", model ?: @"default");
}

/// 原包同名选择器：中断 exec 路径的当前进程（app-server 路径走 -cancelCurrentTurnWithCompletion:）
- (id)cancelExecution
{
    CAProcess *task = _activeExecTask;
    if (!task || !task.isRunning) return @NO;
    CALog(CALogLevelWarn, @"CHAT-TERMINAL", @"exec interrupted pid=%d", task.processIdentifier);
    [task interrupt];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (task.isRunning) {
            CALog(CALogLevelWarn, @"CHAT-TERMINAL", @"exec did not exit after interrupt, terminating pid=%d", task.processIdentifier);
            [task terminate];
        }
    });
    return @YES;
}

- (id)currentTask
{
    return _activeExecTask;
}

- (void)sendPromptViaPersistentAppServer:(NSString *)prompt threadId:(NSString *)threadId completion:(CACodexTurnCompletion)completion
{
    __weak typeof(self) weakSelf = self;
    [self preparePersistentAppServerWithCompletion:^(BOOL ok, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!ok) {
            CALog(CALogLevelError, @"APP-SERVER", @"persistent app-server unavailable error=%@", error.localizedDescription ?: @"unknown");
            if (completion) completion(127, error.localizedDescription ?: @"app-server 不可用");
            return;
        }
        [strongSelf dispatchTurnWithPrompt:prompt threadId:threadId completion:completion];
    } preserveCatalogSession:YES];
}

- (BOOL)persistentTurnInFlight
{
    return _turnInFlight;
}

- (NSString *)lastTurnTerminalReason
{
    return _lastTurnTerminalReason;
}

- (void)dispatchTurnWithPrompt:(NSString *)prompt threadId:(NSString *)threadId completion:(CACodexTurnCompletion)completion
{
    if (_turnInFlight) {
        // 一轮还没结束：直接拒绝并发（聊天页在跑的时候按钮已切成「停止」）。
        if (completion) completion(-1, @"上一轮还没有结束");
        return;
    }

    _turnInFlight = YES;
    _turnGeneration += 1;
    NSUInteger generation = _turnGeneration;
    _lastTurnTerminalReason = nil;
    _activeTurnId = nil;
    _activeTurnThreadId = threadId;
    _pendingTurnCompletion = completion ? [completion copy] : nil;
    self.isRunning = YES;

    NSString *resolvedThread = threadId.length > 0 ? threadId : @"";
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"thread_id"] = resolvedThread;
    parameters[@"input"] = @[ @{ @"type": @"text", @"text": prompt ?: @"" } ];
    parameters[@"collaboration_mode"] = @{ @"sandbox_policy": self.sandboxMode ?: @"workspace-write" };

    CALog(CALogLevelInfo, @"APP-SERVER", @"turn/start thread=%@ chars=%lu", resolvedThread.length ? resolvedThread : @"(new)", (unsigned long)(prompt ? prompt.length : 0));

    __weak typeof(self) weakSelf = self;
    [self.persistentAppServer callMethod:CARPCMethodTurnStart
                              parameters:parameters
                              completion:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            CALog(CALogLevelError, @"APP-SERVER", @"turn/start failed error=%@", error.localizedDescription);
            [strongSelf finishTurnWithStatus:-1 reason:error.localizedDescription ?: @"turn/start 失败"];
            return;
        }
        NSDictionary *payload = [result isKindOfClass:NSDictionary.class] ? result : @{};
        NSString *turnId = [payload[@"turn_id"] ?: payload[@"turnId"] ?: payload[@"id"] isKindOfClass:NSString.class]
            ? (payload[@"turn_id"] ?: payload[@"turnId"] ?: payload[@"id"]) : nil;
        if (turnId.length > 0) strongSelf->_activeTurnId = turnId;
        NSString *threadFromResult = [payload[@"thread_id"] ?: payload[@"threadId"] isKindOfClass:NSString.class]
            ? (payload[@"thread_id"] ?: payload[@"threadId"]) : nil;
        if (threadFromResult.length > 0) {
            strongSelf->_activeTurnThreadId = threadFromResult;
            strongSelf.currentConversationId = threadFromResult;
        }
        CALog(CALogLevelInfo, @"APP-SERVER", @"turn/start accepted turn=%@ thread=%@", turnId ?: @"?", strongSelf->_activeTurnThreadId ?: @"(none)");
    }];

    // 兜底看门狗：通知通道异常时不至于永远卡在「思考中」。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPersistentTurnTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf->_turnGeneration == generation && strongSelf->_turnInFlight) {
            CALog(CALogLevelWarn, @"APP-SERVER", @"turn watchdog fired after %.0fs", kPersistentTurnTimeout);
            [strongSelf finishTurnWithStatus:-1 reason:@"回合超时（未收到结束通知）"];
        }
    });
}

- (void)finishTurnWithStatus:(NSInteger)status reason:(NSString *)reason
{
    if (!_turnInFlight && !_pendingTurnCompletion) return;
    CACodexTurnCompletion completion = _pendingTurnCompletion;
    _pendingTurnCompletion = nil;
    _turnInFlight = NO;
    _activeTurnId = nil;
    self.isRunning = NO;
    _lastTurnTerminalReason = [reason copy];
    CALog(CALogLevelInfo, @"APP-SERVER", @"turn finished status=%ld reason=%@", (long)status, reason ?: @"(completed)");
    if (completion) completion(status, reason);
}

- (void)cancelCurrentTurnWithCompletion:(void (^)(BOOL))completion
{
    if (!_turnInFlight || !self.persistentAppServer.isRunning) {
        [self finishTurnWithStatus:0 reason:@"用户中断"];
        if (completion) completion(YES);
        return;
    }
    NSDictionary *parameters = @{ @"thread_id": _activeTurnThreadId ?: @"",
                                  @"turn_id": _activeTurnId ?: @"" };
    __weak typeof(self) weakSelf = self;
    [self.persistentAppServer callMethod:@"turn/interrupt"
                              parameters:parameters
                              completion:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        BOOL ok = (error == nil);
        CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"APP-SERVER", @"turn/interrupt ok=%@ error=%@", ok ? @"YES" : @"NO", error.localizedDescription ?: @"");
        if (ok) [strongSelf finishTurnWithStatus:0 reason:@"用户中断"];
        if (completion) completion(ok);
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
    CAProcess *task = [CAProcess new];
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
    CAProcess *task = [CAProcess new];
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
    CAProcess *task = [CAProcess new];
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
    [self postAppServerNotification:@"app-server.invalidated" params:@{ @"reason": reason ?: @"" }];
    if (_turnInFlight) [self finishTurnWithStatus:-1 reason:reason ?: @"app-server 连接失效"];
}

- (void)appServerSession:(CAAppServerSession *)session didRequestUserInput:(NSDictionary *)request
{
    CALog(CALogLevelInfo, @"APP-SERVER", @"plan user-input requested id=%@ questions=%lu",
          request[@"id"] ?: @"?", (unsigned long)[request[@"questions"] count]);
    [self postAppServerNotification:CARPCItemRequestUserInput params:request ?: @{}];
}

- (void)appServerSession:(CAAppServerSession *)session didReportUsage:(NSDictionary *)usage
{
    [self postAppServerNotification:@"turn/usage" params:usage ?: @{}];
}

- (void)appServerSession:(CAAppServerSession *)session didEmitNotification:(NSString *)method params:(NSDictionary *)params
{
    NSDictionary *payload = [params isKindOfClass:NSDictionary.class] ? params : @{};

    // 记录 thread / turn 标识，供中断与下一轮复用。
    NSString *threadId = payload[@"threadId"] ?: payload[@"thread_id"];
    if ([threadId isKindOfClass:NSString.class] && threadId.length > 0) {
        _activeTurnThreadId = threadId;
        self.currentConversationId = threadId;
    }
    NSDictionary *turn = [payload[@"turn"] isKindOfClass:NSDictionary.class] ? payload[@"turn"] : nil;
    NSString *turnId = payload[@"turnId"] ?: payload[@"turn_id"] ?: turn[@"id"];
    if ([turnId isKindOfClass:NSString.class] && turnId.length > 0) _activeTurnId = turnId;

    [self postAppServerNotification:method params:payload];

    // 回合终止判定 → 结束挂起的 completion（一次且仅一次）。
    NSString *lowercased = method.lowercaseString ?: @"";
    if ([lowercased containsString:@"turn/completed"] || [lowercased containsString:@"turn/complete"]
        || [lowercased isEqualToString:@"turn.completed"]) {
        [self finishTurnWithStatus:0 reason:nil];
    } else if ([lowercased containsString:@"turn/failed"] || [lowercased containsString:@"turn/aborted"]
               || [lowercased containsString:@"turn/interrupted"] || [lowercased isEqualToString:@"turn.failed"]) {
        NSString *reason = payload[@"error"] ?: payload[@"message"] ?: (turn[@"error"] ?: @"回合失败");
        [self finishTurnWithStatus:-1 reason:[reason isKindOfClass:NSString.class] ? reason : @"回合失败"];
    } else if ([lowercased isEqualToString:@"error"] || [lowercased isEqualToString:@"app-server.error"]) {
        NSString *reason = payload[@"message"] ?: payload[@"error"];
        [self finishTurnWithStatus:-1 reason:[reason isKindOfClass:NSString.class] ? reason : @"app-server 报错"];
    }
}

- (void)postAppServerNotification:(NSString *)method params:(NSDictionary *)params
{
    if (method.length == 0) return;
    [NSNotificationCenter.defaultCenter postNotificationName:CACodexEngineAppServerNotification
                                                      object:self
                                                    userInfo:@{ CACodexEngineNotificationMethodKey: method,
                                                                CACodexEngineNotificationParamsKey: params ?: @{} }];
}

@end
