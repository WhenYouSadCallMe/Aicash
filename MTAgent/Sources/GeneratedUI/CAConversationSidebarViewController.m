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
#import "CAAccountInfoBridge.h"
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

    // 账号页脚（底部白卡）状态：ivar 名与原包 __objc_ivars 对齐
    UIView *_accountFooter;
    UIView *_accountPanel;
    UIControl *_accountControl;
    UIImageView *_accountAvatar;
    UILabel *_accountNameLabel;
    UILabel *_accountStatusLabel;
    UILabel *_accountEmailLabel;
    UILabel *_providerHintLabel;
    UIView *_footerSeparator;
    NSLayoutConstraint *_accountHeight;
    NSLayoutConstraint *_footerTop;
    NSString *_profileHome;
    NSString *_profileRefreshID;

    // 套餐余量（同一张卡下半段：套餐余量 → 主限额 / 次限额）
    UIControl *_quotaControl;
    UIStackView *_quotaHeading;
    UILabel *_quotaTitle;
    UILabel *_quotaStatus;
    UIImageView *_quotaChevron;
    UIStackView *_quotaWindows;
    NSLayoutConstraint *_quotaTop;
    NSArray<UILabel *> *_quotaWindowValueLabels;
    NSArray<UIProgressView *> *_quotaWindowBars;
    NSString *_quotaRefreshError;
    unsigned long long _quotaRefreshGeneration;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *sidebarHeader;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *workspaceButton;
@property (nonatomic, strong) UIButton *composeButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) NSLayoutConstraint *headerHeight;
@property (nonatomic, strong) NSLayoutConstraint *composeHeight;
@property (nonatomic, strong) NSLayoutConstraint *workspaceHeight;

#pragma mark 账号页脚私有方法（仅本文件使用）

- (void)buildAccountRowInPanel:(UIView *)panel;
- (void)buildQuotaSectionInPanel:(UIView *)panel;
- (UIView *)quotaColumnWithTitle:(NSString *)title valueLabel:(UILabel *)valueLabel bar:(UIProgressView *)bar;
- (void)recolorAccountFooter;
- (void)applyQuotaSnapshot:(NSDictionary *)snapshot;
- (NSDictionary *)quotaSnapshotFromLocalFiles:(NSString **)errorOut;
- (NSDictionary *)quotaWindowsFromPayload:(NSDictionary *)payload;
- (NSNumber *)quotaPercentFromValue:(id)value;
- (NSString *)quotaPercentText:(NSNumber *)percent;
- (NSDictionary *)profilePayloadFromObject:(id)object;

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
    // 截图 02：抽屉标题「MT 智能体」居中（导航栏标题），关闭钮在导航栏右侧
    self.title = @"MT 智能体";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self buildHeader];
    // 底部账号卡先建：表格底边贴在卡的顶部（原包 footerTop 约束）
    [self buildAccountFooter];
    [self buildTable];
    [self reloadConversations];
    [self reloadAccountProfile];
    [self refreshQuota];
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
    _sidebarHeader.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.view addSubview:_sidebarHeader];

    // 截图 02：标题「MT 智能体」是**导航栏**标题（居中，见 viewDidLoad 的 self.title），
    // 这一行只放两个入口：左小方钮（folder.badge.plus，进工作区）+ 右「新对话」药丸。
    _workspaceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _workspaceButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *workspaceConfiguration = [UIButtonConfiguration plainButtonConfiguration];
    workspaceConfiguration.image = [UIImage systemImageNamed:@"folder.badge.plus"];
    workspaceConfiguration.baseForegroundColor = UIColor.labelColor;
    workspaceConfiguration.background.backgroundColor = UIColor.tertiarySystemFillColor;
    workspaceConfiguration.background.cornerRadius = 12.0;
    _workspaceButton.configuration = workspaceConfiguration;
    [_workspaceButton addTarget:self action:@selector(openWorkspaces) forControlEvents:UIControlEventTouchUpInside];
    _workspaceButton.accessibilityLabel = @"工作区";
    [_sidebarHeader addSubview:_workspaceButton];

    _composeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _composeButton.translatesAutoresizingMaskIntoConstraints = NO;
    // 截图 02：铅笔图标 + 「新对话」文案（入口仍是既有 createConversation）
    UIButtonConfiguration *composeConfiguration = [UIButtonConfiguration plainButtonConfiguration];
    composeConfiguration.image = [UIImage systemImageNamed:@"square.and.pencil"];
    composeConfiguration.title = @"新对话";
    composeConfiguration.imagePadding = 6.0;
    composeConfiguration.baseForegroundColor = UIColor.labelColor;
    composeConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 14.0, 6.0, 12.0);
    composeConfiguration.background.backgroundColor = UIColor.tertiarySystemFillColor;
    composeConfiguration.background.cornerRadius = 12.0;
    _composeButton.configuration = composeConfiguration;
    _composeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [_composeButton addTarget:self action:@selector(createConversation) forControlEvents:UIControlEventTouchUpInside];
    [_sidebarHeader addSubview:_composeButton];

    // 齿轮（设置）入口按截图保留对象但不进任何视图层级：截图 02 的顶栏没有它，
    // 设置入口仍在底部账号卡的齿轮上（buildAccountRowInPanel）。
    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsButton setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    [_settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];

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

        // 截图 02 实测：左内缩 14pt、两个按钮间距 9pt、右内缩 12pt、按钮高 46pt
        [_workspaceButton.leadingAnchor constraintEqualToAnchor:_sidebarHeader.leadingAnchor constant:14.0],
        [_workspaceButton.centerYAnchor constraintEqualToAnchor:_sidebarHeader.centerYAnchor],
        [_workspaceButton.widthAnchor constraintEqualToConstant:45.0],
        [_workspaceButton.heightAnchor constraintEqualToConstant:46.0],

        [_composeButton.leadingAnchor constraintEqualToAnchor:_workspaceButton.trailingAnchor constant:9.0],
        [_composeButton.centerYAnchor constraintEqualToAnchor:_sidebarHeader.centerYAnchor],
        [_composeButton.trailingAnchor constraintEqualToAnchor:_sidebarHeader.trailingAnchor constant:-12.0],
        [_composeButton.heightAnchor constraintEqualToConstant:46.0],
    ]];
}

