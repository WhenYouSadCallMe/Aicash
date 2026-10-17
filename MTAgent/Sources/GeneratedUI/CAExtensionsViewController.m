//
//  CAExtensionsViewController — 「Skills 与扩展」入口页
//
//  原包对应入口：设置 → 开发环境与诊断 → 「Skills 与扩展」（右值「指令、Skills、提示词与插件」）。
//  四类入口分别跳到 CAExtensionListViewController（skill / plugin / mcp / prompt / memory），
//  「全局指令」行直接编辑 <codexHome>/AGENTS.md（原包的全局指令文件）。
//  真实数据来源：CAComposerCatalog.sharedCatalog.items（计数）+ 磁盘上的 AGENTS.md（状态）。
//

#import "CAExtensionsViewController.h"
#import "CAComposerCatalog.h"
#import "CARuntimePaths.h"
#import "CACommon.h"
#import "CAExtensionListViewController.h"
#import "CAProjectInstructionsViewController.h"
#import "CATextEditorViewController.h"

static NSString * const kCAExtensionsCellIdentifier = @"CAExtensionsCell";

/// 统一使用 UITableViewCellStyleSubtitle（标题 + 副标题），写法与 CASettingsViewController 的 CASettingsValueCell 一致。
@interface CAExtensionsValueCell : UITableViewCell
@end

@implementation CAExtensionsValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}

@end

@interface CAExtensionsViewController () <UITableViewDataSource, UITableViewDelegate>
{
    NSDictionary *_instructionStatus;      // -instructionStatus / -setInstructionStatus: 的真实存储
    BOOL _seedingGlobalInstruction;        // -seedingGlobalInstruction / -setSeedingGlobalInstruction:
    unsigned long long _statusGeneration;  // -statusGeneration / -setStatusGeneration:（代际校验）
    UITableView *_tableView;
    UIRefreshControl *_refreshControl;
    BOOL _observerInstalled;
}

#pragma mark - 私有辅助（工具方法，不属于原包选择器）

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath;
- (void)handleClose;
- (void)catalogDidChangeNotification:(NSNotification *)notification;
- (void)endRefreshing;
- (NSString *)instructionStatusSummary;
- (NSUInteger)countOfKind:(CAComposerCatalogKind)kind enabledOnly:(BOOL)enabledOnly;

@end

@implementation CAExtensionsViewController

#pragma mark - 目录变化

- (void)catalogDidChange
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self catalogDidChange];
        });
        return;
    }
    // 目录变化会影响各分类计数，「全局指令」状态顺带校准一次
    [self loadInstructionStatus];
    [_tableView reloadData];
}

- (void)catalogDidChangeNotification:(NSNotification *)notification
{
    [self catalogDidChange];
}

#pragma mark - 路径

- (id)codexHome
{
    return [CARuntimePaths codexHome];
}

- (id)workspace
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *workspace = [defaults stringForKey:CADefaultsActiveWorkspace];
    if (workspace.length) return workspace;
    return [CARuntimePaths documentsCodexDirectory];
}

#pragma mark - 全局指令

- (void)ensureGlobalInstructionSeeded
{
    // 复刻兜底：原包装机自带 AGENTS.md，本复刻首次启动时按模板生成一份
    if (_seedingGlobalInstruction) return;   // 防重入

    NSString *path = [self globalInstructionPath];
    if (!path.length) return;

    NSString *existing = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    BOOL needsSeed = (existing.length == 0);
    if (!needsSeed) {
        NSCharacterSet *trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        NSString *trimmed = [existing stringByTrimmingCharactersInSet:trimSet];
        NSString *legacy = [[self legacyGlobalInstructionTemplate] stringByTrimmingCharactersInSet:trimSet];
        needsSeed = (trimmed.length == 0) || [trimmed isEqualToString:legacy];
    }
    if (!needsSeed) return;

    [self setSeedingGlobalInstruction:@YES];
    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    NSString *template = [self globalInstructionTemplate];
    BOOL ok = [template writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"GENERAL", @"global instruction seeded=%d path=%@ error=%@",
          ok ? 1 : 0, path, error.localizedDescription ?: @"(none)");
    [self setSeedingGlobalInstruction:@NO];

    [self loadInstructionStatus];
}

