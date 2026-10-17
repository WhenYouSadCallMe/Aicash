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

// P1 补齐（原包方法对齐）：常驻 app-server 会话就绪信号
NSNotificationName const CACodexEnginePersistentSessionReadyNotification = @"CACodexEnginePersistentSessionReadyNotification";
NSNotificationName const CAModelListDidUpdateNotification = @"CAModelListDidUpdateNotification";

@interface CACodexEngine () {
    CACodexTurnCompletion _pendingTurnCompletion;
    NSString *_activeTurnId;
    NSString *_activeTurnThreadId;
    NSString *_lastTurnTerminalReason;
    NSUInteger _turnGeneration;
    BOOL _turnInFlight;
    CAProcess *_activeExecTask;
    // 任务 A：服务端用户输入请求缓存（原包行为：缓存 requestID，决策卡点完再回包）
    NSNumber *_pendingUserInputRequestID;
    NSDictionary *_pendingUserInputParams;
    // 任务 B：turn/steer（原包同名 ivar：已接受插话的回合 id 集合 + 不可插话时的排队消息）
    NSMutableSet *_steeringQueuedMessageIDs;
    NSMutableArray *_pendingSteerMessages;
}
@end

@implementation CACodexEngine

#pragma mark - 原包占位选择器的真实实现（此前只有 .h 声明，调用即 unrecognized selector）

- (id)currentThreadId
{
    if (_activeTurnThreadId.length > 0) return _activeTurnThreadId;
    if (self.mcpCatalogThreadId.length > 0) return self.mcpCatalogThreadId;
    return self.currentConversationId;
}

- (id)effectiveModelSlug
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[ @"CodexActiveModelSlug", @"CodexSelectedModel", @"CodexThirdPartyModel" ]) {
        NSString *value = [defaults stringForKey:key];
        if (value.length > 0) return value;
    }
    return self.thirdPartyModel;
}

- (id)latestContextTokenCount
{
    if (self.contextUsagePercent <= 0) return @(0);
    long long limit = [self.contextWindowLimitTokens longLongValue];
    if (limit <= 0) return @(0);
    return @((long long)((double)limit * (double)self.contextUsagePercent / 100.0));
}

- (id)contextWindowLimitTokens
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger tokens = [defaults integerForKey:@"CodexThirdPartyContextWindowTokens"];
    if (tokens > 0) return @(tokens);
    // 官方模型默认 272000（models.json context_window 最小值），未配置第三方时用它兜底
    return @(272000);
}


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
        _steeringQueuedMessageIDs = [NSMutableSet set];
        _pendingSteerMessages = [NSMutableArray array];
        // P1 补齐（原包方法对齐）：常驻会话就绪后主动拉取官方限额与模型列表
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(p1PersistentSessionDidChange:)
                                                     name:CACodexEnginePersistentSessionReadyNotification
                                                   object:nil];
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
    // 原包行为：app-server 发来的带 id 请求（如 item/tool/requestUserInput）由这里接住，
    // 缓存 requestID/params 供决策卡回包；带 id 消息不再走 didEmitNotification，避免重复弹卡。
    __weak typeof(self) weakSelf2 = self;
    session.serverRequestHandler = ^(NSString *method, NSDictionary *params, NSNumber *requestID) {
        typeof(self) strongSelf = weakSelf2;
        if (!strongSelf) return;
        if ([method isEqualToString:CARPCItemRequestUserInput]) {
            [strongSelf handleServerUserInputRequest:params requestID:requestID];
            return;
        }
        // 其他服务端请求：按 codex 协议立即回空 result，避免服务端挂等
        CALog(CALogLevelDebug, @"APP-SERVER", @"server request answered empty method=%@ id=%@", method ?: @"", requestID ?: @"?");
        [session sendResult:@{} forRequestID:requestID];
    };
    _persistentAppServer = session;
    CALog(CALogLevelInfo, @"APP-SERVER", @"command backend runtime=native app-server executable=%@", exe);
    [session startWithCompletion:^(BOOL ok, NSError *error) {
        if (!ok && completion) completion(NO, error);
        else if (completion) completion(YES, nil);
        if (ok) {
            // P1 补齐（原包方法对齐）：常驻会话启动成功 → 通知拉取官方限额 / 模型列表
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:CACodexEnginePersistentSessionReadyNotification object:self];
            });
        }
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

    // P1 补齐（原包方法对齐）：回合正常结束后异步刷新官方限额（dispatch_async 防重入）
    if (status == 0) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf refreshOfficialRateLimitsWithCompletion:nil];
        });
    }

    // 排队中的插话：回合结束后作为新 turn/start 自动发出
    [self deliverPendingSteerMessagesAfterTurnFinish];
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
    // 通知路径（params 里的 id 字段）：requestUserInput 也可能以通知形态到达，缓存 requestID
    id rawID = request[@"id"];
    if ([rawID isKindOfClass:NSNumber.class]) {
        _pendingUserInputRequestID = rawID;
        _pendingUserInputParams = request ?: @{};
    } else if ([rawID isKindOfClass:NSString.class]) {
        _pendingUserInputRequestID = @([(NSString *)rawID integerValue]);
        _pendingUserInputParams = request ?: @{};
    }
    [self postAppServerNotification:CARPCItemRequestUserInput params:request ?: @{}];
}

