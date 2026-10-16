//
//  CAConversationSidebarViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：会话侧栏（按工作区分组列出会话；点击切换；滑动重命名 / 删除 / 移动到工作区）。
//  数据全部来自 CAConversationStore；操作完成后回调 delegate（CAChatViewController）。
//  delegate 是 id（原包选择器），所以这里用 respondsToSelector: 做可选回调。
//

#import "CAConversationSidebarViewController.h"
#import "CAConversationStore.h"
#import "CAConversationCell.h"
#import "CARuntimePaths.h"
#import "CACommon.h"
#import "CALogger.h"

/// 侧栏 → 宿主（CAChatViewController）的非正式回调协议。
/// 侧栏不 import 宿主头文件（避免循环依赖），因此这里用 @optional 协议声明回调形状。
@protocol CAChatSidebarCallbacks <NSObject>
@optional
- (void)conversationSidebar:(id)sidebar didSelectRecord:(id)record;
- (void)conversationSidebar:(id)sidebar didDeleteRecord:(id)record;
- (void)conversationSidebar:(id)sidebar didRenameRecord:(id)record title:(id)title;
- (void)conversationSidebar:(id)sidebar didMoveRecord:(id)record toWorkspace:(id)workspace;
- (void)conversationSidebar:(id)sidebar didRequestNewConversationForWorkspace:(id)workspace;
- (void)conversationSidebar:(id)sidebar didRequestPermanentDeleteWorkspaceAtPath:(id)path;
- (void)conversationSidebarDidRequestClose:(id)sidebar;
- (void)conversationSidebarDidRequestNewConversation:(id)sidebar;
- (void)conversationSidebarDidRequestSettings:(id)sidebar;
- (void)conversationSidebarDidRequestUsage:(id)sidebar;
- (void)conversationSidebarDidRequestWorkspaces:(id)sidebar;
@end

@interface CAConversationSidebarViewController () {
    NSArray<CAConversationRecord *> *_records;
    NSString *_activeConversationId;
    NSString *_workspacePath;
    __weak id _delegate;
    BOOL _compactLayout;
    BOOL _refreshingQuota;
    NSMutableSet *_expandedWorkspacePaths;
    NSArray *_sectionWorkspaces;
    NSDictionary *_countsByWorkspace;
    NSDictionary *_recordsByWorkspace;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *sidebarHeader;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *composeButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) NSLayoutConstraint *headerHeight;
@property (nonatomic, strong) NSLayoutConstraint *composeHeight;
@property (nonatomic, strong) NSLayoutConstraint *workspaceHeight;
@end

@implementation CAConversationSidebarViewController

#pragma mark - 生命周期

- (instancetype)init
{
    if ((self = [super init])) {
        _workspacePath = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace];
        if (_workspacePath.length == 0) _workspacePath = CARuntimePaths.documentsCodexDirectory;
        _records = @[];
        _expandedWorkspacePaths = [NSMutableSet set];
        _sectionWorkspaces = @[];
        _countsByWorkspace = @{};
        _recordsByWorkspace = @{};
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"会话";
    self.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self buildHeader];
    [self buildTable];
    [self reloadConversations];
}

- (void)viewDidAppear:(id)arg1
{
    [super viewDidAppear:[arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES];
    [self reloadConversations];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self applyResponsiveLayout];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 界面

- (void)buildHeader
{
    _sidebarHeader = [[UIView alloc] init];
    _sidebarHeader.translatesAutoresizingMaskIntoConstraints = NO;
    _sidebarHeader.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:_sidebarHeader];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"会话";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [_sidebarHeader addSubview:title];

    _composeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _composeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_composeButton setImage:[UIImage systemImageNamed:@"square.and.pencil"] forState:UIControlStateNormal];
    [_composeButton addTarget:self action:@selector(createConversation) forControlEvents:UIControlEventTouchUpInside];
    [_sidebarHeader addSubview:_composeButton];

    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsButton setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    [_settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [_sidebarHeader addSubview:_settingsButton];

    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.text = @"当前工作区还没有会话\n点右上角新建一个";
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    _headerHeight = [_sidebarHeader.heightAnchor constraintEqualToConstant:52.0];
    [NSLayoutConstraint activateConstraints:@[
        [_sidebarHeader.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_sidebarHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_sidebarHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _headerHeight,

        [title.leadingAnchor constraintEqualToAnchor:_sidebarHeader.leadingAnchor constant:16.0],
        [title.centerYAnchor constraintEqualToAnchor:_sidebarHeader.centerYAnchor],

        [_composeButton.trailingAnchor constraintEqualToAnchor:_sidebarHeader.trailingAnchor constant:-12.0],
        [_composeButton.centerYAnchor constraintEqualToAnchor:_sidebarHeader.centerYAnchor],
        [_composeButton.widthAnchor constraintEqualToConstant:32.0],
        [_composeButton.heightAnchor constraintEqualToConstant:32.0],

        [_settingsButton.trailingAnchor constraintEqualToAnchor:_composeButton.leadingAnchor constant:-6.0],
        [_settingsButton.centerYAnchor constraintEqualToAnchor:_sidebarHeader.centerYAnchor],
        [_settingsButton.widthAnchor constraintEqualToConstant:32.0],
        [_settingsButton.heightAnchor constraintEqualToConstant:32.0],
    ]];
}

- (void)buildTable
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 56.0;
    [_tableView registerClass:CAConversationCell.class forCellReuseIdentifier:@"CAConversationCell"];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_sidebarHeader.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
    ]];
}