- (id)globalInstructionPath
{
    NSString *home = [self codexHome];
    if (!home.length) return nil;
    // 原包全局指令文件名即 AGENTS.md（见代码内 AGENTS.md / AGENTS.override.md 常量）
    return [home stringByAppendingPathComponent:@"AGENTS.md"];
}

- (id)globalInstructionTemplate
{
    return @"# 全局指令\n\n- 用简体中文回复。\n- 需要多步操作时先给计划。\n";
}

- (id)globalOutputInstructionBlock
{
    return @"输出保持简洁，不要复述代码。\n";
}

- (id)globalSubagentInstructionBlock
{
    return @"子代理只做被指派的分析，不要改动无关文件。\n";
}

- (id)legacyGlobalInstructionTemplate
{
    // 老版本默认模板：仅用于识别历史文件，命中即视为需要重新播种
    return @"You are a helpful coding agent.\n";
}

- (void)loadInstructionStatus
{
    // 代际校验：快速切换页面时旧结果不覆盖新结果
    [self setStatusGeneration:@(_statusGeneration + 1)];
    unsigned long long generation = _statusGeneration;

    NSString *path = [self globalInstructionPath];
    NSString *outputBlock = [self globalOutputInstructionBlock];
    NSString *subagentBlock = [self globalSubagentInstructionBlock];
    NSString *legacyTemplate = [self legacyGlobalInstructionTemplate];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *text = path.length ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
        BOOL exists = (text != nil) || (path.length && [NSFileManager.defaultManager fileExistsAtPath:path]);
        if (!text) text = @"";

        NSCharacterSet *trimSet = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        NSString *trimmed = [text stringByTrimmingCharactersInSet:trimSet];
        NSDictionary *status = @{
            @"path": path ?: @"",
            @"exists": @(exists),
            @"bytes": @([text dataUsingEncoding:NSUTF8StringEncoding].length),
            @"hasOutput": @(outputBlock.length && [text containsString:outputBlock]),
            @"hasSubagent": @(subagentBlock.length && [text containsString:subagentBlock]),
            @"legacy": @(trimmed.length > 0 && [trimmed isEqualToString:[legacyTemplate stringByTrimmingCharactersInSet:trimSet]]),
        };

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (generation != strongSelf->_statusGeneration) return;   // 过期结果丢弃
            [strongSelf setInstructionStatus:status];
            [strongSelf->_tableView reloadData];
        });
    });
}

#pragma mark - 入口行

- (id)extensionRows
{
    NSDictionary *status = _instructionStatus ?: @{};
    NSString *instructionDetail = nil;
    if ([status[@"exists"] boolValue]) {
        instructionDetail = [NSString stringWithFormat:@"AGENTS.md · %@ 字节%@",
                             status[@"bytes"] ?: @0,
                             [status[@"legacy"] boolValue] ? @" · 仍是旧版模板" : @""];
    } else {
        instructionDetail = @"AGENTS.md · 未创建，点击生成模板";
    }

    NSUInteger skillTotal = [self countOfKind:CAComposerCatalogKindSkill enabledOnly:NO];
    NSUInteger skillEnabled = [self countOfKind:CAComposerCatalogKindSkill enabledOnly:YES];
    NSUInteger pluginTotal = [self countOfKind:CAComposerCatalogKindPlugin enabledOnly:NO];
    NSUInteger mcpTotal = [self countOfKind:CAComposerCatalogKindMCP enabledOnly:NO];
    NSUInteger promptTotal = [self countOfKind:CAComposerCatalogKindPrompt enabledOnly:NO];

    return @[
        @{ @"title": @"Skills",
           @"detail": [NSString stringWithFormat:@"本地技能 %lu 个 · 已启用 %lu 个",
                       (unsigned long)skillTotal, (unsigned long)skillEnabled],
           @"symbol": @"sparkles",
           @"kind": @"skill" },
        @{ @"title": @"插件",
           @"detail": [NSString stringWithFormat:@"插件 %lu 个 · ~/.codex/plugins", (unsigned long)pluginTotal],
           @"symbol": @"shippingbox",
           @"kind": @"plugin" },
        @{ @"title": @"MCP 服务",
           @"detail": [NSString stringWithFormat:@"config.toml 中 %lu 个服务", (unsigned long)mcpTotal],
           @"symbol": @"server.rack",
           @"kind": @"mcp" },
        @{ @"title": @"全局指令",
           @"detail": instructionDetail,
           @"symbol": @"text.badge.plus",
           @"kind": @"instruction" },
        @{ @"title": @"提示词",
           @"detail": [NSString stringWithFormat:@"提示词 %lu 条 · ~/.codex/prompts", (unsigned long)promptTotal],
           @"symbol": @"text.quote",
           @"kind": @"prompt" },
        @{ @"title": @"项目指令",
           @"detail": @"每个工作区各自的 AGENTS.md",
           @"symbol": @"doc.text",
           @"kind": @"projectinstructions" },
    ];
}

