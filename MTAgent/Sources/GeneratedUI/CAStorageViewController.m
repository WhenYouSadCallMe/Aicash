//
//  CAStorageViewController — 存储管理（安全清理缓存）
//
//  真实视图层级：UITableViewStyleInsetGrouped 分组表格
//      · 分区 0「占用明细」：缓存 / 日志 / 运行时下载 / 会话记录 / 产物 Artifacts / 编辑器目录缓存 / 临时目录
//      · 分区 1「运行时下载」：runtimeDownloadsDirectory 下的子目录，逐项删除（二次确认）
//      · 分区 2「清理操作」：安全清理缓存 / 清理运行时下载 / 恢复出厂设置
//      · 底部工作条：operationStatus + 转圈，工作中禁用表格交互
//  真实数据来源：CARuntimePaths 各路径 + CAStorageManager
//      -directorySizeAtPath: / -clearRuntimeDownloadCaches / -purgeCachesWithCompletion: /
//      -resetLocalStatePreservingCredentials（respondsToSelector: 判断，未实现则清缓存/日志/临时目录兜底）
//  扫描策略：后台队列逐个统计，回主线程 completeScanKey:value:generation: 更新 snapshot，
//            scanGeneration 递增丢弃过期结果，只 reload 受影响的那一行。
//
//  说明：头文件把原包选择器生成成了 id 占位参数，这里逐字沿用头文件签名，
//        函数体第一行再强转成真实类型使用，避免 -Wmismatched-parameter-types。
//

#import "CAStorageViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAStorageManager.h"

static NSString *const kCAStorageValueCellReuseIdentifier = @"CAStorageValueCell";

/// 浮层提示停留时长（淡出 1.5s）
static const NSTimeInterval kCAStorageToastFadeDuration = 1.5;
static const NSTimeInterval kCAStorageToastHoldDuration = 0.6;

/// 清理只删除缓存与可重建内容的说明文案（分区尾固定使用）
static NSString *const kCAStorageUsageFooterText = @"清理只删除缓存与可重建内容，账号凭据与设置不会被移除。";

typedef NS_ENUM(NSInteger, CAStorageSection) {
    CAStorageSectionUsage = 0,
    CAStorageSectionRuntime,
    CAStorageSectionCleanup,
    CAStorageSectionCount,
};

typedef NS_ENUM(NSInteger, CAStorageCleanupRow) {
    CAStorageCleanupRowPurge = 0,
    CAStorageCleanupRowDownloads,
    CAStorageCleanupRowFactoryReset,
    CAStorageCleanupRowCount,
};

/// 统一使用 UITableViewCellStyleValue1（左侧标题 + 右侧详情）
@interface CAStorageValueCell : UITableViewCell
@end

@implementation CAStorageValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

/// 头文件把原包的 NSInteger 参数生成成了 id：同时兼容「原始整数位」与「NSNumber」两种调用
static NSInteger CAStorageSignedArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits < 0x1000) return (NSInteger)bits;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument integerValue];
    if ([argument isKindOfClass:NSString.class]) return [(NSString *)argument integerValue];
    return 0;
}

/// 头文件把原包的 unsigned long long 参数生成成了 id：同时兼容「原始整数位」与「NSNumber」两种调用
static unsigned long long CAStorageUnsignedArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits < 0x1000) return (unsigned long long)bits;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument unsignedLongLongValue];
    if ([argument isKindOfClass:NSString.class]) return (unsigned long long)[(NSString *)argument longLongValue];
    return 0;
}

/// 头文件把原包的 bool 参数生成成了 id：同时兼容「原始 0/1 位」与「NSNumber」两种调用
static BOOL CAStorageBooleanArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits == 0) return NO;
    if (bits == 1) return YES;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument boolValue];
    if ([argument isKindOfClass:NSString.class]) return [(NSString *)argument boolValue];
    return YES;
}

/// 任意取值收敛成非空文案
static NSString *CAStorageText(id value)
{
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return value ? [value description] : @"";
}

@interface CAStorageViewController () <UITableViewDataSource, UITableViewDelegate>
{
    NSDictionary *_snapshot;
    NSMutableSet *_pendingScanKeys;
    NSString *_operationStatus;
    unsigned long long _scanGeneration;
    BOOL _working;
    BOOL _resetting;