- (void)applyResponsiveLayout
{
    _compactLayout = self.view.bounds.size.width < 300.0;
    _headerHeight.constant = _compactLayout ? 46.0 : 52.0;
}

#pragma mark - 数据

- (NSString *)workspacePath
{
    if (_workspacePath.length == 0) {
        _workspacePath = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace];
        if (_workspacePath.length == 0) _workspacePath = CARuntimePaths.documentsCodexDirectory;
    }
    return _workspacePath;
}

- (void)setWorkspacePath:(id)arg1
{
    NSString *workspace = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    if (workspace.length == 0) return;
    _workspacePath = workspace;
    [self reloadConversations];
}

- (NSString *)activeConversationId
{
    return [[CAConversationStore sharedStore] activeConversationIdForWorkspace:self.workspacePath];
}

- (void)setActiveConversationId:(id)arg1
{
    _activeConversationId = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil;
}

- (void)reloadConversations
{
    CAConversationStore *store = [CAConversationStore sharedStore];
    _records = [store loadRecordsForWorkspace:self.workspacePath] ?: @[];
    _activeConversationId = [store activeConversationIdForWorkspace:self.workspacePath];

    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    counts[self.workspacePath ?: @""] = @(_records.count);
    _countsByWorkspace = counts;
    _recordsByWorkspace = @{ self.workspacePath ?: @"" : _records };
    _sectionWorkspaces = @[ self.workspacePath ?: @"" ];

    self.emptyLabel.hidden = (_records.count > 0);
    [self.tableView reloadData];
    CALog(CALogLevelDebug, @"CHAT", @"sidebar reloaded workspace=%@ records=%lu",
          self.workspacePath, (unsigned long)_records.count);
}

- (id)recordAtIndexPath:(id)arg1
{
    NSIndexPath *indexPath = [arg1 isKindOfClass:NSIndexPath.class] ? arg1 : nil;
    if (!indexPath) return nil;
    if ((NSUInteger)indexPath.row >= _records.count) return nil;
    return _records[(NSUInteger)indexPath.row];
}

- (NSDictionary *)countsByWorkspace
{
    return _countsByWorkspace ?: @{};
}

- (void)setCountsByWorkspace:(id)arg1
{
    _countsByWorkspace = [arg1 isKindOfClass:NSDictionary.class] ? arg1 : @{};
}

- (NSDictionary *)recordsByWorkspace
{
    return _recordsByWorkspace ?: @{};
}

- (void)setRecordsByWorkspace:(id)arg1
{
    _recordsByWorkspace = [arg1 isKindOfClass:NSDictionary.class] ? arg1 : @{};
}

- (NSArray *)sectionWorkspaces
{
    return _sectionWorkspaces ?: @[];
}

- (void)setSectionWorkspaces:(id)arg1
{
    _sectionWorkspaces = [arg1 isKindOfClass:NSArray.class] ? arg1 : @[];
}

- (NSMutableSet *)expandedWorkspacePaths
{
    return _expandedWorkspacePaths;
}

- (void)setExpandedWorkspacePaths:(id)arg1
{
    _expandedWorkspacePaths = [arg1 isKindOfClass:NSMutableSet.class] ? arg1 : [NSMutableSet set];
}

- (bool)compactLayout { return _compactLayout; }

- (void)setCompactLayout:(id)arg1
{
    _compactLayout = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)refreshingQuota { return _refreshingQuota; }

