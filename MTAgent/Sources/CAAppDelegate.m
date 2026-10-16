//
//  CAAppDelegate.m
//
//  行为对齐原包（观测项）：
//    didFinishLaunching      → 目录准备(CAStorageManager) → 日志会话(CALogger) → 远端策略 start(CARemoteOperations)
//                              → 运行时清单 startAutoRefresh(CARuntimeCatalog) → 内嵌 MCP 桥 127.0.0.1:27018/mcp
//    openURL                 → mtagent://settings | logs | diagnostics | chat
//    didReceiveRemoteNotification / handleActionWithIdentifier
//                              → 运行时清单刷新、停止当前运行、跳转会话
//    后台切换                 → 保存会话 / 静音音频保活(renewBackgroundTask)
//

#import "CAAppDelegate.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CARemoteOperations.h"
#import "CARuntimeCatalog.h"
#import "CAExecutionEnvironment.h"
#import "CAStorageManager.h"
#import "CAMCPBridge.h"
#import "CACodexEngine.h"
#import "CAChatViewController.h"
#import "CASettingsViewController.h"
#import "CALogViewerViewController.h"
#import "CADiagnosticsViewController.h"

static NSString * const kAPNSDeviceTokenDefaultsKey = @"CodexAPNSDeviceToken";

@interface CAAppDelegate ()

@property (nonatomic, strong, nullable) UINavigationController *rootNavigationController;

- (void)startInternalMCPBridge;
- (NSString *)catalogRuntimeSignature;
- (NSArray<CARuntimeCatalogEntry *> *)missingRequiredRuntimes;
- (void)evaluateRequiredRuntimePrompt;
- (void)presentController:(UIViewController *)controller;
- (void)installCrashReporters;

@end

@implementation CAAppDelegate

#pragma mark - 启动

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    [self installCrashReporters];
    NSError *directoryError = nil;
    if (![[CAStorageManager sharedManager] prepareDirectoriesWithError:&directoryError]) {
        CALog(CALogLevelError, @"GENERAL", @"prepare directories failed: %@", directoryError);
    }

    [[CALogger sharedLogger] beginAppSession];

    [[CARemoteOperations sharedOperations] start];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(remoteOperationsDidChange:)
                                                 name:CARemoteOperationsDidChangeNotification
                                               object:nil];

    [[CARuntimeCatalog sharedCatalog] startAutoRefresh];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeCatalogDidChange:)
                                                 name:CARuntimeCatalogDidChangeNotification
                                               object:nil];

    [self startInternalMCPBridge];

    self.chatViewController = [[CAChatViewController alloc] init];
    self.rootNavigationController = [[UINavigationController alloc] initWithRootViewController:self.chatViewController];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = self.rootNavigationController;
    [self.window makeKeyAndVisible];

    [application registerForRemoteNotifications];

    CALog(CALogLevelInfo, @"GENERAL", @"launch display=%@ version=%@ build=%@ mcp=%@",
          CABundleDisplayName, CABundleShortVersion, CABundleVersion, CAInternalMCPURLString);

    self.lastCatalogRuntimeSignature = [self catalogRuntimeSignature];
    [self prewarmComposerCatalogWithReason:@"launch" force:NO];

    return YES;
}

#pragma mark - 内嵌 MCP 桥（127.0.0.1:27018/mcp）

- (void)startInternalMCPBridge
{
    CAMCPBridge *bridge = [CAMCPBridge sharedBridge];
    NSError *error = nil;
    if (![bridge startOnPort:CAInternalMCPPort error:&error]) {
        bridge.reportedInternalMCPTransportFailure = YES;
        CALog(CALogLevelError, @"MCP", @"internal MCP bridge failed on %@: %@", CAInternalMCPURLString, error);
        return;
    }
    CALog(CALogLevelInfo, @"MCP", @"internal MCP bridge listening on %@", CAInternalMCPURLString);
}

#pragma mark - APNs

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    const unsigned char *bytes = deviceToken.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:deviceToken.length * 2];
    for (NSUInteger index = 0; index < deviceToken.length; index++) {
        [hex appendFormat:@"%02x", bytes[index]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:hex forKey:kAPNSDeviceTokenDefaultsKey];
    CALog(CALogLevelInfo, @"REMOTE", @"apns device token=%@", hex);
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    CALog(CALogLevelWarn, @"REMOTE", @"apns registration failed: %@", error);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    NSString *action = userInfo[@"action"] ?: userInfo[@"mtagent_action"];
    CALog(CALogLevelInfo, @"REMOTE", @"remote notification action=%@", action ?: @"(none)");

    if ([action isEqualToString:@"refresh-runtime"]) {
        [[CARuntimeCatalog sharedCatalog] refreshNowWithCompletion:^(BOOL ok, NSError *error) {
            CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"RUNTIME", @"remote refresh runtime manifest ok=%d error=%@", ok, error);
        }];
        completionHandler(UIBackgroundFetchResultNewData);
        return;
    }

    if ([action isEqualToString:@"stop"]) {
        [self.chatViewController handleStop];
        completionHandler(UIBackgroundFetchResultNewData);
        return;
    }

    [self.chatViewController flushStreamingMessages];
    completionHandler(UIBackgroundFetchResultNewData);
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(nullable NSString *)identifier forRemoteNotification:(NSDictionary *)userInfo completionHandler:(void (^)(void))completionHandler
{
    CALog(CALogLevelInfo, @"REMOTE", @"remote action identifier=%@", identifier ?: @"(none)");

    if ([identifier isEqualToString:@"stop"]) {
        [self.chatViewController handleStop];
    } else if ([identifier isEqualToString:@"open-diagnostics"]) {
        [self presentController:[[CADiagnosticsViewController alloc] init]];
    } else {
        [self.rootNavigationController popToRootViewControllerAnimated:YES];
    }

    if (completionHandler) completionHandler();
}

