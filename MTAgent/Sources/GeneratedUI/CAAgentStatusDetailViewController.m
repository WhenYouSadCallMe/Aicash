//
//  CAAgentStatusDetailViewController — Agent 运行状态详情
//
//  真实视图层级：UITableViewStyleInsetGrouped 分组表格（UITableViewCellStyleValue1）
//  真实数据来源：
//    · defaults：CodexSelectedModel / CodexActiveModelSlug / CodexReasoningEffort /
//      CodexActiveReasoningEffort / CodexActiveWorkspace
//    · CACodexEngine.sharedEngine：isRunning / contextUsagePercent / currentWorkspacePath /
//      mcpCatalogThreadId（占位选择器一律先 respondsToSelector: 再取值，取不到显示「—」）
//    · uptime：本面板自身计时（_openedAt）
//  快照键：state / model / effort / workspace / thread / contextPercent（键名自定义，中文由 statusText: 翻译）
//
//  说明：头文件把原包选择器生成成了 id 占位参数，这里逐字沿用头文件签名，
//        函数体第一行再强转成真实类型使用，避免 -Wmismatched-parameter-types。
//

#import "CAAgentStatusDetailViewController.h"
#import "CACommon.h"
#import "CACodexEngine.h"
#import "CAModelPricingManager.h"

static NSString *const kCAAgentStatusValueCellReuseIdentifier = @"CAAgentStatusValueCell";

// 快照键（复刻自定义；构成中文文案的映射全部落在 statusText: 内）
static NSString *const kCAAgentStatusSnapshotStateKey = @"state";
static NSString *const kCAAgentStatusSnapshotModelKey = @"model";
static NSString *const kCAAgentStatusSnapshotEffortKey = @"effort";
static NSString *const kCAAgentStatusSnapshotWorkspaceKey = @"workspace";
static NSString *const kCAAgentStatusSnapshotThreadKey = @"thread";
static NSString *const kCAAgentStatusSnapshotContextPercentKey = @"contextPercent";
static NSString *const kCAAgentStatusSnapshotUptimeKey = @"uptime";

// 分区 / 行内字典键
static NSString *const kCAAgentStatusSectionTitleKey = @"title";
static NSString *const kCAAgentStatusSectionRowsKey = @"rows";
static NSString *const kCAAgentStatusRowKeyKey = @"key";
static NSString *const kCAAgentStatusRowTitleKey = @"title";
static NSString *const kCAAgentStatusRowDetailKey = @"detail";

/// 运行状态的原始值与中文名
static NSString *const kCAAgentStatusRawRunning = @"running";
static NSString *const kCAAgentStatusRawIdle = @"idle";

typedef NS_ENUM(NSInteger, CAAgentStatusSection) {
    CAAgentStatusSectionRuntime = 0,
    CAAgentStatusSectionModel,
    CAAgentStatusSectionWorkspace,
    CAAgentStatusSectionCount,
};

/// 统一使用 UITableViewCellStyleValue1（左侧标题 + 右侧详情）
@interface CAAgentStatusValueCell : UITableViewCell
@end

@implementation CAAgentStatusValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

/// 头文件把原包的 NSInteger 参数生成成了 id：同时兼容「原始整数位」与「NSNumber」两种调用
static NSInteger CAAgentStatusSignedArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits < 0x1000) return (NSInteger)bits;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument integerValue];
    if ([argument isKindOfClass:NSString.class]) return [(NSString *)argument integerValue];
    return 0;
}

/// 任何取值都收敛成非空文案（缺失显示「—」，绝不返回 nil）
static NSString *CAAgentStatusDetailText(id value)
{
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return text.length ? text : @"—";
    }
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"—";
}

/// 面板自身计时文案：<1 分钟用「秒」，<1 小时用「分 秒」，其余用「小时 分」
static NSString *CAAgentStatusDurationText(NSTimeInterval interval)
{
    NSInteger seconds = (NSInteger)MAX(interval, 0.0);
    if (seconds < 60) return [NSString stringWithFormat:@"%ld 秒", (long)seconds];
    if (seconds < 3600) return [NSString stringWithFormat:@"%ld 分 %ld 秒", (long)(seconds / 60), (long)(seconds % 60)];
    return [NSString stringWithFormat:@"%ld 小时 %ld 分", (long)(seconds / 3600), (long)((seconds % 3600) / 60)];
}