- (void)setRefreshingQuota:(id)arg1
{
    _refreshingQuota = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (id)delegate { return _delegate; }

- (void)setDelegate:(id)arg1
{
    _delegate = arg1;
}

/// 回调宿主（弱引用）；用协议类型承接，避免 import 宿主头文件
- (id<CAChatSidebarCallbacks>)sidebarDelegate
{
    return (id<CAChatSidebarCallbacks>)_delegate;
}

#pragma mark - 会话操作

- (void)createConversation
{
    CAConversationStore *store = [CAConversationStore sharedStore];
    CAConversationRecord *record = [store createConversationForWorkspace:self.workspacePath];
    [self reloadConversations];
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebarDidRequestNewConversation:)]) {
        [[self sidebarDelegate] conversationSidebarDidRequestNewConversation:self];
    }
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebar:didSelectRecord:)]) {
        [[self sidebarDelegate] conversationSidebar:self didSelectRecord:record];
    }
}

- (void)newConversationForWorkspacePath:(id)arg1
{
    NSString *workspace = [arg1 isKindOfClass:NSString.class] ? arg1 : self.workspacePath;
    if (workspace.length > 0) _workspacePath = workspace;
    [self createConversation];
}

- (void)renameRecord:(id)arg1
{
    CAConversationRecord *record = [arg1 isKindOfClass:CAConversationRecord.class] ? arg1 : nil;
    if (!record) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名会话"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = record.title ?: @"";
        textField.placeholder = @"会话标题";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *title = alert.textFields.firstObject.text;
        title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        record.title = title ?: @"";
        record.updatedAt = [NSDate date];
        [[CAConversationStore sharedStore] saveRecord:record];
        [strongSelf reloadConversations];
        if ([strongSelf.delegate respondsToSelector:@selector(conversationSidebar:didRenameRecord:title:)]) {
            [strongSelf.delegate conversationSidebar:strongSelf didRenameRecord:record title:record.title];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDelete:(id)arg1
{
    CAConversationRecord *record = [arg1 isKindOfClass:CAConversationRecord.class] ? arg1 : nil;
    if (!record) return;

    NSString *title = record.title.length > 0 ? record.title : @"该会话";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除“%@”？", title]
                                                                  message:@"删除后无法恢复。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[CAConversationStore sharedStore] deleteRecord:record];
        [strongSelf reloadConversations];
        if ([strongSelf.delegate respondsToSelector:@selector(conversationSidebar:didDeleteRecord:)]) {
            [strongSelf.delegate conversationSidebar:strongSelf didDeleteRecord:record];
        }
    }]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)moveRecord:(id)arg1
{
    CAConversationRecord *record = [arg1 isKindOfClass:CAConversationRecord.class] ? arg1 : nil;
    if (!record) return;

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    [candidates addObject:CARuntimePaths.documentsDirectory];
    NSArray<NSString *> *saved = [NSUserDefaults.standardUserDefaults arrayForKey:CADefaultsSavedWorkspaces];
    for (NSString *path in saved) {
        if ([path isKindOfClass:NSString.class] && path.length > 0 && ![candidates containsObject:path]) {
            [candidates addObject:path];
        }
    }
    NSMutableArray<NSString *> *destinations = [NSMutableArray array];
    for (NSString *path in candidates) {
        if ([[path stringByStandardizingPath] isEqualToString:[(self.workspacePath ?: @"") stringByStandardizingPath]]) continue;
        [destinations addObject:path];
    }
    if (destinations.count == 0) {
        [self presentAlertWithTitle:@"没有其它工作区" message:@"先去工作区管理里添加一个工作区。"];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"移动到工作区"
                                                                  message:record.title ?: record.conversationId
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *destination in destinations) {
        [sheet addAction:[UIAlertAction actionWithTitle:destination.lastPathComponent ?: destination
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf moveConversation:record toWorkspace:destination];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)moveConversation:(CAConversationRecord *)record toWorkspace:(NSString *)destination
{
    CAConversationStore *store = [CAConversationStore sharedStore];
    id result = [store moveConversationWithId:record.conversationId
                                fromWorkspace:record.workspacePath
                                  toWorkspace:destination
                                        error:nil];
    BOOL ok = [result respondsToSelector:@selector(boolValue)] ? [result boolValue] : NO;
    if (!ok) {
        [self presentAlertWithTitle:@"移动失败" message:[NSString stringWithFormat:@"无法把会话移动到 %@（详见日志）。", destination]];
        return;
    }
    [self reloadConversations];
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebar:didMoveRecord:toWorkspace:)]) {
        [[self sidebarDelegate] conversationSidebar:self didMoveRecord:record toWorkspace:destination];
    }
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRemoveWorkspaceAtPath:(id)arg1
{
    NSString *path = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    if (path.length == 0) return;
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebar:didRequestPermanentDeleteWorkspaceAtPath:)]) {
        [[self sidebarDelegate] conversationSidebar:self didRequestPermanentDeleteWorkspaceAtPath:path];
    }
}

- (void)closeSidebar
{
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebarDidRequestClose:)]) {
        [[self sidebarDelegate] conversationSidebarDidRequestClose:self];
    }
}

