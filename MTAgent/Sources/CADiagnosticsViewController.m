//
//  CADiagnosticsViewController.m
//
//  分区（与页面文案一致）：概览 / 网络 / 远端开关 / 运行时 / 环境 / shell 探针 / MCP 桥 / 登录态。
//  数据来源全部为工程公共件：CARemoteOperations、CARuntimeCatalog(+Entry)、CAExecutionEnvironment、
//  CACodexEngine、CAMCPBridge、CARuntimePaths、CALogger、CAProviderConfiguration。
//

#import "CADiagnosticsViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CACodexEngine.h"
#import "CARemoteOperations.h"
#import "CAExecutionEnvironment.h"
#import "CARuntimeCatalog.h"
#import "CAMCPBridge.h"
#import "CAProviderConfiguration.h"
#import "CAUpdateViewController.h"
#import "CAUpdateProgress.h"
#import "CALogViewerViewController.h"

static NSString * const kDiagnosticsCellReuseIdentifier = @"CADiagnosticsCell";
/// 「安装」分区标题（行含义：0 一键安装 / 1 状态 / 2 当前阶段 / 3 失败项 / 4 最近日志 / 5 签名模板 / 6… 各必需运行时）
static NSString * const kDiagnosticsInstallSectionTitle = @"安装";
/// 安装分区里“逐运行时”行的起始下标
static const NSInteger kDiagnosticsInstallRuntimeRowStart = 6;

/// CARootMode → 字符串（CAExecutionEnvironmentProfile 只提供 rootModeString）
static NSString *CADiagnosticsRootModeString(CARootMode mode)
{
    switch (mode) {
        case CARootModeRootless:  return @"rootless";
        case CARootModeRootful:   return @"rootful";
        case CARootModeRootHide:  return @"roothide";
        case CARootModeRoothide:  return @"roothide";
        case CARootModeUnknown:
        default:                  return @"unknown";
    }
}

typedef NS_ENUM(NSInteger, CADiagnosticsItemStatus) {
    CADiagnosticsItemStatusPending = 0,
    CADiagnosticsItemStatusOK,
    CADiagnosticsItemStatusWarn,
    CADiagnosticsItemStatusFail,
    CADiagnosticsItemStatusInfo,
};

#pragma mark - 模型（私有）

/// 统一使用 UITableViewCellStyleValue1（左侧标题 + 右侧详情）
@interface CADiagnosticsValueCell : UITableViewCell
@end

@implementation CADiagnosticsValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

@interface CADiagnosticsItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) CADiagnosticsItemStatus status;
@property (nonatomic, assign) BOOL optional;
@property (nonatomic, assign) BOOL expandable;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, copy, nullable) NSString *runtimeID;
@end

@implementation CADiagnosticsItem

+ (instancetype)friendlyItem:(NSString *)title ok:(BOOL)ok optional:(BOOL)optional detail:(NSString *)detail
{
    CADiagnosticsItem *item = [[CADiagnosticsItem alloc] init];
    item.title = title ?: @"";
    item.detail = detail ?: @"";
    item.optional = optional;
    item.status = ok ? CADiagnosticsItemStatusOK : (optional ? CADiagnosticsItemStatusWarn : CADiagnosticsItemStatusFail);
    return item;
}

+ (instancetype)pendingItem:(NSString *)title detail:(NSString *)detail
{
    CADiagnosticsItem *item = [[CADiagnosticsItem alloc] init];
    item.title = title ?: @"";
    item.detail = detail ?: @"探测中…";
    item.status = CADiagnosticsItemStatusPending;
    return item;
}

- (NSString *)statusSymbol
{
    switch (self.status) {
        case CADiagnosticsItemStatusOK:      return @"✓";
        case CADiagnosticsItemStatusWarn:    return @"!";
        case CADiagnosticsItemStatusFail:    return @"✗";
        case CADiagnosticsItemStatusPending: return @"…";
        case CADiagnosticsItemStatusInfo:
        default:                             return @"·";
    }
}

- (BOOL)isProblem
{
    return self.status == CADiagnosticsItemStatusWarn || self.status == CADiagnosticsItemStatusFail;
}

@end

@interface CADiagnosticsSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<CADiagnosticsItem *> *items;
@end

@implementation CADiagnosticsSection

+ (instancetype)sectionWithTitle:(NSString *)title
{
    CADiagnosticsSection *section = [[CADiagnosticsSection alloc] init];
    section.title = title ?: @"";
    section.items = [NSMutableArray array];
    return section;
}

@end

#pragma mark - 诊断页

/// 「安装」分区固定行（6 起为该分区内各必需运行时的安装行）
typedef NS_ENUM(NSInteger, CADiagnosticsInstallRow) {
    CADiagnosticsInstallRowOneTap = 0,
    CADiagnosticsInstallRowStatus,
    CADiagnosticsInstallRowStage,
    CADiagnosticsInstallRowFailures,
    CADiagnosticsInstallRowLogs,
    CADiagnosticsInstallRowEntitlements,
};

@interface CADiagnosticsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) NSTimer *elapsedRefreshTimer;
@property (nonatomic, assign) NSUInteger probeGeneration;

/// 安装分区状态
@property (nonatomic, strong, nullable) NSMutableArray<NSString *> *installFailures;
@property (nonatomic, copy, nullable) NSString *installStageText;
@property (nonatomic, assign) double installFraction;
@property (nonatomic, strong, nullable) UIProgressView *installProgressView;
@property (nonatomic, strong, nullable) NSTimer *installRefreshTimer;

- (void)startProbe;
- (void)finishProbeWithResult:(NSDictionary *)result;
- (NSArray<CADiagnosticsSection *> *)pendingUserSections;
- (NSArray<CADiagnosticsSection *> *)userSectionsForResult:(NSDictionary *)result;
- (CADiagnosticsSection *)installSection;
- (CADiagnosticsItem *)itemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)itemHasExpandableDetail:(CADiagnosticsItem *)item;
- (NSString *)textForItem:(CADiagnosticsItem *)item;
- (NSString *)summaryTitle;
- (NSString *)summaryDetail;
- (void)refreshSummaryCell;
- (void)updateActionState;
- (void)elapsedRefreshTimerTick:(NSTimer *)timer;
- (void)runtimeCatalogDidChange:(NSNotification *)notification;
- (NSString *)reportText;
- (NSString *)durationText;
- (void)close;
- (void)moreMenu;

#pragma mark - 安装 / 修复运行时
- (void)handleInstallSectionSelectionAtIndexPath:(NSIndexPath *)indexPath item:(CADiagnosticsItem *)item;
- (void)startInstallRefreshTimer;
- (void)stopInstallRefreshTimer;
- (void)installRefreshTimerTick:(NSTimer *)timer;
- (void)reloadInstallRows;
- (void)updateInstallProgress:(CAUpdateProgress *)progress runtimeID:(NSString *)runtimeID;
- (nullable NSString *)recentLogTail;
- (nullable NSString *)signingTemplatePath;
- (void)presentUpdateSheetForRuntimeID:(NSString *)runtimeID;
- (void)showMessage:(NSString *)message title:(NSString *)title;

@end