- (void)buildTable
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 56.0;
    [_tableView registerClass:CAConversationCell.class forCellReuseIdentifier:@"CAConversationCell"];
    [self.view addSubview:_tableView];

    // 表格底边让位给底部账号卡（账号卡不存在时退回贴 view 底部）
    UIView *footerAnchorView = _accountFooter ?: self.view;
    CGFloat footerSpacing = _accountFooter ? -8.0 : 0.0;
    _footerTop = [_tableView.bottomAnchor constraintEqualToAnchor:footerAnchorView.topAnchor constant:footerSpacing];

    // 截图 02 实测：两行灰字的中心在 y ≈ 312pt（不是整屏正中 426pt），
    // 也就是「抽屉顶部 → 底部白卡上沿」这段区域的中心。
    UILayoutGuide *emptyGuide = [[UILayoutGuide alloc] init];
    [self.view addLayoutGuide:emptyGuide];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_sidebarHeader.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _footerTop,

        [emptyGuide.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [emptyGuide.bottomAnchor constraintEqualToAnchor:footerAnchorView.topAnchor],
        [emptyGuide.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [emptyGuide.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:emptyGuide.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:emptyGuide.centerYAnchor],
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
    if (_records.count == 0) {
        // 截图 02：连项目工作区都还没有时显示引导文案；已有工作区只是没会话时用旧文案
        NSArray *savedWorkspaces = [NSUserDefaults.standardUserDefaults arrayForKey:CADefaultsSavedWorkspaces];
        self.emptyLabel.text = (savedWorkspaces.count > 0)
            ? @"当前工作区还没有会话\n点右上角新建一个"
            : @"还没有项目工作区\n点击左上角选择或新建项目";
    }
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
    // 截图 02 的空态里，入口行之下直接是居中的两行灰字：没有「工作区 · xxx」分组标题
    return (_records.count > 0) ? 28.0 : 0.0;
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    return 0.0;
}

- (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2
{
    if (_records.count == 0) return nil;
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

#pragma mark - 账号页脚（截图 02 底部白卡：个人中心 / 套餐余量 / 主限额 / 次限额）

/// 底部账号卡结构（ivar 名与原包 __objc_ivars 对齐）：
///   accountFooter ⊃ accountPanel
///     ├─ accountControl：accountAvatar（person.crop.circle.fill，灰底圆形）
///     │                  + accountNameLabel「个人中心」+ accountStatusLabel「登录账户」+ 齿轮（openSettings）
///     ├─ footerSeparator（卡片内分隔线，quotaTop 约束挂在它上面）
///     ├─ quotaControl（quotaHeading：quotaTitle「套餐余量」+ quotaStatus 值 + quotaChevron）
///     └─ quotaWindows（两列：主限额 / 次限额，各带一条细进度条）
/// 卡片高度由内容撑开（Auto Layout），accountHeight 只做最小值兜底。
- (void)buildAccountFooter
{
    if (_accountFooter) return; // 幂等：viewDidLoad / 主题切换重复调用只建一次

    _accountFooter = [[UIView alloc] initWithFrame:CGRectZero];
    _accountFooter.translatesAutoresizingMaskIntoConstraints = NO;
    _accountFooter.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_accountFooter];

    _accountPanel = [[UIView alloc] initWithFrame:CGRectZero];
    _accountPanel.translatesAutoresizingMaskIntoConstraints = NO;
    _accountPanel.layer.cornerRadius = 14.0;
    _accountPanel.layer.cornerCurve = kCACornerCurveContinuous;
    _accountPanel.clipsToBounds = YES;
    [_accountFooter addSubview:_accountPanel];

    [self buildAccountRowInPanel:_accountPanel];
    [self buildQuotaSectionInPanel:_accountPanel];

    _accountHeight = [_accountFooter.heightAnchor constraintGreaterThanOrEqualToConstant:132.0];
    [NSLayoutConstraint activateConstraints:@[
        _accountHeight,

        [_accountFooter.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],
        [_accountFooter.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],
        [_accountFooter.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],

        [_accountPanel.topAnchor constraintEqualToAnchor:_accountFooter.topAnchor],
        [_accountPanel.leadingAnchor constraintEqualToAnchor:_accountFooter.leadingAnchor],
        [_accountPanel.trailingAnchor constraintEqualToAnchor:_accountFooter.trailingAnchor],
        [_accountPanel.bottomAnchor constraintEqualToAnchor:_accountFooter.bottomAnchor],
    ]];

    [self recolorAccountFooter];
    CALog(CALogLevelDebug, @"CHAT", @"sidebar account footer built home=%@", self.accountHome);
}

/// 卡片第一段：圆形头像 + 个人中心 + 登录账户/账号名 + 齿轮按钮
- (void)buildAccountRowInPanel:(UIView *)panel
{
    _accountControl = [[UIControl alloc] initWithFrame:CGRectZero];
    _accountControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_accountControl addTarget:self action:@selector(openUsage) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:_accountControl];

    _accountAvatar = [[UIImageView alloc] initWithFrame:CGRectZero];
    _accountAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    _accountAvatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    _accountAvatar.contentMode = UIViewContentModeScaleAspectFit;
    _accountAvatar.layer.cornerRadius = 20.0;
    _accountAvatar.clipsToBounds = YES;
    [_accountControl addSubview:_accountAvatar];

    _accountNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _accountNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _accountNameLabel.text = @"个人中心";
    _accountNameLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _accountNameLabel.textColor = UIColor.labelColor;

    _accountStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _accountStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _accountStatusLabel.text = @"登录账户";
    _accountStatusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    _accountStatusLabel.textColor = UIColor.secondaryLabelColor;
    _accountStatusLabel.adjustsFontSizeToFitWidth = YES;
    _accountStatusLabel.minimumScaleFactor = 0.85;

    _accountEmailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _accountEmailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _accountEmailLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    _accountEmailLabel.textColor = UIColor.tertiaryLabelColor;
    _accountEmailLabel.hidden = YES;

    _providerHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _providerHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _providerHintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    _providerHintLabel.textColor = UIColor.tertiaryLabelColor;
    _providerHintLabel.hidden = YES;

    // 竖向信息列：hidden 的 label 由 UIStackView 自动折叠（不会留下空白）
    UIStackView *infoStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _accountNameLabel, _accountStatusLabel, _accountEmailLabel, _providerHintLabel
    ]];
    infoStack.axis = UILayoutConstraintAxisVertical;
    infoStack.alignment = UIStackViewAlignmentLeading;
    infoStack.spacing = 2.0;
    infoStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_accountControl addSubview:infoStack];

    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.translatesAutoresizingMaskIntoConstraints = NO;
    [gear setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    [gear addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [_accountControl addSubview:gear];

    [NSLayoutConstraint activateConstraints:@[
        [_accountControl.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [_accountControl.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [_accountControl.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],

        [_accountAvatar.leadingAnchor constraintEqualToAnchor:_accountControl.leadingAnchor constant:16.0],
        [_accountAvatar.centerYAnchor constraintEqualToAnchor:_accountControl.centerYAnchor],
        [_accountAvatar.widthAnchor constraintEqualToConstant:40.0],
        [_accountAvatar.heightAnchor constraintEqualToConstant:40.0],

        // 信息列高度决定整行高度（>= 40 保证最小行高，卡片高度自适应）
        [infoStack.heightAnchor constraintGreaterThanOrEqualToConstant:40.0],
        [infoStack.leadingAnchor constraintEqualToAnchor:_accountAvatar.trailingAnchor constant:12.0],
        [infoStack.trailingAnchor constraintEqualToAnchor:gear.leadingAnchor constant:-12.0],
        [infoStack.topAnchor constraintEqualToAnchor:_accountControl.topAnchor constant:14.0],
        [infoStack.bottomAnchor constraintEqualToAnchor:_accountControl.bottomAnchor constant:-14.0],

        [gear.trailingAnchor constraintEqualToAnchor:_accountControl.trailingAnchor constant:-16.0],
        [gear.centerYAnchor constraintEqualToAnchor:_accountControl.centerYAnchor],
        [gear.widthAnchor constraintEqualToConstant:28.0],
        [gear.heightAnchor constraintEqualToConstant:28.0],
    ]];
}

/// 卡片下两段：卡片内分隔线 + 「套餐余量」行 + 「主限额 / 次限额」两列
- (void)buildQuotaSectionInPanel:(UIView *)panel
{
    _footerSeparator = [[UIView alloc] initWithFrame:CGRectZero];
    _footerSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    _footerSeparator.backgroundColor = UIColor.separatorColor;
    [panel addSubview:_footerSeparator];

    // quotaTop：分隔线压在账号行下方（原包同名约束）
    _quotaTop = [_footerSeparator.topAnchor constraintEqualToAnchor:_accountControl.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        _quotaTop,
        [_footerSeparator.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16.0],
        [_footerSeparator.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16.0],
        [_footerSeparator.heightAnchor constraintEqualToConstant:0.5],
    ]];

    // 套餐余量行（整行可点：打开用量页）
    _quotaControl = [[UIControl alloc] initWithFrame:CGRectZero];
    _quotaControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_quotaControl addTarget:self action:@selector(openUsage) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:_quotaControl];

    _quotaTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _quotaTitle.text = @"套餐余量";
    _quotaTitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    _quotaTitle.textColor = UIColor.labelColor;
    [_quotaTitle setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _quotaStatus = [[UILabel alloc] initWithFrame:CGRectZero];
    _quotaStatus.text = @"暂未获取";
    _quotaStatus.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    _quotaStatus.textColor = UIColor.secondaryLabelColor;
    _quotaStatus.textAlignment = NSTextAlignmentRight;
    [_quotaStatus setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_quotaStatus setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _quotaChevron = [[UIImageView alloc] initWithFrame:CGRectZero];
    _quotaChevron.image = [UIImage systemImageNamed:@"chevron.right"];
    _quotaChevron.tintColor = UIColor.tertiaryLabelColor;
    _quotaChevron.contentMode = UIViewContentModeCenter;

    _quotaHeading = [[UIStackView alloc] initWithArrangedSubviews:@[ _quotaTitle, _quotaStatus, _quotaChevron ]];
    _quotaHeading.axis = UILayoutConstraintAxisHorizontal;
    _quotaHeading.alignment = UIStackViewAlignmentCenter;
    _quotaHeading.spacing = 6.0;
    _quotaHeading.translatesAutoresizingMaskIntoConstraints = NO;
    [_quotaControl addSubview:_quotaHeading];

    // 两列：主限额 / 次限额（每列 = 标题 + 数值 + 细进度条）
    NSMutableArray<UIView *> *columns = [NSMutableArray array];
    NSMutableArray<UILabel *> *valueLabels = [NSMutableArray array];
    NSMutableArray<UIProgressView *> *bars = [NSMutableArray array];
    for (NSString *windowTitle in @[ @"主限额", @"次限额" ]) {
        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        valueLabel.text = @"—";
        UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        bar.progress = 0.0;
        [columns addObject:[self quotaColumnWithTitle:windowTitle valueLabel:valueLabel bar:bar]];
        [valueLabels addObject:valueLabel];
        [bars addObject:bar];
    }
    _quotaWindowValueLabels = [valueLabels copy];
    _quotaWindowBars = [bars copy];

    _quotaWindows = [[UIStackView alloc] initWithArrangedSubviews:columns];
    _quotaWindows.axis = UILayoutConstraintAxisHorizontal;
    _quotaWindows.alignment = UIStackViewAlignmentFill;
    _quotaWindows.distribution = UIStackViewDistributionFillEqually;
    _quotaWindows.spacing = 16.0;
    _quotaWindows.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:_quotaWindows];

    [NSLayoutConstraint activateConstraints:@[
        [_quotaControl.topAnchor constraintEqualToAnchor:_footerSeparator.bottomAnchor],
        [_quotaControl.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [_quotaControl.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [_quotaControl.heightAnchor constraintEqualToConstant:46.0],

        [_quotaHeading.leadingAnchor constraintEqualToAnchor:_quotaControl.leadingAnchor constant:16.0],
        [_quotaHeading.trailingAnchor constraintEqualToAnchor:_quotaControl.trailingAnchor constant:-16.0],
        [_quotaHeading.centerYAnchor constraintEqualToAnchor:_quotaControl.centerYAnchor],
        [_quotaChevron.widthAnchor constraintEqualToConstant:12.0],
        [_quotaChevron.heightAnchor constraintEqualToConstant:12.0],

        [_quotaWindows.topAnchor constraintEqualToAnchor:_quotaControl.bottomAnchor],
        [_quotaWindows.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16.0],
        [_quotaWindows.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16.0],
        [_quotaWindows.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-14.0],
    ]];
}

/// 单列：标题 + 右下角数值 + 底部细进度条
- (UIView *)quotaColumnWithTitle:(NSString *)title valueLabel:(UILabel *)valueLabel bar:(UIProgressView *)bar
{
    UIView *column = [[UIView alloc] initWithFrame:CGRectZero];
    column.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    titleLabel.textColor = UIColor.secondaryLabelColor;
    [column addSubview:titleLabel];

    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    valueLabel.textColor = UIColor.labelColor;
    valueLabel.textAlignment = NSTextAlignmentRight;
    [column addSubview:valueLabel];

    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.progressTintColor = UIColor.systemBlueColor;
    bar.trackTintColor = UIColor.tertiarySystemFillColor;
    bar.layer.cornerRadius = 1.5;
    bar.clipsToBounds = YES;
    [column addSubview:bar];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:column.leadingAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:column.topAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
        [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:8.0],
        [valueLabel.firstBaselineAnchor constraintEqualToAnchor:titleLabel.firstBaselineAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:column.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
        [bar.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
        [bar.heightAnchor constraintEqualToConstant:3.0],
        [bar.bottomAnchor constraintEqualToAnchor:column.bottomAnchor],
    ]];
    return column;
}

/// 账号卡上色（系统动态色：浅色 / 深色自动适配；themeDidChange 时重跑）
- (void)recolorAccountFooter
{
    _accountPanel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _accountAvatar.backgroundColor = UIColor.tertiarySystemFillColor;
    _accountAvatar.tintColor = UIColor.secondaryLabelColor;
    _accountNameLabel.textColor = UIColor.labelColor;
    _accountStatusLabel.textColor = UIColor.secondaryLabelColor;
    _accountEmailLabel.textColor = UIColor.tertiaryLabelColor;
    _providerHintLabel.textColor = UIColor.tertiaryLabelColor;
    _footerSeparator.backgroundColor = UIColor.separatorColor;
    _quotaTitle.textColor = UIColor.labelColor;
    _quotaStatus.textColor = UIColor.secondaryLabelColor;
    _quotaChevron.tintColor = UIColor.tertiaryLabelColor;
    for (UILabel *valueLabel in _quotaWindowValueLabels) valueLabel.textColor = UIColor.labelColor;
    for (UIProgressView *bar in _quotaWindowBars) {
        bar.progressTintColor = UIColor.systemBlueColor;
        bar.trackTintColor = UIColor.tertiarySystemFillColor;
    }
}

- (void)themeDidChange
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _sidebarHeader.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.backgroundColor = UIColor.clearColor;
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    [self recolorAccountFooter];
}

#pragma mark - 账号 / 配额数据

/// 账号卡数据源：CAAccountInfoBridge 缓存（defaults 键 CodexAccountProfile.v2.<home>）先出图，再走官方 account/read 刷新
- (void)reloadAccountProfile
{
    NSString *home = CARuntimePaths.codexHome;
    NSString *token = [NSUUID UUID].UUIDString;
    _profileHome = home;
    _profileRefreshID = token; // 代际校验：只接受本轮的异步结果

    CAAccountInfoBridge *bridge = [CAAccountInfoBridge sharedBridge];
    [self applyAccountProfile:[bridge cachedProfileForHome:home]];
    [self applyProviderIdentity];

    __weak typeof(self) weakSelf = self;
    [bridge readOfficialAccountOnMainQueueWithCompletion:^(NSDictionary *profile, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![strongSelf->_profileRefreshID isEqualToString:token]) return; // 过期结果直接丢
        if (profile.count > 0) {
            [strongSelf applyAccountProfile:profile];
        } else if (error) {
            CALog(CALogLevelDebug, @"ACCOUNT", @"sidebar account/read failed reason=%@", error.localizedDescription ?: @"unknown");
        }
    }];
}

/// 账号卡文案：主标题固定「个人中心」；副标题登录后显示账号名，拿不到就维持「登录账户」
- (void)applyAccountProfile:(id)arg1
{
    NSDictionary *profile = [self profilePayloadFromObject:arg1];
    NSString *displayName = [profile[@"displayName"] isKindOfClass:NSString.class] ? profile[@"displayName"] : nil;
    NSString *email = [profile[@"email"] isKindOfClass:NSString.class] ? profile[@"email"] : nil;
    id authenticatedValue = profile[@"authenticated"];
    BOOL authenticated = [authenticatedValue respondsToSelector:@selector(boolValue)] ? [authenticatedValue boolValue] : NO;
    if (!authenticated && (displayName.length > 0 || email.length > 0)) authenticated = YES;

    _accountNameLabel.text = @"个人中心";
    NSString *subtitle = nil;
    if (authenticated) subtitle = (displayName.length > 0) ? displayName : email;
    _accountStatusLabel.text = (subtitle.length > 0) ? subtitle : @"登录账户";

    _accountEmailLabel.text = email;
    _accountEmailLabel.hidden = (email.length == 0 || [email isEqualToString:_accountStatusLabel.text ?: @""]);

    [self applyProviderIdentity];
    [self recolorAccountFooter];
    CALog(CALogLevelDebug, @"ACCOUNT", @"sidebar account card authenticated=%d name=%@", authenticated, displayName ?: @"(none)");
}

/// provider 标识：启用第三方 AI 服务时在账号名下方补一行，未启用保持隐藏
- (void)applyProviderIdentity
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL thirdParty = [defaults boolForKey:CADefaultsUseThirdPartyProvider];
    NSString *provider = [defaults stringForKey:CADefaultsThirdPartyProviderName];
    if (thirdParty && provider.length > 0) {
        _providerHintLabel.text = [NSString stringWithFormat:@"第三方服务 · %@", provider];
        _providerHintLabel.hidden = NO;
    } else {
        _providerHintLabel.text = nil;
        _providerHintLabel.hidden = YES;
    }
}

/// 配额刷新入口：代际 +1 → refreshQuotaSnapshot 异步回填
- (void)refreshQuota
{
    _quotaRefreshGeneration += 1;
    _refreshingQuota = YES;
    _quotaTitle.text = @"套餐余量";
    if (_quotaStatus.text.length == 0) _quotaStatus.text = @"暂未获取";
    [self refreshQuotaSnapshot];
}

/// 读本地配额快照（原包：app-server 的 account/rateLimits/read 落盘 rate-limits.json），回主线程写 UI
- (void)refreshQuotaSnapshot
{
    unsigned long long generation = _quotaRefreshGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *failure = nil;
        NSDictionary *snapshot = [weakSelf quotaSnapshotFromLocalFiles:&failure] ?: @{};
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (generation != strongSelf->_quotaRefreshGeneration) return; // 代际校验：过期结果丢弃
            strongSelf->_quotaRefreshError = (snapshot.count > 0) ? nil : (failure ?: @"未找到本地配额快照");
            [strongSelf applyQuotaSnapshot:snapshot];
        });
    });
}