    UITableView *_tableView;
    UIView *_operationBar;
    UILabel *_operationStatusLabel;
    UIActivityIndicatorView *_operationIndicator;
    NSLayoutConstraint *_operationBarHeightConstraint;
    UIView *_toastView;
    NSMutableDictionary<NSString *, NSNumber *> *_runtimeSizeByPath;
}

- (void)handleClose;
- (NSString *)pathForStorageKey:(NSString *)key;
- (NSString *)iconNameForStorageKey:(NSString *)key;
- (NSArray<NSString *> *)runtimeDownloadDirectories;
- (NSNumber *)cachedRuntimeSizeForPath:(NSString *)path;
- (void)completeRuntimeScanPath:(NSString *)path value:(NSNumber *)value generation:(NSNumber *)generation;
- (void)reloadStorageRowForKey:(NSString *)key;
- (void)reloadRuntimeSection;
- (void)updateOperationBar;
- (void)beginOperationWithStatus:(NSString *)status resetting:(BOOL)resetting;
- (void)performCachePurge;
- (void)executeFactoryReset;
- (void)clearRuntimeDownloads;
- (void)showStorageDetailAtIndexPath:(NSIndexPath *)indexPath;

@end

@implementation CAStorageViewController

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"存储管理";
    _snapshot = @{};
    _pendingScanKeys = [NSMutableSet set];
    _runtimeSizeByPath = [NSMutableDictionary dictionary];
    _operationStatus = @"";

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 50.0;
    [_tableView registerClass:CAStorageValueCell.class forCellReuseIdentifier:kCAStorageValueCellReuseIdentifier];
    [self.view addSubview:_tableView];

    _operationBar = [[UIView alloc] initWithFrame:CGRectZero];
    _operationBar.translatesAutoresizingMaskIntoConstraints = NO;
    _operationBar.hidden = YES;

    _operationIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _operationIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _operationIndicator.hidesWhenStopped = YES;

    _operationStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _operationStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _operationStatusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _operationStatusLabel.textColor = UIColor.secondaryLabelColor;
    _operationStatusLabel.textAlignment = NSTextAlignmentCenter;

    UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;

    [_operationBar addSubview:separator];
    [_operationBar addSubview:_operationIndicator];
    [_operationBar addSubview:_operationStatusLabel];
    [self.view addSubview:_operationBar];

    _operationBarHeightConstraint = [_operationBar.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:_operationBar.topAnchor],
        [_operationBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_operationBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_operationBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        _operationBarHeightConstraint,
        [separator.topAnchor constraintEqualToAnchor:_operationBar.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:_operationBar.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:_operationBar.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],
        [_operationIndicator.leadingAnchor constraintEqualToAnchor:_operationBar.leadingAnchor constant:16.0],
        [_operationIndicator.centerYAnchor constraintEqualToAnchor:_operationBar.centerYAnchor],
        [_operationStatusLabel.leadingAnchor constraintEqualToAnchor:_operationIndicator.trailingAnchor constant:8.0],
        [_operationStatusLabel.trailingAnchor constraintEqualToAnchor:_operationBar.trailingAnchor constant:-16.0],
        [_operationStatusLabel.centerYAnchor constraintEqualToAnchor:_operationBar.centerYAnchor],
    ]];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(handleClose)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(scan)];

    [self scan];

    CALog(CALogLevelInfo, @"GENERAL", @"storage view loaded keys=%lu",
          (unsigned long)[[self storageKeys] count]);
}