@implementation CADiagnosticsViewController

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"诊断";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.installStatus = @"待检查";
    self.installFailures = [NSMutableArray array];
    self.installFraction = 0.0;
    self.installStageText = @"";

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    [self.tableView registerClass:CADiagnosticsValueCell.class forCellReuseIdentifier:kDiagnosticsCellReuseIdentifier];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                         target:self
                                                                                         action:@selector(close)];
    self.rerunItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                      style:UIBarButtonItemStylePlain
                                                     target:self
                                                     action:@selector(run)];
    self.shareItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                      style:UIBarButtonItemStylePlain
                                                     target:self
                                                     action:@selector(handleShareReport)];
    self.reportCopyItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(handleCopyReport)];
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(moreMenu)];
    self.navigationItem.rightBarButtonItems = @[ self.rerunItem, self.shareItem, self.reportCopyItem, moreItem ];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeCatalogDidChange:)
                                                 name:CARuntimeCatalogDidChangeNotification
                                               object:nil];

    [self run];
}

- (void)dealloc
{
    [self.elapsedRefreshTimer invalidate];
    [self stopInstallRefreshTimer];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 探测

- (void)run
{
    self.probeGeneration += 1;
    NSUInteger generation = self.probeGeneration;
    [self startProbe];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *snapshot = [weakSelf diagnosticSnapshot] ?: @{};
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (generation != strongSelf.probeGeneration) {
                CALog(CALogLevelDebug, @"GENERAL", @"stale diagnostics result ignored generation=%lu", (unsigned long)generation);
                return;
            }
            [strongSelf finishProbeWithResult:snapshot];
        });
    });
}

- (void)startProbe
{
    self.probing = YES;
    self.startedAt = [NSDate date];
    self.finishedAt = nil;
    self.checkCount = 0;
    self.problemCount = 0;
    self.installStatus = @"检查中…";
    self.sections = [self pendingUserSections];
    [self updateActionState];
    [self.tableView reloadData];
    [self startElapsedTimer];
}

- (void)startElapsedTimer
{
    if (self.elapsedRefreshTimer) return;
    self.elapsedRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(elapsedRefreshTimerTick:) userInfo:nil repeats:YES];
}

- (void)elapsedRefreshTimerTick:(NSTimer *)timer
{
    if (!self.probing) {
        [timer invalidate];
        self.elapsedRefreshTimer = nil;
        return;
    }
    [self refreshSummaryCell];
}

- (void)finishProbeWithResult:(NSDictionary *)result
{
    self.result = result;
    self.sections = [self userSectionsForResult:result];
    self.probing = NO;
    self.finishedAt = [NSDate date];
    [self.elapsedRefreshTimer invalidate];
    self.elapsedRefreshTimer = nil;

    NSInteger checks = 0;
    NSInteger problems = 0;
    for (CADiagnosticsSection *section in self.sections) {
        for (CADiagnosticsItem *item in section.items) {
            checks += 1;
            if ([item isProblem]) problems += 1;
        }
    }
    self.checkCount = checks;
    self.problemCount = problems;

    NSDictionary *runtime = [result[@"runtime"] isKindOfClass:NSDictionary.class] ? result[@"runtime"] : nil;
    NSInteger installed = [runtime[@"installedCount"] integerValue];
    NSInteger total = [runtime[@"requiredCount"] integerValue];
    NSInteger missing = [runtime[@"requiredMissingCount"] integerValue];
    self.installTotalCount = total;
    self.installCompletedCount = installed;
    if (!self.installingRuntime) {
        self.installStatus = missing > 0
            ? [NSString stringWithFormat:@"缺失 %ld 个必需运行时", (long)missing]
            : [NSString stringWithFormat:@"必需运行时已就绪（%ld/%ld）", (long)installed, (long)MAX(total, (NSInteger)0)];
    }

    [self updateActionState];
    [self.tableView reloadData];
    CALog(CALogLevelInfo, @"GENERAL", @"diagnostics finished checks=%ld problems=%ld", (long)checks, (long)problems);
}

#pragma mark - 快照

- (NSDictionary *)diagnosticSnapshot
{
    CARemoteOperations *remote = [CARemoteOperations sharedOperations];
    CARuntimeCatalog *catalog = [CARuntimeCatalog sharedCatalog];
    CAExecutionEnvironment *environment = [CAExecutionEnvironment sharedEnvironment];
    CACodexEngine *engine = [CACodexEngine sharedEngine];
    CAMCPBridge *bridge = [CAMCPBridge sharedBridge];
    [environment refresh];

    NSMutableDictionary<NSString *, NSDictionary *> *runtimeVersions = [NSMutableDictionary dictionary];
    NSInteger requiredCount = 0;
    NSInteger installedCount = 0;
    NSInteger requiredMissing = 0;
    for (CARuntimeCatalogEntry *entry in catalog.entries) {
        if (entry.runtimeID.length == 0) continue;
        NSString *root = [CARuntimePaths runtimeRootForID:entry.runtimeID];
        BOOL installed = [CAUpdateViewController isRuntimeInstalled:entry.runtimeID];
        runtimeVersions[entry.runtimeID] = @{ @"version": entry.version ?: @"?",
                                              @"installed": @(installed),
                                              @"optional": @(entry.optional),
                                              @"root": root ?: @"" };
        if (!entry.optional) {
            requiredCount += 1;
            if (installed) installedCount += 1; else requiredMissing += 1;
        }
    }

    NSDictionary *directories = [self directoriesSnapshot];
    NSDictionary *remoteSnapshot = @{
        @"base": CARemoteBaseURL,
        @"heartbeatHealthy": @(remote.heartbeatHealthy),
        @"failures": @(remote.consecutiveHeartbeatFailures),
        @"failureLimit": @(remote.heartbeatFailureLimit),
        @"policyKnown": @(remote.policyKnown),
        @"remoteLogging": @(remote.remoteLoggingEnabled),
        @"lastSuccess": remote.lastHeartbeatSuccess ? [remote.lastHeartbeatSuccess description] : @"(无)",
        @"anonymousID": remote.anonymousID ?: @"(空)",
        @"deviceGroupID": remote.deviceGroupID ?: @"(空)",
        @"policy": remote.policy ?: @{},
    };

    NSDictionary *runtimeSnapshot = @{
        @"manifest": catalog.manifestURLString ?: @"",
        @"cachePath": catalog.cachePath ?: @"",
        @"lastError": catalog.lastError ?: @"",
        @"refreshing": @(catalog.refreshing),
        @"entryCount": @(catalog.entries.count),
        @"requiredCount": @(requiredCount),
        @"installedCount": @(installedCount),
        @"requiredMissingCount": @(requiredMissing),
        @"versions": runtimeVersions,
    };

    CAExecutionEnvironmentProfile *profile = environment.profile;
    NSDictionary *environmentSnapshot = @{
        @"kind": environment.runtimeEnvironmentKind ?: profile.environmentKind ?: @"unknown",
        @"jailbreak": @(environment.runtimeHasJailbreakEvidence),
        @"trollstore": @(environment.runtimeHasTrollStore),
        @"rootMode": [NSString stringWithFormat:@"%@ (运行时 %@)", profile.rootModeString ?: @"unknown", CADiagnosticsRootModeString(environment.runtimeRootMode)],
        @"family": environment.runtimeJailbreakFamily ?: profile.familyName ?: @"none",
        @"brand": environment.runtimeJailbreakBrand ?: profile.brandName ?: @"none",
        @"launcher": environment.runtimeJailbreakLauncher ?: profile.launcherDisplayName ?: @"none",
        @"launcherBundle": environment.runtimeJailbreakLauncherBundle ?: profile.launcherBundleId ?: @"none",
        @"trollstoreFlavor": environment.runtimeTrollStoreFlavor ?: profile.trollStoreFlavor ?: @"none",
        @"evidence": environment.runtimeEnvironmentEvidence ?: profile.evidenceSummary ?: @"",
        @"directories": directories,
    };

    NSDictionary *shellSnapshot = @{
        @"executable": environment.shellExecutable ?: @"(未解析)",
        @"spawnMode": environment.shellSpawnMode ?: @"(未知)",
        @"probe": environment.shellBootstrapProbeOutput ?: @"",
        @"environmentKeys": @(environment.environmentVariablesForRuntime.count),
    };

    NSDictionary *bridgeSnapshot = @{
        @"url": CAInternalMCPURLString,
        @"host": CAInternalMCPHost,
        @"port": @(bridge.port ?: CAInternalMCPPort),
        @"running": @(bridge.running),
        @"reportedFailure": @(bridge.reportedInternalMCPTransportFailure),
    };

    NSDictionary *loginSnapshot = @{
        @"loggedIn": @(engine.isLoggedIn),
        @"status": engine.loginStatusText ?: @"(未检查)",
        @"hasAPIKey": @([[CAProviderConfiguration sharedConfiguration] readAPIKeyWithError:NULL] != nil),
        @"lastError": engine.lastReportedExecutionError ?: @"",
        @"keyPath": [CAProviderConfiguration sharedConfiguration].keyPath ?: @"",
    };

    return @{
        @"generated_at": [NSDate date].description ?: @"",
        @"app": @{ @"version": CABundleShortVersion, @"build": CABundleVersion, @"bundle": CABundleIdentifier },
        @"remote": remoteSnapshot,
        @"runtime": runtimeSnapshot,
        @"environment": environmentSnapshot,
        @"shell": shellSnapshot,
        @"mcp": bridgeSnapshot,
        @"login": loginSnapshot,
    };
}