#pragma mark - 生命周期

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self.chatViewController saveActiveConversation];
    [self.chatViewController configureAudioSession];
    [self.chatViewController startSilentAudio];
    [self.chatViewController renewBackgroundTask];
    CALog(CALogLevelInfo, @"GENERAL", @"enter background");
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [self.chatViewController flushStreamingMessages];
    [self.chatViewController stopPulseTimer];
    CALog(CALogLevelInfo, @"GENERAL", @"enter foreground");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [self.chatViewController saveActiveConversation];
    CALog(CALogLevelInfo, @"GENERAL", @"will terminate");
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [[CARemoteOperations sharedOperations] performRefresh];
    [[CARuntimeCatalog sharedCatalog] refreshIfStale];
}

#pragma mark - 通知

- (void)remoteOperationsDidChange:(NSNotification *)notification
{
    CARemoteOperations *operations = [CARemoteOperations sharedOperations];
    [[CALogger sharedLogger] applyRemoteLoggingEnabled:operations.remoteLoggingEnabled];
    CALog(CALogLevelInfo, @"REMOTE",
          @"remote state healthy=%d failures=%ld/%ld policyKnown=%d logging=%d",
          operations.heartbeatHealthy,
          (long)operations.consecutiveHeartbeatFailures,
          (long)operations.heartbeatFailureLimit,
          operations.policyKnown,
          operations.remoteLoggingEnabled);
}

- (void)runtimeCatalogDidChange:(NSNotification *)notification
{
    CARuntimeCatalog *catalog = [CARuntimeCatalog sharedCatalog];
    NSString *signature = [self catalogRuntimeSignature];
    if (![signature isEqualToString:self.lastCatalogRuntimeSignature ?: @""]) {
        self.lastCatalogRuntimeSignature = signature;
        [self prewarmComposerCatalogWithReason:@"catalog.change" force:NO];
    }

    if (catalog.newlyAvailableRuntimeIDs.count > 0) {
        CALog(CALogLevelInfo, @"RUNTIME", @"newly available runtimes=%@", [catalog.newlyAvailableRuntimeIDs componentsJoinedByString:@","]);
    }
    if (catalog.changedRuntimeIDs.count > 0) {
        CALog(CALogLevelInfo, @"RUNTIME", @"changed runtimes=%@", [catalog.changedRuntimeIDs componentsJoinedByString:@","]);
        [self managedRuntimeDidChangeForPrompt:notification];
    }
    if (catalog.lastError.length > 0) {
        CALog(CALogLevelWarn, @"RUNTIME", @"runtime catalog error=%@", catalog.lastError);
    }
}

- (void)codexRuntimeDidChangeForCatalog:(NSNotification *)notification
{
    NSString *signature = [self catalogRuntimeSignature];
    self.lastCatalogRuntimeSignature = signature;
    [self prewarmComposerCatalogWithReason:@"codex.runtime" force:YES];
}

- (void)workspaceDidChangeForCatalogPrewarm:(NSNotification *)notification
{
    [self prewarmComposerCatalogWithReason:@"workspace" force:NO];
}

- (void)managedRuntimeDidChangeForPrompt:(NSNotification *)notification
{
    [self evaluateRequiredRuntimePrompt];
}

#pragma mark - 运行时预热

- (void)prewarmComposerCatalogWithReason:(NSString *)reason force:(BOOL)force
{
    CALog(CALogLevelDebug, @"RUNTIME", @"prewarm composer catalog reason=%@ force=%d", reason, force);
    if (force) {
        [[CACodexEngine sharedEngine] ensureMCPCatalogThreadWithCompletion:^(BOOL ok, NSError *error) {
            if (!ok) {
                CALog(CALogLevelWarn, @"MCP", @"catalog thread prewarm failed: %@", error);
            }
        }];
    }
    [[CACodexEngine sharedEngine] reloadMCPConfigurationWithCompletion:^(BOOL ok) {
        CALog(CALogLevelDebug, @"MCP", @"reload MCP configuration ok=%d", ok);
    }];
    [self.chatViewController refreshAttachmentPlaceholder];
}

- (NSString *)catalogRuntimeSignature
{
    NSMutableString *signature = [NSMutableString string];
    for (CARuntimeCatalogEntry *entry in [CARuntimeCatalog sharedCatalog].entries) {
        [signature appendFormat:@"%@@%@|", entry.runtimeID ?: @"?", entry.version ?: @"0"];
    }
    return signature;
}