- (void)handleClose
{
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 存储项

- (id)storageKeys
{
    return @[ @"caches", @"logs", @"runtimeDownloads", @"sessions", @"artifacts", @"composerCatalog", @"temporary" ];
}

- (id)storageTitles
{
    return @[ @"缓存", @"日志", @"运行时下载", @"会话记录", @"产物 Artifacts", @"编辑器目录缓存", @"临时目录" ];
}

- (NSString *)pathForStorageKey:(NSString *)key
{
    if ([key isEqualToString:@"caches"]) return CARuntimePaths.cachesDirectory;
    if ([key isEqualToString:@"logs"]) return CARuntimePaths.logsDirectory;
    if ([key isEqualToString:@"runtimeDownloads"]) return CARuntimePaths.runtimeDownloadsDirectory;
    if ([key isEqualToString:@"sessions"]) return CARuntimePaths.sessionsDirectory;
    if ([key isEqualToString:@"artifacts"]) return CARuntimePaths.artifactsDirectory;
    if ([key isEqualToString:@"composerCatalog"]) return CARuntimePaths.composerCatalogCacheDirectory;
    if ([key isEqualToString:@"temporary"]) return CARuntimePaths.tmpDirectory;
    return nil;
}

- (NSString *)iconNameForStorageKey:(NSString *)key
{
    if ([key isEqualToString:@"caches"]) return @"shippingbox";
    if ([key isEqualToString:@"logs"]) return @"doc.text.magnifyingglass";
    if ([key isEqualToString:@"runtimeDownloads"]) return @"arrow.down.circle";
    if ([key isEqualToString:@"sessions"]) return @"bubble.left.and.bubble.right";
    if ([key isEqualToString:@"artifacts"]) return @"square.stack.3d.up";
    if ([key isEqualToString:@"composerCatalog"]) return @"square.grid.2x2";
    if ([key isEqualToString:@"temporary"]) return @"clock.arrow.circlepath";
    return @"folder";
}

#pragma mark - 扫描

- (void)scan
{
    NSArray<NSString *> *keys = [self storageKeys];
    _scanGeneration += 1;
    unsigned long long generation = _scanGeneration;

    self.pendingScanKeys = [NSMutableSet setWithArray:keys];
    self.snapshot = @{};
    [_runtimeSizeByPath removeAllObjects];
    [_tableView reloadData];

    // 逐项后台统计：只更新对应的那一行，过期结果（generation 不匹配）直接丢弃
    for (NSString *key in keys) {
        NSString *path = [self pathForStorageKey:key];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            unsigned long long bytes = path.length ? [[CAStorageManager sharedManager] directorySizeAtPath:path] : 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self completeScanKey:key value:@(bytes) generation:@(generation)];
            });
        });
    }

    // 运行时下载子目录单独统计（分区 1）
    for (NSString *directory in [self runtimeDownloadDirectories]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            unsigned long long bytes = [[CAStorageManager sharedManager] directorySizeAtPath:directory];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self completeRuntimeScanPath:directory value:@(bytes) generation:@(generation)];
            });
        });
    }

    CALog(CALogLevelInfo, @"GENERAL", @"storage scan started generation=%llu keys=%lu",
          generation, (unsigned long)keys.count);
}

- (void)completeScanKey:(id)arg1 value:(id)arg2 generation:(id)arg3
{
    NSString *key = CAStorageText(arg1);
    if (!key.length) return;

    unsigned long long generation = CAStorageUnsignedArgument(arg3);
    if (generation != [self scanGeneration]) {
        CALog(CALogLevelDebug, @"GENERAL", @"stale storage scan dropped key=%@ generation=%llu current=%llu",
              key, generation, [self scanGeneration]);
        return;
    }

    NSMutableDictionary *next = [_snapshot isKindOfClass:NSDictionary.class] ? [_snapshot mutableCopy]
                                                                            : [NSMutableDictionary dictionary];
    next[key] = @(CAStorageUnsignedArgument(arg2));
    self.snapshot = next;
    [[self pendingScanKeys] removeObject:key];

    [self reloadStorageRowForKey:key];
}

- (void)completeRuntimeScanPath:(NSString *)path value:(NSNumber *)value generation:(NSNumber *)generation
{
    if (!path.length) return;
    if (generation.unsignedLongLongValue != [self scanGeneration]) return;

    _runtimeSizeByPath[path] = value ?: @0;
    [self reloadRuntimeSection];
}

- (void)reloadStorageRowForKey:(NSString *)key
{
    NSArray<NSString *> *keys = [self storageKeys];
    NSUInteger row = [keys indexOfObject:key];
    if (row == NSNotFound) return;
    if ((NSInteger)row >= [_tableView numberOfRowsInSection:CAStorageSectionUsage]) return;

    [_tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:(NSInteger)row inSection:CAStorageSectionUsage] ]
                      withRowAnimation:UITableViewRowAnimationNone];
}