- (NSDictionary *)directoriesSnapshot
{
    NSDictionary<NSString *, NSString *> *paths = @{
        @"support": CARuntimePaths.supportDirectory,
        @"codexHome": CARuntimePaths.codexHome,
        @"logs": CARuntimePaths.logsDirectory,
        @"conversations": CARuntimePaths.conversationsDirectory,
        @"runtimeDownloads": CARuntimePaths.runtimeDownloadsDirectory,
        @"tmp": CARuntimePaths.tmpDirectory,
    };
    NSMutableDictionary<NSString *, NSDictionary *> *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in paths) {
        NSString *path = paths[key];
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path];
        BOOL writable = [NSFileManager.defaultManager isWritableFileAtPath:path];
        snapshot[key] = @{ @"path": path ?: @"", @"exists": @(exists), @"writable": @(writable) };
    }
    return snapshot;
}

#pragma mark - 分区

- (NSArray<CADiagnosticsSection *> *)pendingUserSections
{
    NSArray<NSString *> *titles = @[ @"检查结果", @"基础运行", @"插件", @"组件与工具", @"运行环境", @"基础运行", @"插件", @"账户" ];
    NSMutableArray<CADiagnosticsSection *> *sections = [NSMutableArray array];
    for (NSString *title in titles) {
        CADiagnosticsSection *section = [CADiagnosticsSection sectionWithTitle:title];
        [section.items addObject:[CADiagnosticsItem pendingItem:title detail:@"探测中…"]];
        [sections addObject:section];
    }
    if (sections.count > 4) {
        [sections insertObject:[self installSection] atIndex:4];
    } else {
        [sections addObject:[self installSection]];
    }
    return sections;
}