@interface CAAgentStatusDetailViewController () <UITableViewDataSource, UITableViewDelegate>
{
    NSDictionary *_snapshot;
    UITableView *_tableView;
    NSDate *_openedAt;
    NSDate *_lastRefreshDate;
    NSTimer *_uptimeTimer;
}

- (void)handleClose;
- (void)handleRefresh;
- (NSDictionary *)liveSnapshot;
- (NSArray<NSDictionary *> *)sectionDescriptors;
- (NSString *)uptimeText;
- (NSString *)clockTextForDate:(NSDate *)date;
- (BOOL)snapshotIsRunning;
- (void)logSnapshotSummary;

@end

@implementation CAAgentStatusDetailViewController

#pragma mark - 初始化

- (id)initWithSnapshot:(id)arg1
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _openedAt = [NSDate date];
        _snapshot = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : nil;
    }
    return self;
}

- (instancetype)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _openedAt = [NSDate date];
    }
    return self;
}

- (void)dealloc
{
    [_uptimeTimer invalidate];
    _uptimeTimer = nil;
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    if (!_openedAt) _openedAt = [NSDate date];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 50.0;
    [_tableView registerClass:CAAgentStatusValueCell.class forCellReuseIdentifier:kCAAgentStatusValueCellReuseIdentifier];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(handleClose)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(handleRefresh)];

    [self refreshTitle];

    // 面板自身计时：只刷新运行状态分区，避免整表闪烁
    __weak typeof(self) weakSelf = self;
    _uptimeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!strongSelf.isViewLoaded || strongSelf.view.window == nil) return;
        [strongSelf refreshTitle];
        [strongSelf->_tableView reloadSections:[NSIndexSet indexSetWithIndex:CAAgentStatusSectionRuntime]
                              withRowAnimation:UITableViewRowAnimationNone];
    }];

    CALog(CALogLevelInfo, @"GENERAL", @"agent status detail loaded running=%d", [self snapshotIsRunning] ? 1 : 0);
}

#pragma mark - 交互

- (void)handleClose
{
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleRefresh
{
    // 重新从引擎 + defaults 现场组一份快照
    [self updateSnapshot:[self liveSnapshot]];
    [self logSnapshotSummary];
}

- (void)logSnapshotSummary
{
    CALog(CALogLevelInfo, @"GENERAL", @"agent status detail refreshed state=%@",
          CAAgentStatusDetailText([[self snapshot] objectForKey:kCAAgentStatusSnapshotStateKey]));
}

#pragma mark - 快照

- (NSDictionary *)snapshot
{
    if (![_snapshot isKindOfClass:NSDictionary.class]) {
        _snapshot = [self liveSnapshot];
    }
    return _snapshot;
}

- (void)setSnapshot:(id)arg1
{
    _snapshot = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : nil;
}

- (void)updateSnapshot:(id)arg1
{
    if ([arg1 isKindOfClass:NSDictionary.class]) {
        _snapshot = [(NSDictionary *)arg1 copy];
    } else if (!arg1) {
        _snapshot = [self liveSnapshot];
    }
    [self refreshTitle];
    [_tableView reloadData];
}

- (NSDictionary *)liveSnapshot
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    CACodexEngine *engine = [CACodexEngine sharedEngine];

    BOOL running = NO;
    if ([engine respondsToSelector:@selector(isRunning)]) running = engine.isRunning;
    NSString *state = running ? kCAAgentStatusRawRunning : kCAAgentStatusRawIdle;

    NSString *model = [defaults stringForKey:CADefaultsSelectedModel];
    if (!model.length) model = [defaults stringForKey:CADefaultsActiveModelSlug];
    if (!model.length) model = engine.thirdPartyModel;
    if (!model.length && [engine respondsToSelector:@selector(effectiveModelSlug)]) {
        id slug = [engine effectiveModelSlug];
        model = [slug isKindOfClass:NSString.class] ? (NSString *)slug : nil;
    }
    if (!model.length) model = @"—";

    NSString *effort = [defaults stringForKey:CADefaultsReasoningEffort];
    if (!effort.length) effort = [defaults stringForKey:CADefaultsActiveEffort];
    if (!effort.length) effort = engine.reasoningEffort;
    if (!effort.length) effort = @"medium";

    NSString *workspace = [defaults stringForKey:CADefaultsActiveWorkspace];
    if (!workspace.length) workspace = engine.currentWorkspacePath;
    if (!workspace.length) workspace = @"—";

    NSString *thread = engine.mcpCatalogThreadId;
    if (!thread.length && [engine respondsToSelector:@selector(currentThreadId)]) {
        id threadId = [engine currentThreadId];
        thread = [threadId isKindOfClass:NSString.class] ? (NSString *)threadId : nil;
    }

    // 上下文占用：优先百分比，其次 token 数，都没有就「—」
    NSString *contextText = nil;
    if ([engine respondsToSelector:@selector(contextUsagePercent)] && engine.contextUsagePercent > 0) {
        contextText = [NSString stringWithFormat:@"%lld%%", engine.contextUsagePercent];
    }
    if (!contextText.length && [engine respondsToSelector:@selector(latestContextTokenCount)]) {
        id tokens = [engine latestContextTokenCount];
        if ([tokens isKindOfClass:NSNumber.class] && [(NSNumber *)tokens longLongValue] > 0) {
            contextText = [NSString stringWithFormat:@"%@ tokens", tokens];
        } else if ([tokens respondsToSelector:@selector(length)] && [(NSString *)tokens length] > 0) {
            contextText = (NSString *)tokens;
        }
    }

    return @{
        kCAAgentStatusSnapshotStateKey: state,
        kCAAgentStatusSnapshotModelKey: model,
        kCAAgentStatusSnapshotEffortKey: effort,
        kCAAgentStatusSnapshotWorkspaceKey: workspace,
        kCAAgentStatusSnapshotThreadKey: thread ?: @"",
        kCAAgentStatusSnapshotContextPercentKey: contextText ?: @"",
    };
}