- (void)reloadRuntimeSection
{
    if ([_tableView numberOfSections] <= CAStorageSectionRuntime) return;
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:CAStorageSectionRuntime]
              withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - 运行时下载子目录

- (NSArray<NSString *> *)runtimeDownloadDirectories
{
    NSString *root = CARuntimePaths.runtimeDownloadsDirectory;
    if (!root.length) return @[];

    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    NSMutableArray<NSString *> *directories = [NSMutableArray array];
    for (NSString *entry in entries) {
        BOOL isDirectory = NO;
        NSString *full = [root stringByAppendingPathComponent:entry];
        if ([NSFileManager.defaultManager fileExistsAtPath:full isDirectory:&isDirectory] && isDirectory) {
            [directories addObject:full];
        }
    }
    [directories sortUsingSelector:@selector(localizedStandardCompare:)];
    return directories;
}

- (NSNumber *)cachedRuntimeSizeForPath:(NSString *)path
{
    NSNumber *size = _runtimeSizeByPath[path];
    return [size isKindOfClass:NSNumber.class] ? size : nil;
}

- (void)deleteRuntimeAtRow:(id)arg1
{
    NSInteger row = CAStorageSignedArgument(arg1);
    NSArray<NSString *> *directories = [self runtimeDownloadDirectories];
    if (row < 0 || (NSUInteger)row >= directories.count) return;

    NSString *path = directories[(NSUInteger)row];
    NSString *name = path.lastPathComponent ?: @"运行时下载";
    NSNumber *cachedSize = [self cachedRuntimeSizeForPath:path];

    NSString *message = cachedSize
        ? [NSString stringWithFormat:@"将删除「%@」（%@），对应运行时会在下次使用时重新下载。", name, [self formattedBytes:cachedSize]]
        : [NSString stringWithFormat:@"将删除「%@」，对应运行时会在下次使用时重新下载。", name];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除运行时下载"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self beginOperationWithStatus:[NSString stringWithFormat:@"正在删除 %@…", name] resetting:NO];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            unsigned long long bytes = [[CAStorageManager sharedManager] directorySizeAtPath:path];
            NSError *error = nil;
            BOOL removed = [NSFileManager.defaultManager removeItemAtPath:path error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!removed) {
                    CALog(CALogLevelWarn, @"GENERAL", @"storage delete failed path=%@ error=%@", path, error);
                    [self finishOperationWithMessage:[NSString stringWithFormat:@"删除失败：%@", error.localizedDescription ?: @"未知错误"]];
                    return;
                }
                [self finishOperationWithMessage:[NSString stringWithFormat:@"已删除 %@（%@）", name, [self formattedBytes:@(bytes)]]];
            });
        });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 清理操作

- (void)confirmAndClearDownloads
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理运行时下载"
                                                                  message:[NSString stringWithFormat:@"将清空 %@ 下的全部下载缓存，以及本机缓存目录；账号凭据与设置不会被移除。",
                                                                           CARuntimePaths.runtimeDownloadsDirectory]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self clearRuntimeDownloads];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearRuntimeDownloads
{
    [self beginOperationWithStatus:@"正在清理运行时下载…" resetting:NO];

    // 同步清运行时下载目录，再走管理器清理缓存目录（后台队列内完成）
    [[CAStorageManager sharedManager] clearRuntimeDownloadCaches];
    [[CAStorageManager sharedManager] purgeCachesWithCompletion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message = error
                ? [NSString stringWithFormat:@"运行时下载已清理；缓存目录有残留：%@", error.localizedDescription ?: @"未知错误"]
                : @"运行时下载缓存已清理";
            [self finishOperationWithMessage:message];
        });
    }];
}