- (NSArray<CADiagnosticsSection *> *)userSectionsForResult:(NSDictionary *)result
{
    NSMutableArray<CADiagnosticsSection *> *sections = [NSMutableArray array];

    NSDictionary *remote = result[@"remote"];
    NSDictionary *runtime = result[@"runtime"];
    NSDictionary *environment = result[@"environment"];
    NSDictionary *shell = result[@"shell"];
    NSDictionary *mcp = result[@"mcp"];
    NSDictionary *login = result[@"login"];

    // 概览
    CADiagnosticsSection *overview = [CADiagnosticsSection sectionWithTitle:@"检查结果"];
    [overview.items addObject:[CADiagnosticsItem friendlyItem:@"生成时间" ok:YES optional:NO detail:result[@"generated_at"] ?: @""]];
    [overview.items addObject:[CADiagnosticsItem friendlyItem:@"应用版本" ok:YES optional:NO
                                                      detail:[NSString stringWithFormat:@"%@ (%@) · %@", CABundleShortVersion, CABundleVersion, CABundleIdentifier]]];
    [overview.items addObject:[CADiagnosticsItem friendlyItem:@"运行时安装状态"
                                                           ok:([runtime[@"requiredMissingCount"] integerValue] == 0)
                                                     optional:YES
                                                       detail:self.installStatus ?: @""]];
    [sections addObject:overview];

    // 网络
    CADiagnosticsSection *network = [CADiagnosticsSection sectionWithTitle:@"基础运行"];
    [network.items addObject:[CADiagnosticsItem friendlyItem:@"远端端点" ok:YES optional:NO detail:remote[@"base"] ?: @""]];
    [network.items addObject:[CADiagnosticsItem friendlyItem:@"心跳"
                                                         ok:[remote[@"heartbeatHealthy"] boolValue]
                                                   optional:NO
                                                     detail:[NSString stringWithFormat:@"连续失败 %@/%@ · 上次成功 %@",
                                                             remote[@"failures"] ?: @0,
                                                             remote[@"failureLimit"] ?: @0,
                                                             remote[@"lastSuccess"] ?: @"(无)"]]];
    [network.items addObject:[CADiagnosticsItem friendlyItem:@"匿名标识" ok:YES optional:YES detail:remote[@"anonymousID"] ?: @""]];
    [network.items addObject:[CADiagnosticsItem friendlyItem:@"设备组标识" ok:YES optional:YES detail:remote[@"deviceGroupID"] ?: @""]];
    [sections addObject:network];

    // 远端开关
    CADiagnosticsSection *remoteSection = [CADiagnosticsSection sectionWithTitle:@"插件"];
    NSDictionary *policy = [remote[@"policy"] isKindOfClass:NSDictionary.class] ? remote[@"policy"] : @{};
    NSDictionary *featureFlags = [policy[@"feature_flags"] isKindOfClass:NSDictionary.class] ? policy[@"feature_flags"] : @{};
    NSDictionary *logSwitches = [policy[@"log_switches"] isKindOfClass:NSDictionary.class] ? policy[@"log_switches"] : @{};
    [remoteSection.items addObject:[CADiagnosticsItem friendlyItem:@"策略已知"
                                                               ok:[remote[@"policyKnown"] boolValue]
                                                         optional:YES
                                                           detail:[remote[@"policyKnown"] boolValue] ? @"已下发" : @"未获取（使用本地默认）"]];
    [remoteSection.items addObject:[CADiagnosticsItem friendlyItem:@"远程日志" ok:YES optional:YES detail:[remote[@"remoteLogging"] boolValue] ? @"开启" : @"关闭"]];
    for (NSString *key in featureFlags) {
        id value = featureFlags[key];
        [remoteSection.items addObject:[CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"flag %@", key]
                                                                     ok:YES
                                                               optional:YES
                                                                 detail:[value description] ?: @""]];
    }
    for (NSString *key in logSwitches) {
        id value = logSwitches[key];
        [remoteSection.items addObject:[CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"log %@", key]
                                                                     ok:YES
                                                               optional:YES
                                                                 detail:[value description] ?: @""]];
    }
    if (featureFlags.count == 0 && logSwitches.count == 0) {
        [remoteSection.items addObject:[CADiagnosticsItem friendlyItem:@"开关列表" ok:YES optional:YES detail:@"(空)"]];
    }
    [sections addObject:remoteSection];

    // 运行时
    CADiagnosticsSection *runtimeSection = [CADiagnosticsSection sectionWithTitle:@"组件与工具"];
    [runtimeSection.items addObject:[CADiagnosticsItem friendlyItem:@"清单地址" ok:YES optional:NO detail:runtime[@"manifest"] ?: @""]];
    [runtimeSection.items addObject:[CADiagnosticsItem friendlyItem:@"本地缓存"
                                                                ok:[(runtime[@"lastError"] ?: @"") length] == 0
                                                          optional:YES
                                                            detail:[NSString stringWithFormat:@"%@%s%@",
                                                                    runtime[@"cachePath"] ?: @"(无)",
                                                                    [(runtime[@"lastError"] ?: @"") length] ? " · 错误: " : "",
                                                                    runtime[@"lastError"] ?: @""]]];
    NSDictionary *versions = [runtime[@"versions"] isKindOfClass:NSDictionary.class] ? runtime[@"versions"] : @{};
    for (NSString *runtimeID in versions) {
        NSDictionary *info = versions[runtimeID];
        BOOL installed = [info[@"installed"] boolValue];
        BOOL optional = [info[@"optional"] boolValue];
        CADiagnosticsItem *item = [CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"%@ %@", runtimeID, info[@"version"] ?: @"?"]
                                                               ok:installed
                                                         optional:optional
                                                           detail:[NSString stringWithFormat:@"%@ · 根目录 %@",
                                                                   installed ? @"已安装" : @"未安装",
                                                                   info[@"root"] ?: @""]];
        item.runtimeID = runtimeID;
        item.expandable = YES;
        [runtimeSection.items addObject:item];
    }
    if (versions.count == 0) {
        [runtimeSection.items addObject:[CADiagnosticsItem friendlyItem:@"运行时条目" ok:NO optional:YES detail:@"清单为空（可下拉刷新）"]];
    }
    [sections addObject:runtimeSection];

    // 安装 / 修复
    [sections addObject:[self installSection]];

    // 环境
    CADiagnosticsSection *environmentSection = [CADiagnosticsSection sectionWithTitle:@"运行环境"];
    [environmentSection.items addObject:[CADiagnosticsItem friendlyItem:@"环境类型" ok:YES optional:NO detail:environment[@"kind"] ?: @"unknown"]];
    [environmentSection.items addObject:[CADiagnosticsItem friendlyItem:@"越狱证据" ok:YES optional:YES detail:[environment[@"jailbreak"] boolValue] ? @"有" : @"无"]];
    [environmentSection.items addObject:[CADiagnosticsItem friendlyItem:@"TrollStore" ok:YES optional:YES detail:[environment[@"trollstore"] boolValue] ? @"有" : @"无"]];
    [environmentSection.items addObject:[CADiagnosticsItem friendlyItem:@"Root 模式" ok:YES optional:YES detail:environment[@"rootMode"] ?: @"unknown"]];
    [environmentSection.items addObject:[CADiagnosticsItem friendlyItem:@"家族 / 品牌"
                                                                     ok:YES
                                                               optional:YES
                                                                 detail:[NSString stringWithFormat:@"%@ / %@",
                                                                         environment[@"family"] ?: @"none",
                                                                         environment[@"brand"] ?: @"none"]]];
    [environmentSection.items addObject:[CADiagnosticsItem friendlyItem:@"启动器"
                                                                     ok:YES
                                                               optional:YES
                                                                 detail:[NSString stringWithFormat:@"%@ (%@)",
                                                                         environment[@"launcher"] ?: @"none",
                                                                         environment[@"launcherBundle"] ?: @"none"]]];
    CADiagnosticsItem *evidence = [CADiagnosticsItem friendlyItem:@"证据摘要" ok:YES optional:YES detail:environment[@"evidence"] ?: @""];
    evidence.expandable = YES;
    [environmentSection.items addObject:evidence];

    NSDictionary *directories = [environment[@"directories"] isKindOfClass:NSDictionary.class] ? environment[@"directories"] : @{};
    for (NSString *key in directories) {
        NSDictionary *info = directories[key];
        BOOL exists = [info[@"exists"] boolValue];
        BOOL writable = [info[@"writable"] boolValue];
        CADiagnosticsItem *item = [CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"目录 %@", key]
                                                               ok:exists && writable
                                                         optional:YES
                                                           detail:[NSString stringWithFormat:@"%@%s", info[@"path"] ?: @"", writable ? " · 可写" : " · 只读"]];
        item.expandable = YES;
        [environmentSection.items addObject:item];
    }
    [sections addObject:environmentSection];

    // shell 探针
    CADiagnosticsSection *shellSection = [CADiagnosticsSection sectionWithTitle:@"基础运行"];
    [shellSection.items addObject:[CADiagnosticsItem friendlyItem:@"shell 可执行" ok:[(shell[@"executable"] ?: @"(未解析)") hasPrefix:@"/"] optional:NO detail:shell[@"executable"] ?: @"(未解析)"]];
    [shellSection.items addObject:[CADiagnosticsItem friendlyItem:@"启动方式" ok:YES optional:NO detail:shell[@"spawnMode"] ?: @"(未知)"]];
    [shellSection.items addObject:[CADiagnosticsItem friendlyItem:@"环境变量数" ok:YES optional:YES detail:[NSString stringWithFormat:@"%@ 项", shell[@"environmentKeys"] ?: @0]]];
    CADiagnosticsItem *probe = [CADiagnosticsItem friendlyItem:@"自检脚本输出" ok:YES optional:YES detail:shell[@"probe"] ?: @"(空)"];
    probe.expandable = YES;
    [shellSection.items addObject:probe];
    [sections addObject:shellSection];

    // MCP 桥
    CADiagnosticsSection *mcpSection = [CADiagnosticsSection sectionWithTitle:@"插件"];
    [mcpSection.items addObject:[CADiagnosticsItem friendlyItem:@"监听端口"
                                                            ok:[mcp[@"running"] boolValue]
                                                      optional:NO
                                                        detail:[NSString stringWithFormat:@"%@:%@ · %@",
                                                                mcp[@"host"] ?: CAInternalMCPHost,
                                                                mcp[@"port"] ?: @(CAInternalMCPPort),
                                                                [mcp[@"running"] boolValue] ? @"运行中" : @"未运行"]]];
    [mcpSection.items addObject:[CADiagnosticsItem friendlyItem:@"端点" ok:YES optional:NO detail:mcp[@"url"] ?: CAInternalMCPURLString]];
    [mcpSection.items addObject:[CADiagnosticsItem friendlyItem:@"传输失败上报"
                                                            ok:![mcp[@"reportedFailure"] boolValue]
                                                      optional:YES
                                                        detail:[mcp[@"reportedFailure"] boolValue] ? @"已上报失败" : @"无失败记录"]];
    [sections addObject:mcpSection];

    // 登录态
    CADiagnosticsSection *loginSection = [CADiagnosticsSection sectionWithTitle:@"账户"];
    [loginSection.items addObject:[CADiagnosticsItem friendlyItem:@"登录状态"
                                                               ok:[login[@"loggedIn"] boolValue]
                                                         optional:NO
                                                           detail:[login[@"loggedIn"] boolValue] ? @"已登录" : @"未登录"]];
    [loginSection.items addObject:[CADiagnosticsItem friendlyItem:@"状态详情" ok:YES optional:NO detail:login[@"status"] ?: @""]];
    [loginSection.items addObject:[CADiagnosticsItem friendlyItem:@"第三方密钥" ok:YES optional:YES detail:[login[@"hasAPIKey"] boolValue] ? @"已保存" : @"未保存"]];
    CADiagnosticsItem *keyPath = [CADiagnosticsItem friendlyItem:@"密钥路径" ok:YES optional:YES detail:login[@"keyPath"] ?: @""];
    keyPath.expandable = YES;
    [loginSection.items addObject:keyPath];
    if ([(login[@"lastError"] ?: @"") length] > 0) {
        CADiagnosticsItem *lastError = [CADiagnosticsItem friendlyItem:@"最近执行错误" ok:NO optional:NO detail:login[@"lastError"] ?: @""];
        lastError.expandable = YES;
        [loginSection.items addObject:lastError];
    }
    [sections addObject:loginSection];

    // 同名分区合并（原包每个分类只出现一次）
    NSMutableArray<CADiagnosticsSection *> *merged = [NSMutableArray array];
    NSMutableDictionary<NSString *, CADiagnosticsSection *> *byTitle = [NSMutableDictionary dictionary];
    for (CADiagnosticsSection *section in sections) {
        NSString *title = section.title ?: @"";
        CADiagnosticsSection *existing = byTitle[title];
        if (existing) {
            [existing.items addObjectsFromArray:section.items];
        } else {
            byTitle[title] = section;
            [merged addObject:section];
        }
    }
    sections = merged;

    // 按原包分区顺序排列：检查结果 → 基础运行 → 组件与工具 → 安装 → 插件 → 运行环境 → 账户
    NSArray<NSString *> *preferredOrder = @[ @"检查结果", @"基础运行", @"组件与工具", @"安装", @"插件", @"运行环境", @"账户" ];
    [sections sortUsingComparator:^NSComparisonResult(CADiagnosticsSection *a, CADiagnosticsSection *b) {
        NSUInteger ia = [preferredOrder indexOfObject:a.title ?: @""];
        NSUInteger ib = [preferredOrder indexOfObject:b.title ?: @""];
        if (ia == NSNotFound) ia = preferredOrder.count;
        if (ib == NSNotFound) ib = preferredOrder.count;
        if (ia == ib) return NSOrderedSame;
        return ia < ib ? NSOrderedAscending : NSOrderedDescending;
    }];
    return sections;
}