#pragma mark - 服务端请求应答（item/tool/requestUserInput）

- (NSNumber *)pendingUserInputRequestID
{
    return _pendingUserInputRequestID;
}

- (NSDictionary *)pendingUserInputParams
{
    return _pendingUserInputParams;
}

- (void)handleServerUserInputRequest:(NSDictionary *)params requestID:(NSNumber *)requestID
{
    _pendingUserInputRequestID = requestID;
    _pendingUserInputParams = [params isKindOfClass:NSDictionary.class] ? params : @{};
    CALog(CALogLevelInfo, @"APP-SERVER", @"plan user-input requested id=%@ questions=%lu",
          params[@"id"] ?: (requestID ?: @"?"), (unsigned long)[_pendingUserInputParams[@"questions"] count]);
    // 仍向聊天页广播一次（engine notification），由聊天页弹决策卡；回包走 respondToUserInputRequest:
    [self postAppServerNotification:CARPCItemRequestUserInput params:_pendingUserInputParams];
}

- (void)respondToUserInputRequest:(NSNumber *)requestID answers:(NSDictionary *)answers
{
    NSNumber *rid = requestID ?: _pendingUserInputRequestID;
    if (!rid) {
        CALog(CALogLevelWarn, @"APP-SERVER", @"respond user-input skipped reason=no pending request id");
        return;
    }
    [self.persistentAppServer sendResult:answers ?: @{} forRequestID:rid];
    if (_pendingUserInputRequestID && [rid isEqual:_pendingUserInputRequestID]) {
        _pendingUserInputRequestID = nil;
        _pendingUserInputParams = nil;
    }
}

#pragma mark - turn/steer（回合插话）

- (BOOL)canSteerActiveTurn
{
    return _turnInFlight && _activeTurnId.length > 0 && self.usePersistentAppServerChat;
}