- (void)performFactoryReset
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复出厂设置"
                                                                  message:@"将清空缓存、日志与临时目录，并尽力重置本机本地状态。账号凭据与设置不会被移除。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复出厂设置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self executeFactoryReset];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)executeFactoryReset
{
    [self beginOperationWithStatus:@"正在恢复出厂设置…" resetting:YES];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CAStorageManager *manager = [CAStorageManager sharedManager];
        BOOL usedResetSelector = NO;
        if ([manager respondsToSelector:@selector(resetLocalStatePreservingCredentials)]) {
            // 原包形态：整体重置本地状态但保留凭据
            [manager resetLocalStatePreservingCredentials];
            usedResetSelector = YES;
        } else {
            // 兜底：清空缓存 / 日志 / 临时目录（随后重建空目录）
            NSArray<NSString *> *targets = @[ CARuntimePaths.cachesDirectory,
                                              CARuntimePaths.logsDirectory,
                                              CARuntimePaths.tmpDirectory ];
            for (NSString *target in targets) {
                if (!target.length) continue;
                NSError *error = nil;
                if ([NSFileManager.defaultManager fileExistsAtPath:target] &&
                    ![NSFileManager.defaultManager removeItemAtPath:target error:&error]) {
                    CALog(CALogLevelWarn, @"GENERAL", @"factory reset remove failed path=%@ error=%@", target, error);
                }
                [CARuntimePaths ensureDirectory:target mode:0700 error:NULL];
            }
        }
        [manager clearRuntimeDownloadCaches];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message = usedResetSelector
                ? @"已恢复出厂设置（账号凭据与设置保留）"
                : @"已清空缓存、日志与临时目录（账号凭据与设置保留）";
            [self finishOperationWithMessage:message];
        });
    });
}

- (void)finishOperationWithMessage:(id)arg1
{
    NSString *message = CAStorageText(arg1);
    _working = NO;
    _resetting = NO;
    _operationStatus = @"";
    [self updateOperationBar];
    [_tableView reloadData];
    if (message.length) [self showToast:message];
    // 收尾后重新统计体积（快照会被立刻清空并逐项回填）
    [self scan];
}

#pragma mark - 状态 / 提示

- (void)beginOperationWithStatus:(NSString *)status resetting:(BOOL)resetting
{
    _working = YES;
    _resetting = resetting;
    _operationStatus = [status copy] ?: @"";
    [self updateOperationBar];
    [_tableView reloadData];
}

- (void)updateOperationBar
{
    BOOL busy = _working || _resetting;
    _operationBar.hidden = !busy;
    _operationBarHeightConstraint.constant = busy ? 44.0 : 0.0;
    _operationStatusLabel.text = [self operationStatus];
    _tableView.userInteractionEnabled = !busy;
    if (busy) {
        [_operationIndicator startAnimating];
    } else {
        [_operationIndicator stopAnimating];
    }
}

- (void)showToast:(id)arg1
{
    NSString *message = CAStorageText(arg1);
    if (!message.length) return;
    if (!self.isViewLoaded) return;

    if (_toastView) {
        [_toastView removeFromSuperview];
        _toastView = nil;
    }

    UIView *toast = [[UIView alloc] initWithFrame:CGRectZero];
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.82];
    toast.layer.cornerRadius = 12.0;
    toast.layer.masksToBounds = YES;
    toast.alpha = 0.0;
    toast.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;

    [toast addSubview:label];
    [self.view addSubview:toast];

    // 底部工作条可见时浮在它上方，否则贴在安全区底部之上
    NSLayoutYAxisAnchor *bottomAnchor = _operationBar ? _operationBar.topAnchor : self.view.safeAreaLayoutGuide.bottomAnchor;
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:toast.topAnchor constant:10.0],
        [label.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-10.0],
        [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:16.0],
        [label.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-16.0],
        [toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:bottomAnchor constant:-24.0],
        [toast.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-64.0],
    ]];
    _toastView = toast;

    [UIView animateWithDuration:0.22 animations:^{
        toast.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:kCAStorageToastFadeDuration
                              delay:kCAStorageToastHoldDuration
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            toast.alpha = 0.0;
        } completion:^(BOOL completed) {
            [toast removeFromSuperview];
            if (self->_toastView == toast) self->_toastView = nil;
        }];
    }];
}

- (id)formattedBytes:(id)arg1
{
    unsigned long long bytes = CAStorageUnsignedArgument(arg1);
    if (bytes < 1024ULL) return [NSString stringWithFormat:@"%llu B", bytes];

    double value = 0.0;
    NSString *unit = @"KB";
    if (bytes < 1024ULL * 1024ULL) {
        value = (double)bytes / 1024.0;
        unit = @"KB";
    } else if (bytes < 1024ULL * 1024ULL * 1024ULL) {
        value = (double)bytes / (1024.0 * 1024.0);
        unit = @"MB";
    } else {
        value = (double)bytes / (1024.0 * 1024.0 * 1024.0);
        unit = @"GB";
    }
    return [NSString stringWithFormat:@"%.1f %@", value, unit];
}