#pragma mark - 安装 / 修复运行时

- (CADiagnosticsSection *)installSection
{
    CADiagnosticsSection *section = [CADiagnosticsSection sectionWithTitle:kDiagnosticsInstallSectionTitle];

    CADiagnosticsItem *oneTap = [CADiagnosticsItem friendlyItem:@"一键安装 / 修复必需运行时"
                                                            ok:YES
                                                      optional:YES
                                                        detail:@"按清单安装缺失项：下载 → 校验 → 解包 → 签名 → 安装"];
    [section.items addObject:oneTap];

    NSArray<NSString *> *missing = (NSArray<NSString *> *)[self requiredRuntimeIDsNeedingInstall];
    BOOL busy = self.installingRuntime;
    CADiagnosticsItem *status = [CADiagnosticsItem friendlyItem:@"安装状态"
                                                           ok:(missing.count == 0 && !busy)
                                                     optional:YES
                                                       detail:self.installStatus ?: @"待检查"];
    [section.items addObject:status];

    CADiagnosticsItem *stage = [CADiagnosticsItem friendlyItem:@"当前阶段"
                                                          ok:!busy
                                                    optional:YES
                                                      detail:self.installStageText.length ? self.installStageText : @"(空闲)"];
    [section.items addObject:stage];

    NSArray<NSString *> *failures = self.installFailures ?: @[];
    CADiagnosticsItem *failureItem = [CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"失败项（%lu）", (unsigned long)failures.count]
                                                                 ok:(failures.count == 0)
                                                           optional:YES
                                                             detail:failures.count ? [failures componentsJoinedByString:@"\n"] : @"无"];
    failureItem.expandable = failures.count > 0;
    [section.items addObject:failureItem];

    NSString *logTail = [self recentLogTail];
    CADiagnosticsItem *logItem = [CADiagnosticsItem friendlyItem:@"最近日志（CALogger）"
                                                            ok:(logTail.length > 0)
                                                      optional:YES
                                                        detail:logTail.length ? logTail : @"(暂无日志)"];
    logItem.expandable = logTail.length > 0;
    [section.items addObject:logItem];

    NSString *template = [self signingTemplatePath];
    CADiagnosticsItem *entitlements = [CADiagnosticsItem friendlyItem:@"签名模板"
                                                                  ok:(template.length > 0)
                                                            optional:YES
                                                              detail:template.length ? template : @"未找到 ResignEntitlements/*.plist，签名步骤会失败"];
    [section.items addObject:entitlements];

    for (CARuntimeCatalogEntry *entry in [CARuntimeCatalog sharedCatalog].entries) {
        if (entry.optional || !entry.runtimeID.length) continue;
        BOOL installed = [CAUpdateViewController isRuntimeInstalled:entry.runtimeID];
        CADiagnosticsItem *item = [CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"%@ · %@", entry.runtimeID, installed ? @"已安装" : @"未安装"]
                                                               ok:installed
                                                         optional:NO
                                                           detail:@"点击安装 / 修复该运行时（带阶段进度）"];
        item.runtimeID = entry.runtimeID;
        [section.items addObject:item];
    }

    return section;
}

- (void)reloadInstallRows
{
    NSUInteger index = NSNotFound;
    for (NSUInteger cursor = 0; cursor < self.sections.count; cursor++) {
        CADiagnosticsSection *section = self.sections[cursor];
        if ([section.title isEqualToString:kDiagnosticsInstallSectionTitle]) { index = cursor; break; }
    }
    if (index == NSNotFound) return;

    NSMutableArray *mutable = [self.sections mutableCopy];
    mutable[index] = [self installSection];
    self.sections = mutable;

    // 防护：视图不在窗口 / 表尚未加载过（numberOfSections==0）/ 页面正在关闭时，
    // reloadSections 会被 UIKit 当作 "insert section" 并抛 NSInternalInconsistencyException。
    if (!self.tableView.window || [self.tableView numberOfSections] == 0) {
        [self.tableView reloadData];
        return;
    }
    if ((NSUInteger)index >= (NSUInteger)[self.tableView numberOfSections]) {
        [self.tableView reloadData];
        return;
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:index] withRowAnimation:UITableViewRowAnimationNone];
}

- (NSString *)recentLogTail
{
    NSString *text = [[CALogger sharedLogger] currentLogText] ?: @"";
    if (text.length <= 1200) return text;
    return [NSString stringWithFormat:@"…%@", [text substringFromIndex:text.length - 1200]];
}