- (void)openSettings
{
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebarDidRequestSettings:)]) {
        [[self sidebarDelegate] conversationSidebarDidRequestSettings:self];
    }
}

- (void)openUsage
{
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebarDidRequestUsage:)]) {
        [[self sidebarDelegate] conversationSidebarDidRequestUsage:self];
    }
}

- (void)openWorkspaces
{
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebarDidRequestWorkspaces:)]) {
        [[self sidebarDelegate] conversationSidebarDidRequestWorkspaces:self];
    }
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    return (signed long long)_records.count;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? arg2 : nil;
    CAConversationCell *cell = (CAConversationCell *)[self.tableView dequeueReusableCellWithIdentifier:@"CAConversationCell" forIndexPath:indexPath];
    CAConversationRecord *record = [self recordAtIndexPath:indexPath];
    BOOL active = [record.conversationId isEqualToString:self.activeConversationId ?: @""];
    [cell configureWithRecord:record active:@(active) running:@NO];
    return cell;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? arg2 : nil;
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    CAConversationRecord *record = [self recordAtIndexPath:indexPath];
    if (!record) return;
    [[CAConversationStore sharedStore] setActiveConversationId:record.conversationId workspace:self.workspacePath];
    [self reloadConversations];
    if ([[self sidebarDelegate] respondsToSelector:@selector(conversationSidebar:didSelectRecord:)]) {
        [[self sidebarDelegate] conversationSidebar:self didSelectRecord:record];
    }
}

- (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? arg2 : nil;
    CAConversationRecord *record = [self recordAtIndexPath:indexPath];
    if (!record) return nil;

    __weak typeof(self) weakSelf = self;
    UISwipeActionsConfiguration *configuration = nil;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"删除"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf confirmDelete:record];
        completionHandler(YES);
    }];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                         title:@"重命名"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf renameRecord:record];
        completionHandler(YES);
    }];
    UIContextualAction *move = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                       title:@"移动"
                                                                     handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf moveRecord:record];
        completionHandler(YES);
    }];
    configuration = [UISwipeActionsConfiguration configurationWithActions:@[ delete, rename, move ]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2
{
    return 28.0;
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    return 0.0;
}

- (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2
{
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = [NSString stringWithFormat:@"工作区 · %@", self.workspacePath.lastPathComponent ?: @"默认"];
    label.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.secondaryLabelColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4.0],
    ]];
    return header;
}

#pragma mark - 未实装（原包选择器保留）

- (void)applyAccountProfile:(id)arg1 { /* TODO(parity): 账号卡片 */ }

- (void)applyProviderIdentity { /* TODO(parity): provider 标识 */ }

- (void)buildAccountFooter { /* TODO(parity): 账号页脚 */ }

- (void)themeDidChange { /* TODO(parity) */ }

- (void)reloadWorkspaceTitle { /* TODO(parity) */ }

- (void)refreshQuota { /* TODO(parity) */ }

- (void)refreshQuotaSnapshot { /* TODO(parity) */ }

- (void)reloadAccountProfile { /* TODO(parity) */ }

- (void)persistExpandedWorkspaces { /* TODO(parity) */ }

- (void)expandWorkspaceAtPath:(id)arg1 { /* TODO(parity): 多工作区分组 */ }

- (void)toggleWorkspaceHeader:(id)arg1 { /* TODO(parity) */ }

- (void)renameWorkspaceAtPath:(id)arg1 { /* TODO(parity) */ }

- (void)openWorkspacePathInFilza:(id)arg1 { /* TODO(parity) */ }

- (void)finishPermanentWorkspaceRemovalAtPath:(id)arg1 { /* TODO(parity) */ }

- (void)costSummaryDidChange:(id)arg1 { /* TODO(parity) */ }

- (id)labelWithSize:(id)arg1 weight:(id)arg2 { return nil; }

- (id)windowTitle:(id)arg1 fallback:(id)arg2 { return [arg2 isKindOfClass:NSString.class] ? arg2 : @""; }

- (NSArray *)windowBars { return @[]; }

- (NSArray *)windowTitles { return @[]; }

- (NSArray *)windowValues { return @[]; }

- (NSSet *)runningConversationIds { return [NSSet set]; }

- (NSSet *)runningWorkspacePaths { return [NSSet set]; }

- (unsigned long long)filzaRequestGeneration { return 0; }

- (unsigned long long)quotaRefreshGeneration { return 0; }

- (void)setFilzaRequestGeneration:(id)arg1 { /* no-op */ }

- (void)setQuotaRefreshGeneration:(id)arg1 { /* no-op */ }

@end