/// 本地配额快照（只读）：<codex home>/rate-limits.json → Application Support/CodexApp/rate-limits.json
- (NSDictionary *)quotaSnapshotFromLocalFiles:(NSString **)errorOut
{
    NSArray<NSString *> *candidates = @[
        [CARuntimePaths.codexHome stringByAppendingPathComponent:@"rate-limits.json"],
        [CARuntimePaths.supportDirectory stringByAppendingPathComponent:@"rate-limits.json"],
    ];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *path in candidates) {
        if (path.length == 0 || ![fileManager fileExistsAtPath:path]) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSError *jsonError = nil;
        id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![payload isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *windows = [self quotaWindowsFromPayload:payload];
        if (windows.count == 0) continue;
        return @{ @"path": path, @"windows": windows };
    }
    if (errorOut) *errorOut = @"未找到本地配额快照";
    return @{};
}

/// 取 primary / secondary 两个窗口的 used_percent（兼容 rate_limits 与 rate_limits_by_limit_id 两种嵌套）
- (NSDictionary *)quotaWindowsFromPayload:(NSDictionary *)payload
{
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray arrayWithObject:payload];
    for (NSString *key in @[ @"rate_limits", @"rateLimits", @"rate_limits_by_limit_id", @"rateLimitsByLimitId" ]) {
        id container = payload[key];
        if (![container isKindOfClass:NSDictionary.class]) continue;
        [candidates addObject:container];
        for (id child in [container allValues]) {
            if ([child isKindOfClass:NSDictionary.class]) [candidates addObject:child];
        }
    }

    NSMutableDictionary *windows = [NSMutableDictionary dictionary];
    for (NSDictionary *candidate in candidates) {
        for (NSString *windowKey in @[ @"primary", @"secondary" ]) {
            if (windows[windowKey]) continue;
            NSNumber *percent = [self quotaPercentFromValue:candidate[windowKey]];
            if (percent) windows[windowKey] = percent;
        }
    }
    return windows;
}