- (NSString *)signingTemplatePath
{
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSArray<NSString *> *candidates = @[
        [bundlePath stringByAppendingPathComponent:@"ResignEntitlements/runtime.entitlements.plist"],
        [bundlePath stringByAppendingPathComponent:@"ResignEntitlements/helper.entitlements.plist"],
        [bundlePath stringByAppendingPathComponent:@"entitlements.plist"],
    ];
    for (NSString *candidate in candidates) {
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

- (void)startInstallRefreshTimer
{
    if (self.installRefreshTimer) return;
    self.installRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                               target:self
                                                             selector:@selector(installRefreshTimerTick:)
                                                             userInfo:nil
                                                              repeats:YES];
}

- (void)stopInstallRefreshTimer
{
    [self.installRefreshTimer invalidate];
    self.installRefreshTimer = nil;
    // dealloc/关闭路径不再触发 reload，避免对已 detach 的表做更新（SIGSEGV/insert-section 崩溃源）
}

- (void)installRefreshTimerTick:(NSTimer *)timer
{
    if (!self.installingRuntime) {
        [timer invalidate];
        self.installRefreshTimer = nil;
        [self reloadInstallRows];
        return;
    }
    [self reloadInstallRows];
}

- (void)updateInstallProgress:(CAUpdateProgress *)progress runtimeID:(NSString *)runtimeID
{
    if (!progress) return;
    double perRuntime = MAX(0.0, MIN(1.0, progress.fraction));
    NSInteger total = MAX(self.installTotalCount, (NSInteger)1);
    double base = (double)self.installCompletedCount / (double)total;
    self.installFraction = MIN(1.0, base + perRuntime / (double)total);
    self.activeInstallRuntimeID = runtimeID;
    self.installStageText = [NSString stringWithFormat:@"%@ · %@ · %@（%d%%）",
                             runtimeID,
                             [progress stageTitle],
                             progress.status ?: @"",
                             (int)(perRuntime * 100.0)];
    self.installProgressView.progress = (float)self.installFraction;
}

#pragma mark 安装流程（选择器与 SPEC/method_types.json 对齐）

- (id)installRequiredRuntimes
{
    if (self.installingRuntime) {
        [self showMessage:@"已有安装任务在进行中" title:@"安装"];
        return nil;
    }
    NSArray<NSString *> *ids = (NSArray<NSString *> *)[self requiredRuntimeIDsNeedingInstall];
    if (!ids.count) {
        self.installStatus = @"必需运行时已就绪";
        self.installStageText = @"无需安装";
        [self reloadInstallRows];
        [self showMessage:@"必需运行时均已安装" title:@"安装"];
        return nil;
    }

    self.installingRuntime = YES;
    self.installFailures = [NSMutableArray array];
    self.installTotalCount = (NSInteger)ids.count;
    self.installCompletedCount = 0;
    self.installFraction = 0.0;
    self.installStageText = @"准备安装…";
    self.installStatus = [NSString stringWithFormat:@"安装中：0/%ld", (long)ids.count];
    [self startInstallRefreshTimer];
    [self reloadInstallRows];

    CALog(CALogLevelInfo, @"RUNTIME", @"diagnostics one-tap install runtimes=%@", [ids componentsJoinedByString:@","]);
    [self installRuntimeIDs:ids index:@(0) failures:self.installFailures];
    return nil;
}

- (id)requiredRuntimeIDsNeedingInstall
{
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (CARuntimeCatalogEntry *entry in [CARuntimeCatalog sharedCatalog].entries) {
        if (entry.optional || !entry.runtimeID.length) continue;
        if (![CAUpdateViewController isRuntimeInstalled:entry.runtimeID]) [ids addObject:entry.runtimeID];
    }
    return ids;
}

- (id)requiredRuntimeInstallDetail
{
    NSArray<NSString *> *ids = (NSArray<NSString *> *)[self requiredRuntimeIDsNeedingInstall];
    if (!ids.count) return @"必需运行时均已安装";
    NSMutableString *text = [NSMutableString string];
    for (NSString *runtimeID in ids) {
        CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];
        NSString *size = entry.expandedSize > 0
            ? [NSByteCountFormatter stringFromByteCount:(long long)entry.expandedSize countStyle:NSByteCountFormatterCountStyleFile]
            : @"(未知大小)";
        [text appendFormat:@"%@ · 清单 %@ · %@\n", runtimeID, entry.version ?: @"?", size];
    }
    return text;
}

- (id)installRuntimeID:(id)arg1 completion:(id)arg2
{
    NSString *runtimeID = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    void (^completion)(BOOL, NSString *) = arg2 ? (void (^)(BOOL, NSString *))arg2 : nil;

    if (!runtimeID.length) {
        if (completion) completion(NO, @"运行时 ID 为空");
        return nil;
    }

    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];
    if (!entry || !entry.archiveURL.length) {
        if (completion) completion(NO, [NSString stringWithFormat:@"运行时清单缺少 %@（请先刷新清单）", runtimeID]);
        return nil;
    }

    if (!self.installingRuntime) {
        self.installingRuntime = YES;
        [self startInstallRefreshTimer];
    }
    self.activeInstallRuntimeID = runtimeID;
    self.installStageText = [NSString stringWithFormat:@"%@ · 准备中…", runtimeID];
    [self reloadInstallRows];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [CAUpdateViewController installRuntimeEntry:entry progress:^(CAUpdateProgress *progress) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf updateInstallProgress:progress runtimeID:runtimeID];
            });
        } error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *message = ok ? @"安装完成" : (error.localizedDescription ?: @"安装失败");
            CALog(ok ? CALogLevelInfo : CALogLevelError, @"RUNTIME", @"diagnostics install runtime=%@ ok=%d message=%@",
                  runtimeID, ok, message);
            if (completion) completion(ok, message);
        });
    });
    return nil;
}

- (id)installRuntimeIDs:(id)arg1 index:(id)arg2 failures:(id)arg3
{
    NSArray<NSString *> *ids = [arg1 isKindOfClass:NSArray.class] ? (NSArray<NSString *> *)arg1 : @[];
    NSInteger index = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    NSMutableArray<NSString *> *failures = [arg3 isKindOfClass:NSMutableArray.class] ? (NSMutableArray<NSString *> *)arg3 : [NSMutableArray array];

    if (index >= (NSInteger)ids.count) {
        [self finishRuntimeInstallBatchWithFailures:failures];
        return nil;
    }

    NSString *runtimeID = ids[(NSUInteger)index];
    __weak typeof(self) weakSelf = self;
    [self installRuntimeID:runtimeID completion:^(BOOL ok, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!ok) {
                [failures addObject:[NSString stringWithFormat:@"%@：%@", runtimeID, message.length ? message : @"安装失败"]];
                CALog(CALogLevelError, @"RUNTIME", @"diagnostics install failed runtime=%@ message=%@", runtimeID, message ?: @"");
            }
            strongSelf.installCompletedCount = index + 1;
            strongSelf.installStatus = [NSString stringWithFormat:@"安装中：%ld/%ld",
                                        (long)strongSelf.installCompletedCount, (long)strongSelf.installTotalCount];
            [strongSelf reloadInstallRows];
            [strongSelf installRuntimeIDs:ids index:@(index + 1) failures:failures];
        });
    }];
    return nil;
}

