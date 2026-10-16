//
//  CAProjectInstructionsViewController.m — 项目指令（AGENTS.md）管理（真实界面实现）
//
//  数据来源：
//    · defaults CodexSavedWorkspaces（已保存工作区路径数组）
//    · defaults CodexActiveWorkspace（当前工作区路径，优先展示在「当前工作区」分组）
//    · 每个工作区的项目指令文件是 <workspace>/AGENTS.md
//  编辑入口：CATextEditorViewController（initWithTitle:path:template:editable:）
//
//  头文件的选择器参数类型统一是占位 id；实现逐字沿用该签名，函数体第一行局部强转后使用。
//

#import "CAProjectInstructionsViewController.h"
#import "CATextEditorViewController.h"
#import "CACommon.h"
#import "CALogger.h"

#pragma mark - 文件内工具（静态函数：不为面板新增选择器）

/// 项目指令兜底模板（文件不存在或为空时预填）
static NSString * const kCAPIInstructionsTemplate = @"# 项目指令\n\n- 用中文回复。\n- 改动前先读现有实现。\n";

/// id 占位参数 → BOOL（头文件里真实语义多为 bool）
static BOOL CAPIBool(id value)
{
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [(NSNumber *)value boolValue];
    }
    return value != nil;
}

/// 当前工作区路径（defaults CodexActiveWorkspace）
static NSString *CAPIActiveWorkspacePath(void)
{
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace];
    return [path isKindOfClass:NSString.class] ? [path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
}

/// 分组切片：0 = 当前工作区，1 = 其他工作区
static NSArray<NSString *> *CAPIWorkspacesForSection(NSArray<NSString *> *workspaces, NSInteger section)
{
    NSString *active = CAPIActiveWorkspacePath();
    if (section == 0) {
        return (active.length > 0 && [workspaces containsObject:active]) ? @[ active ] : @[];
    }

    NSMutableArray<NSString *> *others = [NSMutableArray array];
    for (NSString *path in workspaces) {
        if (active.length > 0 && [path isEqualToString:active]) continue;
        [others addObject:path];
    }
    return others;
}