/// used_percent / usedPercent 兼容数字与字符串两种写法
- (NSNumber *)quotaPercentFromValue:(id)value
{
    if ([value isKindOfClass:NSNumber.class]) return value;
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *window = value;
    for (NSString *key in @[ @"used_percent", @"usedPercent" ]) {
        id raw = window[key];
        if ([raw isKindOfClass:NSNumber.class]) return raw;
        if ([raw isKindOfClass:NSString.class] && [raw length] > 0) return @([raw doubleValue]);
    }
    return nil;
}

/// 百分比文本：整数不带小数（62%），否则保留一位（62.5%）
- (NSString *)quotaPercentText:(NSNumber *)percent
{
    NSString *text = [NSString stringWithFormat:@"%.1f", percent.doubleValue];
    return [text hasSuffix:@".0"] ? [text substringToIndex:text.length - 2] : text;
}

/// 把快照写进卡片：没数据的窗口显示「—」且进度为 0，整体显示「暂未获取」
- (void)applyQuotaSnapshot:(NSDictionary *)snapshot
{
    NSDictionary *windows = [snapshot[@"windows"] isKindOfClass:NSDictionary.class] ? snapshot[@"windows"] : @{};
    NSNumber *primary = [windows[@"primary"] isKindOfClass:NSNumber.class] ? windows[@"primary"] : nil;
    NSNumber *secondary = [windows[@"secondary"] isKindOfClass:NSNumber.class] ? windows[@"secondary"] : nil;
    NSArray<NSNumber *> *percents = @[ primary ?: @(-1.0), secondary ?: @(-1.0) ];

    NSArray<UILabel *> *valueLabels = _quotaWindowValueLabels ?: @[];
    NSArray<UIProgressView *> *bars = _quotaWindowBars ?: @[];
    NSMutableArray<NSString *> *summary = [NSMutableArray array];

    for (NSUInteger index = 0; index < valueLabels.count; index += 1) {
        NSNumber *percent = (index < percents.count) ? percents[index] : nil;
        UILabel *valueLabel = valueLabels[index];
        UIProgressView *bar = (index < bars.count) ? bars[index] : nil;
        if (percent.doubleValue >= 0.0) {
            NSString *text = [self quotaPercentText:percent];
            valueLabel.text = [NSString stringWithFormat:@"%@%%", text];
            bar.progress = (float)MIN(1.0, MAX(0.0, percent.doubleValue / 100.0));
            [summary addObject:[NSString stringWithFormat:@"%@ %@%%", (index == 0) ? @"主" : @"次", text]];
        } else {
            valueLabel.text = @"—";
            bar.progress = 0.0;
        }
    }

    _quotaTitle.text = @"套餐余量";
    _quotaStatus.text = (summary.count > 0) ? [summary componentsJoinedByString:@" · "] : @"暂未获取";
    _refreshingQuota = NO;
    CALog(CALogLevelDebug, @"USAGE", @"sidebar quota snapshot primary=%@ secondary=%@ error=%@",
          primary ?: @"(none)", secondary ?: @"(none)", _quotaRefreshError ?: @"(none)");
}