- (id)installSingleRuntimeID:(id)arg1
{
    NSString *runtimeID = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    if (!runtimeID.length) return nil;
    if (self.installingRuntime) {
        [self showMessage:@"已有安装任务在进行中" title:@"安装"];
        return nil;
    }

    self.installingRuntime = YES;
    self.installFailures = [NSMutableArray array];
    self.installTotalCount = 1;
    self.installCompletedCount = 0;
    self.installFraction = 0.0;
    self.installStatus = [NSString stringWithFormat:@"安装中：0/1（%@）", runtimeID];
    self.installStageText = @"准备中…";
    [self startInstallRefreshTimer];
    [self reloadInstallRows];

    __weak typeof(self) weakSelf = self;
    [self installRuntimeID:runtimeID completion:^(BOOL ok, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.installCompletedCount = 1;
            NSMutableArray<NSString *> *failures = [NSMutableArray array];
            if (!ok) [failures addObject:[NSString stringWithFormat:@"%@：%@", runtimeID, message ?: @"安装失败"]];
            [strongSelf finishRuntimeInstallBatchWithFailures:failures];
        });
    }];
    return nil;
}

- (id)finishRuntimeInstallBatchWithFailures:(id)arg1
{
    NSArray<NSString *> *failures = [arg1 isKindOfClass:NSArray.class] ? (NSArray<NSString *> *)arg1 : @[];
    self.installFailures = [NSMutableArray arrayWithArray:failures];
    self.installingRuntime = NO;
    self.activeInstallRuntimeID = nil;
    [self stopInstallRefreshTimer];

    NSArray<NSString *> *missing = (NSArray<NSString *> *)[self requiredRuntimeIDsNeedingInstall];
    self.installStatus = failures.count
        ? [NSString stringWithFormat:@"失败 %lu 个 · 仍需安装 %lu 个", (unsigned long)failures.count, (unsigned long)missing.count]
        : (missing.count ? [NSString stringWithFormat:@"仍需安装 %lu 个", (unsigned long)missing.count] : @"必需运行时已就绪");
    self.installStageText = failures.count ? @"安装结束（存在失败项）" : @"安装完成";
    if (!failures.count) self.installFraction = 1.0;
    [self reloadInstallRows];
    [self run];

    if (failures.count) {
        NSString *message = [NSString stringWithFormat:@"%@\n\n最近日志：\n%@",
                             [failures componentsJoinedByString:@"\n"],
                             [self recentLogTail] ?: @"(无)"];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"安装失败"
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"查看完整日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CALogViewerViewController alloc] init]];
            [self presentViewController:navigation animated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self showMessage:@"必需运行时均已安装" title:@"安装完成"];
    }
    return nil;
}

- (id)setRuntimeInstallStatus:(id)arg1 runtimeID:(id)arg2
{
    NSString *status = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    NSString *runtimeID = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : [arg2 description];
    self.installStatus = status ?: @"";
    if (runtimeID.length) self.activeInstallRuntimeID = runtimeID;
    [self reloadInstallRows];
    return nil;
}

- (id)hasRuntimeActivity
{
    return @(self.installingRuntime);
}

- (id)kickAutomaticRuntimeRecovery
{
    // 打开诊断页不自动发起大体积下载：只刷新清单并记录缺口，等待用户点“一键安装”
    NSArray<NSString *> *missing = (NSArray<NSString *> *)[self requiredRuntimeIDsNeedingInstall];
    CALog(CALogLevelInfo, @"RUNTIME", @"diagnostics automatic recovery probe missing=%lu（等待用户确认后再下载）",
          (unsigned long)missing.count);
    [[CARuntimeCatalog sharedCatalog] refreshIfStale];
    [self reloadInstallRows];
    return nil;
}

- (id)liveRuntimeActivityForID:(id)arg1
{
    NSString *runtimeID = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    if (self.installingRuntime && [runtimeID isEqualToString:self.activeInstallRuntimeID ?: @""]) {
        return [NSString stringWithFormat:@"%@（%d%%）", self.installStageText ?: @"安装中", (int)(self.installFraction * 100.0)];
    }
    return @"(空闲)";
}

- (id)runtimeCheckForID:(id)arg1
{
    NSString *runtimeID = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    if (!runtimeID.length) return @{};
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];
    NSString *root = [CARuntimePaths runtimeRootForID:runtimeID];
    BOOL installed = [CAUpdateViewController isRuntimeInstalled:runtimeID];
    return @{
        @"runtime_id": runtimeID,
        @"version": entry.version ?: @"",
        @"revision": @(entry.revision),
        @"installed": @(installed),
        @"root": root ?: @"",
        @"expanded_size": @(entry.expandedSize),
        @"detail": installed ? @"已安装" : @"未安装",
    };
}

- (id)runtimeItemFromCheck:(id)arg1
{
    NSDictionary *check = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : @{};
    NSString *runtimeID = [check[@"runtime_id"] isKindOfClass:NSString.class] ? check[@"runtime_id"] : @"?";
    BOOL installed = [check[@"installed"] boolValue];
    CADiagnosticsItem *item = [CADiagnosticsItem friendlyItem:[NSString stringWithFormat:@"%@ · %@", runtimeID, check[@"version"] ?: @"?"]
                                                          ok:installed
                                                    optional:NO
                                                      detail:check[@"detail"] ?: @""];
    item.runtimeID = runtimeID;
    return item;
}

- (id)runtimeStateDidChange:(id)arg1
{
    [self reloadInstallRows];
    return nil;
}

- (void)presentUpdateSheetForRuntimeID:(NSString *)runtimeID
{
    if (!runtimeID.length) return;
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];
    if (!entry || !entry.archiveURL.length) {
        [self showMessage:[NSString stringWithFormat:@"运行时清单里没有 %@（可重新检查刷新清单）", runtimeID] title:@"组件与工具"];
        return;
    }

    CAUpdateViewController *controller = [[CAUpdateViewController alloc] initWithRuntimeID:runtimeID version:entry.version];
    __weak typeof(self) weakSelf = self;
    controller.finishHandler = ^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!success && message.length) {
                [strongSelf.installFailures addObject:[NSString stringWithFormat:@"%@：%@", runtimeID, message]];
            }
            strongSelf.installStatus = success
                ? [NSString stringWithFormat:@"%@ 安装完成", runtimeID]
                : [NSString stringWithFormat:@"%@ 安装失败", runtimeID];
            [strongSelf run];
        });
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)handleInstallSectionSelectionAtIndexPath:(NSIndexPath *)indexPath item:(CADiagnosticsItem *)item
{
    switch ((CADiagnosticsInstallRow)indexPath.row) {
        case CADiagnosticsInstallRowOneTap:
            [self installRequiredRuntimes];
            return;
        case CADiagnosticsInstallRowStatus:
        case CADiagnosticsInstallRowStage:
            [self showMessage:[NSString stringWithFormat:@"%@\n%@",
                               self.installStatus ?: @"",
                               self.installStageText ?: @""]
                        title:@"安装状态"];
            return;
        case CADiagnosticsInstallRowFailures: {
            NSArray<NSString *> *failures = self.installFailures ?: @[];
            if (!failures.count) {
                [self showMessage:@"暂无失败项" title:@"安装失败项"];
                return;
            }
            [self showMessage:[failures componentsJoinedByString:@"\n"] title:@"安装失败项"];
            return;
        }
        case CADiagnosticsInstallRowLogs: {
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CALogViewerViewController alloc] init]];
            [self presentViewController:navigation animated:YES completion:nil];
            return;
        }
        case CADiagnosticsInstallRowEntitlements: {
            NSString *path = [self signingTemplatePath];
            NSString *message = path.length
                ? [NSString stringWithFormat:@"签名模板：%@", path]
                : [NSString stringWithFormat:@"bundle 内未找到 ResignEntitlements/*.plist\nbundle：%@\n签名步骤会以 CAUpdateManager 默认路径执行，缺失即签名失败。",
                   NSBundle.mainBundle.bundlePath ?: @"(unknown)"];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"签名模板" message:message preferredStyle:UIAlertControllerStyleAlert];
            if (path.length) {
                [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    UIPasteboard.generalPasteboard.string = path;
                }]];
            }
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        default:
            break;
    }

    if (indexPath.row >= kDiagnosticsInstallRuntimeRowStart && item.runtimeID.length) {
        [self presentUpdateSheetForRuntimeID:item.runtimeID];
    }
}