- (NSArray<CARuntimeCatalogEntry *> *)missingRequiredRuntimes
{
    NSMutableArray<CARuntimeCatalogEntry *> *missing = [NSMutableArray array];
    for (CARuntimeCatalogEntry *entry in [CARuntimeCatalog sharedCatalog].entries) {
        if (entry.optional) continue;
        if (!entry.runtimeID.length) continue;
        NSString *root = [CARuntimePaths runtimeRootForID:entry.runtimeID];
        if (![NSFileManager.defaultManager fileExistsAtPath:root]) {
            [missing addObject:entry];
        }
    }
    return missing;
}

- (void)evaluateRequiredRuntimePrompt
{
    if (self.requiredRuntimePromptShown) return;
    NSArray<CARuntimeCatalogEntry *> *missing = [self missingRequiredRuntimes];
    if (missing.count == 0) return;

    self.requiredRuntimePromptShown = YES;
    NSMutableString *names = [NSMutableString string];
    for (CARuntimeCatalogEntry *entry in missing) {
        [names appendFormat:@"%@ ", entry.displayName ?: entry.runtimeID ?: @"?"];
    }
    // 截图里没有「运行时缺失」弹窗：原包只把状态写在设置页的行文字上，
    // 安装同样由用户点设置页的行触发。这里不再弹 UIAlertController，也不发起下载。
    CALog(CALogLevelWarn, @"RUNTIME", @"missing required runtimes=%@ (no prompt; install from settings rows)", names);
}

#pragma mark - URL scheme（mtagent）

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    if (![url.scheme isEqualToString:CAURLScheme]) {
        CALog(CALogLevelWarn, @"GENERAL", @"ignored url=%@", url.absoluteString);
        return NO;
    }

    NSString *host = url.host ?: @"";
    CALog(CALogLevelInfo, @"GENERAL", @"open url host=%@ query=%@", host, url.query ?: @"");

    if ([host isEqualToString:@"settings"]) {
        [self presentController:[[CASettingsViewController alloc] init]];
    } else if ([host isEqualToString:@"logs"]) {
        [self presentController:[[CALogViewerViewController alloc] init]];
    } else if ([host isEqualToString:@"diagnostics"]) {
        [self presentController:[[CADiagnosticsViewController alloc] init]];
    } else {
        [self.rootNavigationController dismissViewControllerAnimated:YES completion:nil];
        [self.rootNavigationController popToRootViewControllerAnimated:YES];
        [self.chatViewController refreshAttachmentPlaceholder];
    }
    return YES;
}

- (void)presentController:(UIViewController *)controller
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    UIViewController *presenter = self.rootNavigationController ?: self.window.rootViewController;
    [presenter presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - 清理

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - 崩溃兜底（未捕获异常 / 致命信号 → 落盘，供日志页查看与回传）

static NSString *CACrashLogDirectory(void)
{
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)
                     firstObject];
    dir = [dir stringByAppendingPathComponent:@"CrashReports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return dir;
}

static void CAGetCrashReportFilePath(char *out, size_t len)
{
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *path = [CACrashLogDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"crash-%@.log", [fmt stringFromDate:[NSDate date]]]];
    strncpy(out, path.fileSystemRepresentation ?: "", len - 1);
    out[len - 1] = 0;
}

static void CAUncaughtExceptionHandler(NSException *exception)
{
    char path[1024];
    CAGetCrashReportFilePath(path, sizeof(path));
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"[uncaught exception] %@\nreason: %@\ncallStack:\n", exception.name, exception.reason];
    for (NSString *frame in exception.callStackSymbols) [report appendFormat:@"  %@\n", frame];
    FILE *fp = fopen(path, "a");
    if (fp) { fwrite(report.UTF8String, 1, strlen(report.UTF8String), fp); fclose(fp); }
}

static void CASignalHandler(int sig)
{
    char path[1024];
    CAGetCrashReportFilePath(path, sizeof(path));
    const char *names[] = { 0, "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP", "SIGABRT", "SIGEMT", "SIGFPE", "SIGKILL", "SIGBUS", "SIGSEGV" };
    const char *name = (sig > 0 && (size_t)sig < sizeof(names) / sizeof(names[0])) ? names[sig] : "SIG?";
    char buf[256];
    snprintf(buf, sizeof(buf), "[fatal signal] %s (%d)\n", name, sig);
    FILE *fp = fopen(path, "a");
    if (fp) { fwrite(buf, 1, strlen(buf), fp); fclose(fp); }
    signal(sig, SIG_DFL);
    raise(sig);
}

- (void)installCrashReporters
{
    NSSetUncaughtExceptionHandler(&CAUncaughtExceptionHandler);
    signal(SIGABRT, &CASignalHandler);
    signal(SIGILL,  &CASignalHandler);
    signal(SIGSEGV, &CASignalHandler);
    signal(SIGFPE,  &CASignalHandler);
    signal(SIGBUS,  &CASignalHandler);
    signal(SIGTRAP, &CASignalHandler);
}

@end