#pragma mark - 全局指令编辑

- (void)openInstructionAtPath:(id)arg1 title:(id)arg2 note:(id)arg3 template:(id)arg4
{
    NSString *path = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [self globalInstructionPath];
    NSString *editorTitle = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : @"全局指令";
    NSString *note = [arg3 isKindOfClass:NSString.class] ? (NSString *)arg3 : @"";
    NSString *template = [arg4 isKindOfClass:NSString.class] ? (NSString *)arg4 : [self globalInstructionTemplate];
    if (!path.length) return;

    __weak typeof(self) weakSelf = self;
    CATextEditorViewController *editor = [[CATextEditorViewController alloc] initWithTitle:editorTitle
                                                                                    path:path
                                                                                template:template
                                                                                editable:@YES];
    [editor setOnSaved:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        // 保存后重新统计字节数与两个附加指令块是否命中
        CALog(CALogLevelInfo, @"GENERAL", @"global instruction saved note=%@ path=%@", note, path);
        [strongSelf loadInstructionStatus];
    }];

    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    [self presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - 刷新

- (void)pullToRefresh
{
    [self refreshForce:@NO];
}

- (void)refreshForce:(id)arg1
{
    // arg1 为原包占位形参（id）：@YES 强制刷新，其余值走普通刷新
    BOOL force = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    __weak typeof(self) weakSelf = self;
    [[CAComposerCatalog sharedCatalog] refreshForWorkspace:[self workspace] force:force completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"extensions refresh failed: %@", error.localizedDescription ?: @"未知错误");
            }
            [strongSelf endRefreshing];
            [strongSelf loadInstructionStatus];
            [strongSelf->_tableView reloadData];
        });
    }];
}

#pragma mark - getter / setter

- (NSDictionary *)instructionStatus
{
    return _instructionStatus;
}

- (void)setInstructionStatus:(id)arg1
{
    _instructionStatus = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : @{};
}

- (bool)seedingGlobalInstruction
{
    return _seedingGlobalInstruction;
}

- (void)setSeedingGlobalInstruction:(id)arg1
{
    _seedingGlobalInstruction = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (unsigned long long)statusGeneration
{
    return _statusGeneration;
}

- (void)setStatusGeneration:(id)arg1
{
    _statusGeneration = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (void)setTableView:(id)arg1
{
    _tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
}

- (UITableView *)tableView
{
    return _tableView;
}

#pragma mark - UITableViewDataSource

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return 1;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    return (signed long long)[[self extensionRows] count];
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return nil;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAExtensionsCellIdentifier forIndexPath:indexPath];
    NSDictionary *row = [self rowAtIndexPath:indexPath];
    if (!row) return cell;

    cell.textLabel.text = row[@"title"];
    cell.detailTextLabel.text = row[@"detail"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:row[@"symbol"]];
    cell.imageView.tintColor = UIColor.systemBlueColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (tableView && indexPath) [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *row = [self rowAtIndexPath:indexPath];
    NSString *kind = [row[@"kind"] isKindOfClass:NSString.class] ? row[@"kind"] : nil;
    if (!kind.length) return;

    if ([kind isEqualToString:@"instruction"]) {
        [self openInstructionAtPath:[self globalInstructionPath]
                              title:@"全局指令"
                               note:@"AGENTS.md · 对所有会话生效"
                           template:[self globalInstructionTemplate]];
        return;
    }

    if ([kind isEqualToString:@"projectinstructions"]) {
        // 项目指令：每个工作区各自的 AGENTS.md（复刻补全面板入口）
        CAProjectInstructionsViewController *instructions = [[CAProjectInstructionsViewController alloc] init];
        UINavigationController *navigation = self.navigationController;
        if (navigation) {
            [navigation pushViewController:instructions animated:YES];
        } else {
            [self presentViewController:[[UINavigationController alloc] initWithRootViewController:instructions] animated:YES completion:nil];
        }
        return;
    }

    // skill / plugin / mcp / prompt / memory → 分组列表
    CAExtensionListViewController *list = [[CAExtensionListViewController alloc] initWithKind:kind];
    UINavigationController *navigation = self.navigationController;
    if (navigation) {
        [navigation pushViewController:list animated:YES];
    } else {
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:list] animated:YES completion:nil];
    }
}

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    return @"Skills 与扩展";
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    if (section != 0) return nil;
    // 原版页脚：说明可直接在输入框用 / 选用这些内容
    NSString *summary = [self instructionStatusSummary] ?: @"";
    return [NSString stringWithFormat:@"%@\n在输入框键入 / 可以直接选用这些内容。", summary];
}