- (void)showMessage:(NSString *)message title:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 报告

- (NSString *)durationText
{
    if (!self.startedAt) return @"(未开始)";
    NSDate *end = self.finishedAt ?: [NSDate date];
    return [NSString stringWithFormat:@"%.2fs", [end timeIntervalSinceDate:self.startedAt]];
}

- (NSString *)summaryTitle
{
    if (self.probing) return @"正在诊断…";
    if (self.problemCount > 0) return [NSString stringWithFormat:@"发现 %ld 个问题", (long)self.problemCount];
    return @"全部检查通过";
}

- (NSString *)summaryDetail
{
    return [NSString stringWithFormat:@"检查 %ld 项 · 耗时 %@ · %@",
            (long)self.checkCount, [self durationText], self.installStatus ?: @""];
}

- (NSString *)reportText
{
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"MT 智能体 · 诊断报告\n"];
    [text appendFormat:@"生成时间：%@\n", [NSDate date].description ?: @""];
    [text appendFormat:@"版本：%@ (%@)\n", CABundleShortVersion, CABundleVersion];
    [text appendFormat:@"检查：%ld 项，问题：%ld 项，耗时：%@\n",
     (long)self.checkCount, (long)self.problemCount, [self durationText]];
    [text appendFormat:@"安装状态：%@\n\n", self.installStatus ?: @""];

    for (CADiagnosticsSection *section in self.sections) {
        [text appendFormat:@"== %@ ==\n", section.title];
        for (CADiagnosticsItem *item in section.items) {
            [text appendFormat:@"%@ %@：%@\n", item.statusSymbol, item.title, item.detail];
        }
        [text appendString:@"\n"];
    }
    return text;
}

- (void)handleCopyReport
{
    UIPasteboard.generalPasteboard.string = [self reportText];
    CALog(CALogLevelInfo, @"GENERAL", @"diagnostics report copied");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:@"诊断报告已复制" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)handleShareReport
{
    NSString *text = [self reportText];
    NSString *name = [NSString stringWithFormat:@"CodexApp-diagnostics-%@.txt",
                      [[NSUUID.UUID.UUIDString substringToIndex:8] lowercaseString]];
    NSString *path = [CARuntimePaths.tmpDirectory stringByAppendingPathComponent:name];
    NSError *error = nil;
    [CARuntimePaths ensureDirectory:path.stringByDeletingLastPathComponent mode:0700 error:&error];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ text, [NSURL fileURLWithPath:path] ]
                                                                          applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.view;
    activity.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)moreMenu
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重新检查" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self run];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"一键安装/修复运行时" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self installRequiredRuntimes];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleCopyReport];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享报告" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleShareReport];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CALogViewerViewController alloc] init]];
        [self presentViewController:navigation animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 行 / 状态

- (void)updateActionState
{
    self.rerunItem.enabled = !self.probing;
    self.shareItem.enabled = !self.probing && self.sections.count > 0;
    self.reportCopyItem.enabled = !self.probing && self.sections.count > 0;
}

- (void)refreshSummaryCell
{
    NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
    if (!cell) return;
    cell.textLabel.text = [self summaryTitle];
    cell.detailTextLabel.text = [self summaryDetail];
}

- (CADiagnosticsItem *)itemAtIndexPath:(NSIndexPath *)indexPath
{
    if ((NSUInteger)indexPath.section >= self.sections.count) return nil;
    CADiagnosticsSection *section = self.sections[(NSUInteger)indexPath.section];
    if ((NSUInteger)indexPath.row >= section.items.count) return nil;
    return section.items[(NSUInteger)indexPath.row];
}

- (BOOL)itemHasExpandableDetail:(CADiagnosticsItem *)item
{
    return item.expandable && item.detail.length > 0;
}

- (NSString *)textForItem:(CADiagnosticsItem *)item
{
    return [NSString stringWithFormat:@"%@ %@", item.statusSymbol, item.title];
}

- (void)runtimeCatalogDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self run];
    });
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ((NSUInteger)section >= self.sections.count) return 0;
    CADiagnosticsSection *model = self.sections[(NSUInteger)section];
    return (NSInteger)model.items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if ((NSUInteger)section >= self.sections.count) return nil;
    return [self.sections[(NSUInteger)section] title];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDiagnosticsCellReuseIdentifier forIndexPath:indexPath];
    CADiagnosticsItem *item = [self itemAtIndexPath:indexPath];

    cell.textLabel.text = [self textForItem:item];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = item.expanded ? 0 : 2;
    cell.detailTextLabel.text = [self itemHasExpandableDetail:item] && !item.expanded
        ? [NSString stringWithFormat:@"%@（点击展开）", item.detail]
        : item.detail;
    cell.accessoryType = [self itemHasExpandableDetail:item] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    switch (item.status) {
        case CADiagnosticsItemStatusOK:
            cell.textLabel.textColor = UIColor.labelColor;
            break;
        case CADiagnosticsItemStatusWarn:
            cell.textLabel.textColor = UIColor.systemOrangeColor;
            break;
        case CADiagnosticsItemStatusFail:
            cell.textLabel.textColor = UIColor.systemRedColor;
            break;
        default:
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            break;
    }

    if ((NSUInteger)indexPath.section < self.sections.count) {
        CADiagnosticsSection *section = self.sections[(NSUInteger)indexPath.section];
        if ([section.title isEqualToString:kDiagnosticsInstallSectionTitle]) {
            if (indexPath.row == CADiagnosticsInstallRowOneTap) {
                cell.textLabel.textColor = self.view.tintColor;
                cell.accessoryView = nil;
            } else if (indexPath.row == CADiagnosticsInstallRowStage) {
                UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
                progressView.frame = CGRectMake(0.0, 0.0, 120.0, 4.0);
                progressView.progress = (float)self.installFraction;
                cell.accessoryView = progressView;
                self.installProgressView = progressView;
            } else if (cell.accessoryView) {
                cell.accessoryView = nil;
            }
        } else if (cell.accessoryView) {
            cell.accessoryView = nil;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CADiagnosticsItem *item = [self itemAtIndexPath:indexPath];

    if ((NSUInteger)indexPath.section < self.sections.count) {
        CADiagnosticsSection *section = self.sections[(NSUInteger)indexPath.section];
        if ([section.title isEqualToString:kDiagnosticsInstallSectionTitle]) {
            [self handleInstallSectionSelectionAtIndexPath:indexPath item:item];
            return;
        }
    }

    if (![self itemHasExpandableDetail:item]) return;
    item.expanded = !item.expanded;
    [tableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                        point:(CGPoint)point
{
    CADiagnosticsItem *item = [self itemAtIndexPath:indexPath];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIAction *copy = [UIAction actionWithTitle:@"复制该项" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *action) {
            UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@：%@", item.statusSymbol, item.title, item.detail];
        }];
        return [UIMenu menuWithTitle:@"" children:@[ copy ]];
    }];
}

@end