- (BOOL)snapshotIsRunning
{
    NSString *state = CAAgentStatusDetailText([[self snapshot] objectForKey:kCAAgentStatusSnapshotStateKey]);
    return [state isEqualToString:@"运行中"];
}

#pragma mark - 文案

- (void)refreshTitle
{
    _lastRefreshDate = [NSDate date];
    self.title = [self snapshotIsRunning]
        ? [NSString stringWithFormat:@"Agent 状态 · %@", [self clockTextForDate:_lastRefreshDate]]
        : @"Agent 状态";
}

- (id)statusText:(id)arg1
{
    if ([arg1 isKindOfClass:NSNumber.class]) return CAAgentStatusDetailText(arg1);

    NSString *raw = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil;
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return @"—";

    NSString *lower = trimmed.lowercaseString;

    // 运行状态
    if ([lower isEqualToString:kCAAgentStatusRawRunning] ||
        [lower isEqualToString:@"active"] ||
        [lower isEqualToString:@"busy"]) return @"运行中";
    if ([lower isEqualToString:kCAAgentStatusRawIdle] ||
        [lower isEqualToString:@"stopped"] ||
        [lower isEqualToString:@"ready"]) return @"空闲";
    if ([lower isEqualToString:@"paused"]) return @"已暂停";
    if ([lower isEqualToString:@"failed"] || [lower isEqualToString:@"error"]) return @"异常";

    // 推理强度（档位取自 CAThirdPartyModelCatalog，中文名复刻自原包语气）
    static NSDictionary<NSString *, NSString *> *effortTitles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        effortTitles = @{
            @"none":    @"无",
            @"minimal": @"最小",
            @"low":     @"低",
            @"medium":  @"中",
            @"high":    @"高",
            @"xhigh":   @"极高",
            @"max":     @"最大",
            @"ultra":   @"极限",
        };
    });
    NSString *effortTitle = effortTitles[lower];
    if (effortTitle.length) return effortTitle;

    return trimmed;
}

- (NSString *)uptimeText
{
    id provided = [[self snapshot] objectForKey:kCAAgentStatusSnapshotUptimeKey];
    if ([provided isKindOfClass:NSString.class] && [(NSString *)provided length] > 0) return (NSString *)provided;
    NSTimeInterval elapsed = _openedAt ? -[_openedAt timeIntervalSinceNow] : 0.0;
    return CAAgentStatusDurationText(elapsed);
}

- (NSString *)clockTextForDate:(NSDate *)date
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    return [formatter stringFromDate:date ?: [NSDate date]] ?: @"—";
}

#pragma mark - 分区描述