- (void)steerPrompt:(NSString *)prompt attachments:(NSArray *)attachments completion:(void (^)(BOOL, NSError *))completion
{
    attachments = [attachments isKindOfClass:NSArray.class] ? attachments : @[];
    NSString *messageID = [[NSUUID UUID] UUIDString];

    if (![self canSteerActiveTurn]) {
        // 无活动回合：入队，finishTurnWithStatus: 完成当前回合后自动作为新 turn/start 发出
        [_pendingSteerMessages addObject:@{ @"id": messageID,
                                            @"prompt": prompt ?: @"",
                                            @"attachments": attachments ?: @[] }];
        CALog(CALogLevelInfo, @"APP-SERVER", @"queued steer kept for follow-up id=%@ reason=%@",
              messageID, @"no active turn");
        if (completion) completion(YES, nil);
        return;
    }

    CALog(CALogLevelInfo, @"APP-SERVER", @"turn/steer thread=%@ expectedTurn=%@ attachments=%lu",
          _activeTurnThreadId ?: @"(none)", _activeTurnId ?: @"?", (unsigned long)attachments.count);

    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"thread_id"] = _activeTurnThreadId ?: @"";
    parameters[@"turn_id"] = _activeTurnId ?: @"";
    NSMutableArray *items = [NSMutableArray array];
    if (prompt.length > 0) {
        [items addObject:@{ @"type": @"text", @"text": prompt }];
    }
    for (NSDictionary *attachment in attachments) {
        if (![attachment isKindOfClass:NSDictionary.class]) continue;
        NSString *path = attachment[@"path"] ?: attachment[@"localPath"] ?: attachment[@"url"];
        if (![path isKindOfClass:NSString.class] || path.length == 0) continue;
        [items addObject:@{ @"type": @"localImage", @"path": path }];
    }
    parameters[@"items"] = items;

    __weak typeof(self) weakSelf = self;
    [self.persistentAppServer callMethod:@"turn/steer"
                              parameters:parameters
                              completion:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            CALog(CALogLevelWarn, @"APP-SERVER", @"turn/steer failed thread=%@ turn=%@ reason=%@",
                  strongSelf->_activeTurnThreadId ?: @"(none)", strongSelf->_activeTurnId ?: @"?", error.localizedDescription ?: @"unknown");
            if (completion) completion(NO, error);
            return;
        }
        [strongSelf->_steeringQueuedMessageIDs addObject:messageID];
        CALog(CALogLevelInfo, @"APP-SERVER", @"turn/steer accepted thread=%@ turn=%@",
              strongSelf->_activeTurnThreadId ?: @"(none)", strongSelf->_activeTurnId ?: @"?");
        if (completion) completion(YES, nil);
    }];
}

- (void)deliverPendingSteerMessagesAfterTurnFinish
{
    if (_pendingSteerMessages.count == 0) return;
    NSDictionary *first = [_pendingSteerMessages.firstObject isKindOfClass:NSDictionary.class]
        ? (NSDictionary *)_pendingSteerMessages.firstObject : @{};
    [_pendingSteerMessages removeObjectAtIndex:0];
    NSString *prompt = [first[@"prompt"] isKindOfClass:NSString.class] ? first[@"prompt"] : @"";
    NSArray *attachments = [first[@"attachments"] isKindOfClass:NSArray.class] ? first[@"attachments"] : @[];
    CALog(CALogLevelInfo, @"APP-SERVER", @"queued steer delivered id=%@ attachments=%lu",
          first[@"id"] ?: @"?", (unsigned long)attachments.count);
    NSString *threadId = _activeTurnThreadId;
    [self sendPromptViaPersistentAppServer:prompt threadId:threadId completion:nil];
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

#pragma mark - 账号/限额（P1 补齐）

// 常驻会话就绪：先刷官方限额，再刷官方模型列表（原包客户端主动请求形态）
- (void)p1PersistentSessionDidChange:(NSNotification *)notification
{
    __weak typeof(self) weakSelf = self;
    [self refreshOfficialRateLimitsOnMainQueueWithCompletion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf refreshOfficialModelListWithCompletion:nil];
    });
}

// rate-limits.json 落盘路径：与侧栏读取候选对齐（Application Support/CodexApp/rate-limits.json）
- (NSString *)p1RateLimitsSnapshotPath
{
    return [CARuntimePaths.supportDirectory stringByAppendingPathComponent:@"rate-limits.json"];
}

- (void)refreshOfficialRateLimitsWithCompletion:(void (^)(NSDictionary *limits, NSError *error))completion
{
    if (!self.persistentAppServer.isRunning) {
        CALog(CALogLevelWarn, @"ACCOUNT", @"official rate limits refresh skipped reason=persistent session not running");
        if (completion) completion(nil, [NSError errorWithDomain:@"CodexApp.Codex" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"persistent session not running" }]);
        return;
    }
    CALog(CALogLevelInfo, @"ACCOUNT", @"requesting account/rateLimits/read on persistent session");
    __weak typeof(self) weakSelf = self;
    [self.persistentAppServer callMethod:@"account/rateLimits/read"
                              parameters:@{}
                              completion:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            // 失败只打 WARN 日志，不弹 UI
            CALog(CALogLevelWarn, @"ACCOUNT", @"official rate limits refresh failed error=%@", error.localizedDescription ?: @"unknown");
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *limits = [result isKindOfClass:NSDictionary.class] ? result : @{};
        // 落盘到侧栏读取的快照路径
        NSData *data = [NSJSONSerialization dataWithJSONObject:limits options:NSJSONWritingPrettyPrinted error:NULL];
        if (data) {
            NSString *path = [strongSelf p1RateLimitsSnapshotPath];
            [CARuntimePaths ensureDirectory:path.stringByDeletingLastPathComponent mode:0755 error:NULL];
            NSError *writeError = nil;
            BOOL ok = [CARuntimePaths writeFileAtomically:path contents:data mode:0644 error:&writeError];
            if (!ok) {
                CALog(CALogLevelWarn, @"ACCOUNT", @"official rate limits snapshot write failed path=%@ error=%@", path, writeError.localizedDescription ?: @"unknown");
            }
        }
        if (completion) completion(limits, nil);
    }];
}