/// 兼容 NSDictionary（bridge 缓存）与 CAAccountProfile 一类对象
- (NSDictionary *)profilePayloadFromObject:(id)object
{
    if ([object isKindOfClass:NSDictionary.class]) return object;
    if (!object) return @{};

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    for (NSString *key in @[ @"displayName", @"email", @"planType", @"accountType", @"imageURL", @"userId" ]) {
        SEL selector = NSSelectorFromString(key);
        if (![object respondsToSelector:selector]) continue;
        id value = [object valueForKey:key];
        if ([value isKindOfClass:NSString.class] && [value length] > 0) payload[key] = value;
    }
    for (NSString *key in @[ @"authenticated", @"readSucceeded" ]) {
        SEL selector = NSSelectorFromString(key);
        if (![object respondsToSelector:selector]) continue;
        payload[key] = @([[object valueForKey:key] boolValue]);
    }
    return payload;
}

#pragma mark - 账号页脚访问器（对应头文件里 account* / quota* / footer* 选择器）

- (id)accountAvatar { return _accountAvatar; }

- (void)setAccountAvatar:(id)arg1
{
    _accountAvatar = [arg1 isKindOfClass:UIImageView.class] ? (UIImageView *)arg1 : nil;
}

- (id)accountControl { return _accountControl; }