#pragma mark - 属性（头文件声明的 getter/setter，逐字沿用签名）

- (NSDictionary *)snapshot
{
    return [_snapshot isKindOfClass:NSDictionary.class] ? _snapshot : @{};
}

- (void)setSnapshot:(id)arg1
{
    _snapshot = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : @{};
}

- (NSMutableSet *)pendingScanKeys
{
    if (!_pendingScanKeys) _pendingScanKeys = [NSMutableSet set];
    return _pendingScanKeys;
}

- (void)setPendingScanKeys:(id)arg1
{
    _pendingScanKeys = [arg1 isKindOfClass:NSMutableSet.class] ? (NSMutableSet *)arg1 : [NSMutableSet set];
}

- (unsigned long long)scanGeneration
{
    return _scanGeneration;
}

- (void)setScanGeneration:(id)arg1
{
    _scanGeneration = CAStorageUnsignedArgument(arg1);
}

- (bool)working
{
    return _working ? YES : NO;
}

- (void)setWorking:(id)arg1
{
    _working = CAStorageBooleanArgument(arg1) ? YES : NO;
    [self updateOperationBar];
}

- (bool)resetting
{
    return _resetting ? YES : NO;
}

- (void)setResetting:(id)arg1
{
    _resetting = CAStorageBooleanArgument(arg1) ? YES : NO;
    [self updateOperationBar];
}

- (NSString *)operationStatus
{
    return _operationStatus ?: @"";
}

- (void)setOperationStatus:(id)arg1
{
    _operationStatus = [CAStorageText(arg1) copy] ?: @"";
    [self updateOperationBar];
}