- (NSArray<NSDictionary *> *)sectionDescriptors
{
    NSDictionary *snapshot = [self snapshot];

    NSDictionary *runtimeSection = @{
        kCAAgentStatusSectionTitleKey: @"运行状态",
        kCAAgentStatusSectionRowsKey: @[
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotStateKey,
               kCAAgentStatusRowTitleKey: @"当前状态",
               kCAAgentStatusRowDetailKey: [self statusText:snapshot[kCAAgentStatusSnapshotStateKey]] },
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotUptimeKey,
               kCAAgentStatusRowTitleKey: @"运行时长",
               kCAAgentStatusRowDetailKey: [self uptimeText] },
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotThreadKey,
               kCAAgentStatusRowTitleKey: @"会话线程",
               kCAAgentStatusRowDetailKey: [self statusText:snapshot[kCAAgentStatusSnapshotThreadKey]] },
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotContextPercentKey,
               kCAAgentStatusRowTitleKey: @"上下文占用",
               kCAAgentStatusRowDetailKey: [self statusText:snapshot[kCAAgentStatusSnapshotContextPercentKey]] },
        ],
    };

    NSDictionary *modelSection = @{
        kCAAgentStatusSectionTitleKey: @"模型",
        kCAAgentStatusSectionRowsKey: @[
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotModelKey,
               kCAAgentStatusRowTitleKey: @"当前模型",
               kCAAgentStatusRowDetailKey: [self statusText:snapshot[kCAAgentStatusSnapshotModelKey]] },
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotEffortKey,
               kCAAgentStatusRowTitleKey: @"思考强度",
               kCAAgentStatusRowDetailKey: [self statusText:snapshot[kCAAgentStatusSnapshotEffortKey]] },
        ],
    };

    NSDictionary *workspaceSection = @{
        kCAAgentStatusSectionTitleKey: @"运行环境",
        kCAAgentStatusSectionRowsKey: @[
            @{ kCAAgentStatusRowKeyKey: kCAAgentStatusSnapshotWorkspaceKey,
               kCAAgentStatusRowTitleKey: @"工作区",
               kCAAgentStatusRowDetailKey: [self statusText:snapshot[kCAAgentStatusSnapshotWorkspaceKey]] },
            @{ kCAAgentStatusRowKeyKey: @"refreshedAt",
               kCAAgentStatusRowTitleKey: @"最近刷新",
               kCAAgentStatusRowDetailKey: [self clockTextForDate:_lastRefreshDate] },
        ],
    };

    return @[ runtimeSection, modelSection, workspaceSection ];
}

- (id)sections
{
    return [self sectionDescriptors];
}

#pragma mark - UITableViewDataSource

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)[self sectionDescriptors].count;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = CAAgentStatusSignedArgument(arg2);
    NSArray<NSDictionary *> *sections = [self sectionDescriptors];

    if (section < 0 || (NSUInteger)section >= sections.count) return 0;
    NSArray *rows = sections[(NSUInteger)section][kCAAgentStatusSectionRowsKey];
    return (signed long long)([rows isKindOfClass:NSArray.class] ? rows.count : 0);
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;

    if (!tableView || !indexPath) {
        return [[CAAgentStatusValueCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    }

    CAAgentStatusValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAAgentStatusValueCellReuseIdentifier
                                                                  forIndexPath:indexPath];
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = @"—";
    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSArray<NSDictionary *> *sections = [self sectionDescriptors];
    if (indexPath.section < 0 || (NSUInteger)indexPath.section >= sections.count) return cell;

    NSArray *rows = sections[(NSUInteger)indexPath.section][kCAAgentStatusSectionRowsKey];
    if (![rows isKindOfClass:NSArray.class] || indexPath.row < 0 || (NSUInteger)indexPath.row >= rows.count) return cell;

    NSDictionary *row = [rows[(NSUInteger)indexPath.row] isKindOfClass:NSDictionary.class] ? rows[(NSUInteger)indexPath.row] : nil;
    cell.textLabel.text = CAAgentStatusDetailText(row[kCAAgentStatusRowTitleKey]);
    cell.detailTextLabel.text = CAAgentStatusDetailText(row[kCAAgentStatusRowDetailKey]);

    NSString *key = CAAgentStatusDetailText(row[kCAAgentStatusRowKeyKey]);
    if ([key isEqualToString:kCAAgentStatusSnapshotStateKey]) {
        cell.detailTextLabel.textColor = [self snapshotIsRunning] ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    } else {
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    NSInteger section = CAAgentStatusSignedArgument(arg2);
    NSArray<NSDictionary *> *sections = [self sectionDescriptors];

    if (section < 0 || (NSUInteger)section >= sections.count) return @"";
    return CAAgentStatusDetailText(sections[(NSUInteger)section][kCAAgentStatusSectionTitleKey]);
}

@end