- (void)setAccountControl:(id)arg1
{
    _accountControl = [arg1 isKindOfClass:UIControl.class] ? (UIControl *)arg1 : nil;
}

- (UILabel *)accountEmailLabel { return _accountEmailLabel; }

- (void)setAccountEmailLabel:(id)arg1
{
    _accountEmailLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (UIView *)accountFooter { return _accountFooter; }

- (void)setAccountFooter:(id)arg1
{
    _accountFooter = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
}

- (NSLayoutConstraint *)accountHeight { return _accountHeight; }

- (void)setAccountHeight:(id)arg1
{
    _accountHeight = [arg1 isKindOfClass:NSLayoutConstraint.class] ? (NSLayoutConstraint *)arg1 : nil;
}

- (id)accountHome { return _profileHome.length > 0 ? _profileHome : CARuntimePaths.codexHome; }

- (UILabel *)accountNameLabel { return _accountNameLabel; }

- (void)setAccountNameLabel:(id)arg1
{
    _accountNameLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (UIView *)accountPanel { return _accountPanel; }

- (void)setAccountPanel:(id)arg1
{
    _accountPanel = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
}

- (UILabel *)accountStatusLabel { return _accountStatusLabel; }

- (void)setAccountStatusLabel:(id)arg1
{
    _accountStatusLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (UIView *)footerSeparator { return _footerSeparator; }

- (void)setFooterSeparator:(id)arg1
{
    _footerSeparator = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
}

- (NSLayoutConstraint *)footerTop { return _footerTop; }

- (void)setFooterTop:(id)arg1
{
    _footerTop = [arg1 isKindOfClass:NSLayoutConstraint.class] ? (NSLayoutConstraint *)arg1 : nil;
}

- (NSString *)profileHome { return _profileHome ?: @""; }

- (void)setProfileHome:(id)arg1
{
    _profileHome = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil;
}

- (NSString *)profileRefreshID { return _profileRefreshID ?: @""; }

- (void)setProfileRefreshID:(id)arg1
{
    _profileRefreshID = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil;
}

- (UILabel *)providerHintLabel { return _providerHintLabel; }

- (void)setProviderHintLabel:(id)arg1
{
    _providerHintLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (UIImageView *)quotaChevron { return _quotaChevron; }

- (void)setQuotaChevron:(id)arg1
{
    _quotaChevron = [arg1 isKindOfClass:UIImageView.class] ? (UIImageView *)arg1 : nil;
}

- (id)quotaControl { return _quotaControl; }

- (void)setQuotaControl:(id)arg1
{
    _quotaControl = [arg1 isKindOfClass:UIControl.class] ? (UIControl *)arg1 : nil;
}

- (UIStackView *)quotaHeading { return _quotaHeading; }

- (void)setQuotaHeading:(id)arg1
{
    _quotaHeading = [arg1 isKindOfClass:UIStackView.class] ? (UIStackView *)arg1 : nil;
}

- (NSString *)quotaRefreshError { return _quotaRefreshError ?: @""; }

- (void)setQuotaRefreshError:(id)arg1
{
    _quotaRefreshError = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil;
}

- (unsigned long long)quotaRefreshGeneration { return _quotaRefreshGeneration; }

- (void)setQuotaRefreshGeneration:(id)arg1
{
    _quotaRefreshGeneration = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (UILabel *)quotaStatus { return _quotaStatus; }

- (void)setQuotaStatus:(id)arg1
{
    _quotaStatus = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (UILabel *)quotaTitle { return _quotaTitle; }

- (void)setQuotaTitle:(id)arg1
{
    _quotaTitle = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (NSLayoutConstraint *)quotaTop { return _quotaTop; }

- (void)setQuotaTop:(id)arg1
{
    _quotaTop = [arg1 isKindOfClass:NSLayoutConstraint.class] ? (NSLayoutConstraint *)arg1 : nil;
}

- (UIStackView *)quotaWindows { return _quotaWindows; }

- (void)setQuotaWindows:(id)arg1
{
    _quotaWindows = [arg1 isKindOfClass:UIStackView.class] ? (UIStackView *)arg1 : nil;
}

#pragma mark - 未实装（原包选择器保留）

- (void)reloadWorkspaceTitle { /* TODO(parity) */ }

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

- (void)setFilzaRequestGeneration:(id)arg1 { /* no-op */ }

@end