#pragma mark - UITableViewDataSource

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)CAStorageSectionCount;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = CAStorageSignedArgument(arg2);

    switch ((CAStorageSection)section) {
        case CAStorageSectionUsage:
            return (signed long long)[[self storageKeys] count];
        case CAStorageSectionRuntime: {
            NSUInteger count = [self runtimeDownloadDirectories].count;
            return (signed long long)MAX(count, (NSUInteger)1);
        }
        case CAStorageSectionCleanup:
            return (signed long long)CAStorageCleanupRowCount;
        default:
            return 0;
    }
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;

    if (!tableView || !indexPath) {
        return [[CAStorageValueCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    }

    CAStorageValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAStorageValueCellReuseIdentifier
                                                              forIndexPath:indexPath];
    cell.textLabel.text = @"";
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = @"";
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = nil;
    cell.imageView.tintColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    switch ((CAStorageSection)indexPath.section) {
        case CAStorageSectionUsage: {
            NSArray<NSString *> *keys = [self storageKeys];
            NSArray<NSString *> *titles = [self storageTitles];
            if (indexPath.row < 0 || (NSUInteger)indexPath.row >= keys.count) return cell;

            NSString *key = keys[(NSUInteger)indexPath.row];
            NSString *title = indexPath.row < (NSInteger)titles.count ? titles[(NSUInteger)indexPath.row] : key;
            cell.textLabel.text = title;
            cell.imageView.image = [UIImage systemImageNamed:[self iconNameForStorageKey:key]];

            if ([[self pendingScanKeys] containsObject:key]) {
                cell.detailTextLabel.text = @"计算中…";
            } else {
                NSNumber *bytes = [[self snapshot] objectForKey:key];
                cell.detailTextLabel.text = [bytes isKindOfClass:NSNumber.class] ? [self formattedBytes:bytes] : @"—";
            }
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case CAStorageSectionRuntime: {
            NSArray<NSString *> *directories = [self runtimeDownloadDirectories];
            if (!directories.count) {
                cell.textLabel.text = @"暂无可清理的下载缓存";
                cell.detailTextLabel.text = @"—";
                cell.imageView.image = [UIImage systemImageNamed:@"checkmark.circle"];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                break;
            }
            if (indexPath.row < 0 || (NSUInteger)indexPath.row >= directories.count) return cell;

            NSString *path = directories[(NSUInteger)indexPath.row];
            cell.textLabel.text = path.lastPathComponent ?: @"运行时下载";
            NSNumber *size = [self cachedRuntimeSizeForPath:path];
            cell.detailTextLabel.text = size ? [self formattedBytes:size] : @"计算中…";
            cell.imageView.image = [UIImage systemImageNamed:@"shippingbox"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case CAStorageSectionCleanup:
        default: {
            switch ((CAStorageCleanupRow)indexPath.row) {
                case CAStorageCleanupRowPurge:
                    cell.textLabel.text = @"安全清理缓存";
                    cell.detailTextLabel.text = @"缓存 · 日志 · 临时目录";
                    cell.imageView.image = [UIImage systemImageNamed:@"sparkles"];
                    break;
                case CAStorageCleanupRowDownloads:
                    cell.textLabel.text = @"清理运行时下载";
                    cell.detailTextLabel.text = @"可重新下载";
                    cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.circle"];
                    break;
                case CAStorageCleanupRowFactoryReset:
                default:
                    cell.textLabel.text = @"恢复出厂设置";
                    cell.textLabel.textColor = UIColor.systemRedColor;
                    cell.detailTextLabel.text = @"保留账号凭据";
                    cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
                    cell.imageView.tintColor = UIColor.systemRedColor;
                    break;
            }
            break;
        }
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = CAStorageSignedArgument(arg2);

    switch ((CAStorageSection)section) {
        case CAStorageSectionUsage:
            return kCAStorageUsageFooterText;
        case CAStorageSectionRuntime:
            return @"逐项删除后，对应运行时会在下次使用时重新下载。";
        case CAStorageSectionCleanup:
        default:
            return @"清理期间界面会暂时禁用交互，完成后自动重新统计。";
    }
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    NSInteger section = CAStorageSignedArgument(arg2);
    if ((CAStorageSection)section == CAStorageSectionUsage) return 48.0;
    return 44.0;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return;

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch ((CAStorageSection)indexPath.section) {
        case CAStorageSectionUsage:
            [self showStorageDetailAtIndexPath:indexPath];
            return;
        case CAStorageSectionRuntime:
            [self deleteRuntimeAtRow:(__bridge id)(void *)(uintptr_t)indexPath.row];
            return;
        case CAStorageSectionCleanup:
        default:
            switch ((CAStorageCleanupRow)indexPath.row) {
                case CAStorageCleanupRowPurge:
                    [self performCachePurge];
                    break;
                case CAStorageCleanupRowDownloads:
                    [self confirmAndClearDownloads];
                    break;
                case CAStorageCleanupRowFactoryReset:
                default:
                    [self performFactoryReset];
                    break;
            }
            return;
    }
}

#pragma mark - 明细

- (void)performCachePurge
{
    [self beginOperationWithStatus:@"正在清理缓存…" resetting:NO];

    [[CAStorageManager sharedManager] purgeCachesWithCompletion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message = error
                ? [NSString stringWithFormat:@"缓存已清理；日志/临时目录有残留：%@", error.localizedDescription ?: @"未知错误"]
                : @"缓存、日志与临时目录已清理";
            [self finishOperationWithMessage:message];
        });
    }];
}

- (void)showStorageDetailAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray<NSString *> *keys = [self storageKeys];
    NSArray<NSString *> *titles = [self storageTitles];
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= keys.count) return;

    NSString *key = keys[(NSUInteger)indexPath.row];
    NSString *title = indexPath.row < (NSInteger)titles.count ? titles[(NSUInteger)indexPath.row] : key;
    NSString *path = [self pathForStorageKey:key];
    NSNumber *bytes = [[self snapshot] objectForKey:key];
    BOOL exists = path.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:path];

    NSString *message = [NSString stringWithFormat:@"项目：%@\n路径：%@\n体积：%@\n状态：%@",
                         title,
                         path.length ? path : @"—",
                         [bytes isKindOfClass:NSNumber.class] ? [self formattedBytes:bytes] : @"计算中…",
                         exists ? @"存在" : @"不存在"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = path ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