- (void)refreshOfficialRateLimitsOnMainQueueWithCompletion:(void (^)(NSDictionary *limits, NSError *error))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf refreshOfficialRateLimitsWithCompletion:completion];
    });
}

#pragma mark - 模型列表（P1 补齐）

- (void)refreshOfficialModelListWithCompletion:(void (^)(NSArray *models, NSError *error))completion
{
    if (!self.persistentAppServer.isRunning) {
        CALog(CALogLevelWarn, @"ACCOUNT", @"official model/list refresh skipped reason=persistent session not running");
        if (completion) completion(nil, [NSError errorWithDomain:@"CodexApp.Codex" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"persistent session not running" }]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.persistentAppServer callMethod:@"model/list"
                              parameters:@{}
                              completion:^(id result, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            CALog(CALogLevelWarn, @"ACCOUNT", @"official model/list refresh failed reason=%@", error.localizedDescription ?: @"unknown");
            if (completion) completion(nil, error);
            return;
        }
        NSArray *models = nil;
        if ([result isKindOfClass:NSArray.class]) models = result;
        else if ([result isKindOfClass:NSDictionary.class]) {
            id inner = result[@"models"] ?: result[@"data"] ?: result[@"items"];
            if ([inner isKindOfClass:NSArray.class]) models = inner;
        }
        models = models ?: @[];
        CALog(CALogLevelInfo, @"ACCOUNT", @"official model/list refreshed models=%lu", (unsigned long)models.count);

        // 落盘到 CAModelPricingManager 目录（third-party-models.json 同目录），不改变其公开行为
        NSString *path = [[CARuntimePaths.thirdPartyCatalogPath stringByDeletingLastPathComponent]
                          stringByAppendingPathComponent:@"models-official.json"];
        NSDictionary *payload = @{ @"models": models, @"updated_at": @([[NSDate date] timeIntervalSince1970]) };
        NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:NULL];
        if (data) {
            [CARuntimePaths ensureDirectory:path.stringByDeletingLastPathComponent mode:0755 error:NULL];
            [CARuntimePaths writeFileAtomically:path contents:data mode:0644 error:NULL];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:CAModelListDidUpdateNotification object:nil];
        if (completion) completion(models, nil);
    }];
}

#pragma mark - thread/turns（P1 补齐）

- (void)requestThreadTurns:(NSString *)threadId completion:(void (^)(NSArray *turns, NSError *error))completion
{
    if (threadId.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"CodexApp.Codex" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"missing thread id" }]);
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.persistentAppServer callMethod:@"thread/turns"
                              parameters:@{ @"thread_id": threadId }
                              completion:^(id result, NSError *error) {
        if (error) {
            CALog(CALogLevelWarn, @"APP-SERVER", @"thread/turns failed thread=%@ error=%@", threadId, error.localizedDescription ?: @"unknown");
            if (completion) completion(nil, error);
            return;
        }
        NSArray *turns = nil;
        if ([result isKindOfClass:NSArray.class]) turns = result;
        else if ([result isKindOfClass:NSDictionary.class]) {
            id inner = result[@"turns"] ?: result[@"items"];
            if ([inner isKindOfClass:NSArray.class]) turns = inner;
        }
        turns = turns ?: @[];
        if (completion) completion(turns, nil);
    }];
}

@end