/// 文件大小文案
static NSString *CAPISizeText(unsigned long long bytes)
{
    if (bytes < 1024ULL) {
        return [NSString stringWithFormat:@"%llu 字节", bytes];
    }
    if (bytes < 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.1f KB", (double)bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
}

#pragma mark - 面板

@interface CAProjectInstructionsViewController () <UITableViewDataSource, UITableViewDelegate>
{
    NSDictionary *_statusByPath;            // AGENTS.md 绝对路径 → @{ exists, size, modified }
    unsigned long long _statusGeneration;   // 代际校验：切换工作区后丢弃过期结果
    UITableView *_tableView;
    NSArray *_workspaces;                   // 已排序、去重的工作区路径

    UILabel *_emptyLabel;
}

- (void)handleClose;
- (signed long long)numberOfSectionsInTableView:(id)arg1;

@end

@implementation CAProjectInstructionsViewController

#pragma mark - 访问器（头文件里声明的选择器）

- (id)instructionPathForWorkspace:(id)arg1
{
    if (![arg1 isKindOfClass:NSString.class]) return nil;
    NSString *workspace = [(NSString *)arg1 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (workspace.length == 0) return nil;
    if ([workspace hasPrefix:@"~"]) {
        workspace = [workspace stringByExpandingTildeInPath];
    }
    return [workspace stringByAppendingPathComponent:@"AGENTS.md"];
}

- (void)reloadStatuses
{
    NSArray<NSString *> *paths = self.workspaces ?: @[];
    NSMutableArray<NSString *> *instructionPaths = [NSMutableArray array];
    for (NSString *workspace in paths) {
        NSString *instructionPath = (NSString *)[self instructionPathForWorkspace:workspace];
        if (instructionPath.length > 0) [instructionPaths addObject:instructionPath];
    }

    unsigned long long generation = _statusGeneration + 1;
    _statusGeneration = generation;

    if (instructionPaths.count == 0) {
        self.statusByPath = @{};
        _emptyLabel.hidden = (paths.count > 0);
        [_tableView reloadData];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSMutableDictionary *statuses = [NSMutableDictionary dictionary];
        for (NSString *path in instructionPaths) {
            NSError *error = nil;
            NSDictionary *attributes = [manager attributesOfItemAtPath:path error:&error];
            if (attributes) {
                statuses[path] = @{
                    @"exists": @YES,
                    @"size": @([attributes[NSFileSize] unsignedLongLongValue]),
                    @"modified": attributes[NSFileModificationDate] ?: [NSDate date],
                };
            } else {
                statuses[path] = @{ @"exists": @NO };
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            // 代际校验：期间又触发了新的读取就丢弃本次结果
            if (generation != strongSelf.statusGeneration) return;
            strongSelf.statusByPath = statuses;
            strongSelf->_emptyLabel.hidden = (paths.count > 0);
            [strongSelf->_tableView reloadData];
        });
    });
}

- (void)setStatusByPath:(id)arg1
{
    _statusByPath = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : @{};
}

- (void)setStatusGeneration:(id)arg1
{
    _statusGeneration = [arg1 respondsToSelector:@selector(unsignedLongLongValue)]
        ? [(NSNumber *)arg1 unsignedLongLongValue]
        : 0;
}

- (void)setTableView:(id)arg1
{
    _tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
}

- (void)setWorkspaces:(id)arg1
{
    _workspaces = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : @[];
}

- (NSDictionary *)statusByPath
{
    return _statusByPath ?: @{};
}

- (unsigned long long)statusGeneration
{
    return _statusGeneration;
}

- (UITableView *)tableView
{
    return _tableView;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return nil;

    static NSString * const identifier = @"CAProjectInstructionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }

    NSArray<NSString *> *rows = CAPIWorkspacesForSection(self.workspaces, indexPath.section);
    if ((NSUInteger)indexPath.row >= rows.count) return cell;

    NSString *workspace = rows[(NSUInteger)indexPath.row];
    NSString *instructionPath = (NSString *)[self instructionPathForWorkspace:workspace];
    NSDictionary *status = instructionPath.length > 0 ? self.statusByPath[instructionPath] : nil;
    BOOL exists = CAPIBool(status[@"exists"]);

    cell.textLabel.text = workspace.lastPathComponent.length > 0 ? workspace.lastPathComponent : workspace;
    cell.detailTextLabel.text = instructionPath ?: @"";

    NSString *statusText = nil;
    UIColor *statusColor = UIColor.secondaryLabelColor;
    if (exists) {
        unsigned long long size = [status[@"size"] respondsToSelector:@selector(unsignedLongLongValue)]
            ? [(NSNumber *)status[@"size"] unsignedLongLongValue]
            : 0;
        statusText = [NSString stringWithFormat:@"%@ · 已生效", CAPISizeText(size)];
        statusColor = UIColor.systemGreenColor;
    } else {
        statusText = @"未创建";
    }

    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    statusLabel.textColor = statusColor;
    statusLabel.textAlignment = NSTextAlignmentRight;
    statusLabel.text = statusText;
    [statusLabel sizeToFit];
    statusLabel.frame = CGRectMake(0.0, 0.0, MAX(CGRectGetWidth(statusLabel.frame), 108.0), 24.0);
    cell.accessoryView = statusLabel;

    return cell;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSArray<NSString *> *rows = CAPIWorkspacesForSection(self.workspaces, indexPath.section);
    if ((NSUInteger)indexPath.row >= rows.count) return;

    NSString *workspace = rows[(NSUInteger)indexPath.row];
    NSString *instructionPath = (NSString *)[self instructionPathForWorkspace:workspace];
    if (instructionPath.length == 0) return;

    CATextEditorViewController *editor = [[CATextEditorViewController alloc] initWithTitle:@"项目指令"
                                                                                     path:instructionPath
                                                                                 template:kCAPIInstructionsTemplate
                                                                                 editable:@YES];
    __weak typeof(self) weakSelf = self;
    [editor setOnSaved:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf reloadStatuses];
    }];

    UINavigationController *navigation = self.navigationController;
    if (navigation) {
        [navigation pushViewController:editor animated:YES];
    } else {
        UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:editor];
        wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:wrapper animated:YES completion:nil];
    }
    CALog(CALogLevelInfo, @"GENERAL", @"project instructions editing path=%@", instructionPath);
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    if (![arg2 respondsToSelector:@selector(integerValue)]) return 0;
    NSInteger section = [(NSNumber *)arg2 integerValue];
    return (signed long long)CAPIWorkspacesForSection(self.workspaces, section).count;
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    if (![arg2 respondsToSelector:@selector(integerValue)]) return nil;
    NSInteger section = [(NSNumber *)arg2 integerValue];
    if (section != 1) return nil;
    return @"项目指令会随每次会话注入 codex，仅对对应工作区生效。";
}

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    if (![arg2 respondsToSelector:@selector(integerValue)]) return nil;
    NSInteger section = [(NSNumber *)arg2 integerValue];
    return (section == 0) ? @"当前工作区" : @"其他工作区";
}

- (void)themeDidChange
{
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    [_tableView reloadData];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"项目指令";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"还没有工作区。先在会话页选择一个目录，之后就能在这里维护 AGENTS.md。";
    _emptyLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 64.0;
    _tableView.backgroundView = _emptyLabel;
    [self.view addSubview:_tableView];

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(handleClose)];
    self.navigationItem.rightBarButtonItem = done;

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:@"CAThemeDidChangeNotification"
                                               object:nil];

    CALog(CALogLevelDebug, @"GENERAL", @"project instructions loaded workspaces=%lu",
          (unsigned long)self.workspaces.count);
}

- (void)viewWillAppear:(id)arg1
{
    [super viewWillAppear:CAPIBool(arg1)];
    [self reloadStatuses];
    [_tableView reloadData];
}

- (NSArray *)workspaces
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *active = CAPIActiveWorkspacePath();
    if (active.length > 0) {
        [paths addObject:active];
    }

    NSArray *saved = [NSUserDefaults.standardUserDefaults arrayForKey:CADefaultsSavedWorkspaces];
    if ([saved isKindOfClass:NSArray.class]) {
        for (id item in saved) {
            if (![item isKindOfClass:NSString.class]) continue;
            NSString *path = [(NSString *)item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (path.length == 0) continue;
            if ([paths containsObject:path]) continue;
            [paths addObject:path];
        }
    }

    NSArray<NSString *> *sorted = [paths sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    _workspaces = sorted;
    return sorted;
}

#pragma mark - 私有方法

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return 2;
}

- (void)handleClose
{
    UINavigationController *navigation = self.navigationController;
    if (navigation && navigation.viewControllers.count > 1) {
        [navigation popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