#pragma mark - 主题

- (void)themeDidChange
{
    // 系统语义色：浅色 / 深色自动跟随
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.separatorColor = UIColor.separatorColor;
    [_tableView reloadData];
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Skills 与扩展";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:CAExtensionsValueCell.class forCellReuseIdentifier:kCAExtensionsCellIdentifier];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    _refreshControl = [[UIRefreshControl alloc] init];
    _refreshControl.tintColor = UIColor.secondaryLabelColor;
    [_refreshControl addTarget:self action:@selector(pullToRefresh) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(handleClose)];

    if (!_observerInstalled) {
        _observerInstalled = YES;
        // 原包通知名即 CAComposerCatalog.h 里导出的 CAComposerCatalogDidChangeNotification
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(catalogDidChangeNotification:)
                                                     name:CAComposerCatalogDidChangeNotification
                                                   object:nil];
    }

    [self themeDidChange];
    [self ensureGlobalInstructionSeeded];
    [self loadInstructionStatus];
    [self refreshForce:@YES];
}

- (void)viewWillAppear:(id)arg1
{
    BOOL animated = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    [super viewWillAppear:animated];
    [self loadInstructionStatus];
}

#pragma mark - 私有辅助实现

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!indexPath) return nil;
    NSArray *rows = [self extensionRows];
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= rows.count) return nil;
    id row = rows[(NSUInteger)indexPath.row];
    return [row isKindOfClass:NSDictionary.class] ? (NSDictionary *)row : nil;
}

- (NSUInteger)countOfKind:(CAComposerCatalogKind)kind enabledOnly:(BOOL)enabledOnly
{
    NSUInteger count = 0;
    for (id raw in [CAComposerCatalog sharedCatalog].items) {
        if (![raw isKindOfClass:CAComposerCatalogItem.class]) continue;
        CAComposerCatalogItem *item = (CAComposerCatalogItem *)raw;
        if (item.kind != kind) continue;
        if (enabledOnly && !item.enabled) continue;
        count += 1;
    }
    return count;
}

- (NSString *)instructionStatusSummary
{
    NSString *path = [self globalInstructionPath] ?: @"(未知路径)";
    NSDictionary *status = _instructionStatus;
    if (!status.count) {
        return [NSString stringWithFormat:@"%@", path];
    }
    if (![status[@"exists"] boolValue]) {
        return [NSString stringWithFormat:@"%@\n尚未创建：点「全局指令」会按模板生成。", path];
    }

    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    [flags addObject:[NSString stringWithFormat:@"%@ 字节", status[@"bytes"] ?: @0]];
    if ([status[@"legacy"] boolValue]) [flags addObject:@"仍是旧版模板"];
    [flags addObject:[status[@"hasOutput"] boolValue] ? @"含输出约束" : @"无输出约束"];
    [flags addObject:[status[@"hasSubagent"] boolValue] ? @"含子代理约束" : @"无子代理约束"];
    return [NSString stringWithFormat:@"%@\n%@", path, [flags componentsJoinedByString:@" · "]];
}

- (void)handleClose
{
    UINavigationController *navigation = self.navigationController;
    if (navigation && navigation.viewControllers.firstObject != self) {
        [navigation popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)endRefreshing
{
    [_refreshControl endRefreshing];
}

@end
