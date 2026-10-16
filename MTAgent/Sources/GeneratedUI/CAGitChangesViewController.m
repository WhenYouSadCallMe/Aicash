//
//  CAGitChangesViewController.m — Git 变更面板（对应原版截图 06 / 07）
//
//  版式（逐项对齐截图与 SPEC/UI_还原基准.md）：
//    导航栏：左「×」圆钮（关闭）、居中标题「Git」、右「⋯」圆钮（下拉菜单）+「⟳」刷新
//    分区 0  仓库摘要卡：蓝色文件夹 + 仓库名 + 副标题（未设置上游 · 尚无提交）
//            两个胶囊（分支 master / 添加远程）+ 并排三按钮（获取 / 拉取 / 推送）
//            + 提示「还没有远程仓库。点击“添加远程”填写 HTTPS 地址后，即可推送提交。」
//    分区 1  未暂存的更改（橙色铅笔 + 计数胶囊 + 右侧「全部暂存」+ 折叠箭头）
//    分区 2  已暂存的更改（蓝色对勾 + 计数胶囊 + 右侧「全部取消暂存」）
//    分区 3  冲突（仅在有冲突时出现）
//    底部固定条：分段「全部更改 N」/「仅已暂存 M」+ 输入框（占位「这次修改了什么?」）+「✓ 提交」
//
//  数据：CAGitRepository 用 /usr/bin/git 取真实状态；取不到（无 git / 非仓库）时退化成
//        CAGitSnapshot 的演示快照，界面仍然完整可用、不会空白。
//

#import "CAGitChangesViewController.h"
#import "CAGitDiffViewController.h"
#import "CAGitRepository.h"
#import "CAGitSnapshot.h"
#import "CAGitSummaryModel.h"
#import "CAGitSummaryCell.h"
#import "CAGitChangeCell.h"
#import "CAGitCleanCell.h"
#import "CAGitGroupHeaderView.h"
#import "CAGitCommitBar.h"
#import "CAGitEmptyStateView.h"
#import "CARuntimePaths.h"
#import "CACommon.h"

/// 变更种类（sectionKinds 里存放的值）
typedef NS_ENUM(NSInteger, CAGitChangeKind) {
    CAGitChangeKindUnstaged = 0,
    CAGitChangeKindStaged = 1,
    CAGitChangeKindConflict = 2,
};

static NSString * const kCAGitSummaryCellID = @"CAGitSummary";
static NSString * const kCAGitChangeCellID = @"CAGitChange";
static NSString * const kCAGitCleanCellID = @"CAGitClean";

@interface CAGitChangesViewController () <UITableViewDataSource, UITableViewDelegate, UIAdaptivePresentationControllerDelegate>
{
    UITableView *_tableView;
    UIRefreshControl *_refreshControl;
    CAGitCommitBar *_commitBar;
    CAGitEmptyStateView *_emptyView;
    UIView *_bottomFiller;
    CAGitRepository *_git;
    CAGitSnapshot *_snapshot;
    CAGitSummaryModel *_summaryModel;
    NSArray *_sectionKinds;
    NSArray *_unstagedChanges;
    NSArray *_stagedChanges;
    NSArray *_conflictChanges;
    NSMutableSet *_collapsedKinds;
    NSDictionary *_diffStats;
    NSLayoutConstraint *_tableToBar;
    NSLayoutConstraint *_tableToGuide;
    UIBarButtonItem *_moreItem;
    UIBarButtonItem *_refreshItem;
    NSString *_workspacePath;
    NSString *_operationStatus;
    NSString *_networkAction;
    NSString *_networkBranch;
    NSString *_selectedRemote;
    NSString *_pushToken;
    NSString *_pushUsername;
    unsigned long long _refreshGeneration;
    BOOL _loading;
    BOOL _mutating;
    BOOL _stageAll;
    id _onRepositoryChanged;
}
@end

@implementation CAGitChangesViewController

#pragma mark - 生命周期

- (id)initWithWorkspacePath:(id)arg1
{
    if ((self = [super init])) {
        _workspacePath = [arg1 isKindOfClass:NSString.class] && [(NSString *)arg1 length] > 0
            ? [(NSString *)arg1 copy]
            : ([NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace] ?: CARuntimePaths.documentsCodexDirectory);
        _git = [[CAGitRepository alloc] initWithWorkspacePath:_workspacePath];
        _collapsedKinds = [NSMutableSet set];
        _sectionKinds = @[];
        _unstagedChanges = @[];
        _stagedChanges = @[];
        _conflictChanges = @[];
        _diffStats = @{};
        _selectedRemote = @"origin";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Git";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self buildNavigationItems];
    [self buildTable];
    [self buildCommitBar];
    [self rebuildModel];

    // 首次进入先给「正在读取仓库…」，随后刷新；不阻塞 UI
    [self.emptyView showLoadingWithTitle:@"正在读取仓库…"];
    [self refresh];
}

- (void)viewDidAppear:(id)arg1
{
    [super viewDidAppear:arg1];
    [self expandSheet];
}

- (void)dealloc
{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self];
}

#pragma mark - 视图构建

- (void)buildNavigationItems
{
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(close)];
    // 截图 06/07：左侧灰底白叉圆钮（实测圆底 #8E8E93）
    close.tintColor = UIColor.systemGrayColor;

    _refreshItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                    style:UIBarButtonItemStylePlain
                                                   target:self
                                                   action:@selector(refresh)];

    // 截图 06/07：⋯ 是**空心**圆 + 三个黑点（ellipsis.circle），不是实心圆
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:nil
                                                            action:nil];
    more.tintColor = UIColor.labelColor;
    _moreItem = more;

    self.navigationItem.leftBarButtonItem = close;
    self.navigationItem.rightBarButtonItems = @[ _refreshItem, _moreItem ];
}

- (void)buildTable
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60.0;
    _tableView.sectionHeaderTopPadding = 0.0;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [_tableView registerClass:CAGitSummaryCell.class forCellReuseIdentifier:kCAGitSummaryCellID];
    [_tableView registerClass:CAGitChangeCell.class forCellReuseIdentifier:kCAGitChangeCellID];
    [_tableView registerClass:CAGitCleanCell.class forCellReuseIdentifier:kCAGitCleanCellID];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    [self.view addSubview:_tableView];

    _emptyView = [[CAGitEmptyStateView alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    _emptyView.onAction = ^{
        [weakSelf handleEmptyAction];
    };
    [self.view addSubview:_emptyView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_emptyView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:40.0],
        [_emptyView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_emptyView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)buildCommitBar
{
    _commitBar = [[CAGitCommitBar alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
    _commitBar.translatesAutoresizingMaskIntoConstraints = NO;
    // 提交栏是 self.view 的子视图，回调里必须弱引用 self，避免 self → view → commitBar → block 的循环
    __weak typeof(self) weakSelf = self;
    [_commitBar setOnCommit:^(NSString *message) {
        (void)message;
        [weakSelf commit];
    }];
    [_commitBar setOnScopeChange:^(BOOL stagedOnly) {
        (void)stagedOnly;
        [weakSelf updateCommitBar];
    }];
    [_commitBar setOnTextChange:^(NSString *message) {
        (void)message;
        [weakSelf updateCommitBar];
    }];
    [_commitBar setOnBeginEditing:^{
        [weakSelf expandSheet];
    }];
    [_commitBar setOnPrefix:^(id sender) {
        [weakSelf applyPrefix:sender];
    }];
    [self.view addSubview:_commitBar];

    // 底部输入区（列表底部让位；键盘弹出时跟随 keyboardLayoutGuide）
    UILayoutGuide *keyboardGuide = self.view.keyboardLayoutGuide;
    _tableToBar = [_tableView.bottomAnchor constraintEqualToAnchor:_commitBar.topAnchor];
    // tableToGuide 与 tableToBar 语义等价（提交栏本身已钉在 keyboardLayoutGuide 上），
    // 只用其中一条避免重复约束；另一条保留给 setTableToGuide: 的既有 API。
    _tableToGuide = [_tableView.bottomAnchor constraintEqualToAnchor:keyboardGuide.topAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [_commitBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_commitBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_commitBar.bottomAnchor constraintEqualToAnchor:keyboardGuide.topAnchor],
        _tableToBar,
    ]];
}

#pragma mark - 数据

- (void)refresh
{
    _refreshGeneration += 1;
    unsigned long long generation = _refreshGeneration;
    self.loading = @YES;

    __weak typeof(self) weakSelf = self;
    [_git readSnapshot:^(CAGitSnapshot *snapshot, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || generation != self->_refreshGeneration) {
            return;
        }
        CAGitSnapshot *displayed = snapshot;
        if (snapshot == nil || !snapshot.repository) {
            // 没有 git 可执行文件 / 不是仓库：退化成演示数据，界面仍可完整浏览
            displayed = [CAGitSnapshot demoSnapshotWithWorkspaceName:[self ca_workspaceDisplayName]];
        }
        self->_snapshot = displayed;
        self->_loading = NO;
        [self->_refreshControl endRefreshing];
        [self rebuildModel];

        // 顺带取一次行级增删统计（失败不影响主流程）
        [self->_git readDiffStats:^(NSDictionary *stats, NSError *statsError) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf->_diffStats = stats ?: @{};
            [strongSelf.tableView reloadData];
        }];
    }];
}

- (void)rebuildModel
{
    CAGitSnapshot *snapshot = _snapshot;
    _unstagedChanges = [snapshot changesStaged:NO];
    _stagedChanges = [snapshot changesStaged:YES];

    NSMutableArray *conflicts = [NSMutableArray array];
    for (NSDictionary *change in snapshot.changes) {
        if ([change[kCAGitChangeConflictedKey] boolValue]) {
            [conflicts addObject:change];
        }
    }
    _conflictChanges = conflicts;

    NSMutableArray<NSNumber *> *kinds = [NSMutableArray arrayWithObjects:@(CAGitChangeKindUnstaged), @(CAGitChangeKindStaged), nil];
    if (conflicts.count > 0) {
        [kinds addObject:@(CAGitChangeKindConflict)];
    }
    _sectionKinds = kinds;

    NSString *workspaceName = [self ca_workspaceDisplayName];
    _summaryModel = [CAGitSummaryModel modelWithSnapshot:snapshot
                                           workspaceName:workspaceName
                                                    busy:_mutating
                                                activity:_networkAction];
    _stageAll = YES;

    [_tableView reloadData];
    [self updateCommitBar];
    [self updateControls];
    [self updateEmptyState];
}

- (void)updateCommitBar
{
    NSUInteger allCount = _snapshot.unstagedCount + _snapshot.stagedCount;
    if (!_snapshot.repository) {
        allCount = 0;
    }
    NSString *message = _commitBar.trimmedMessage;
    BOOL canCommit = _snapshot.repository && message.length > 0 && allCount > 0 && !_mutating;
    [_commitBar configureWithStageAll:@(_stageAll)
                             allCount:@(allCount)
                          stagedCount:@(_snapshot.stagedCount)
                              canEdit:@(!_mutating)
                            canCommit:@(canCommit)
                                 hint:_mutating ? (_operationStatus ?: @"正在执行…") : nil];
}

- (void)updateControls
{
    _refreshItem.enabled = !_mutating;
    _moreItem.enabled = !_mutating;
    _moreItem.menu = [self moreMenu];
}

- (void)updateEmptyState
{
    BOOL empty = (_snapshot == nil) || (!_snapshot.repository && _snapshot.error.length > 0 && _snapshot.changes.count == 0);
    _emptyView.hidden = !empty;
    _tableView.hidden = empty;
    if (!empty) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    _emptyView.onAction = ^{
        [weakSelf handleEmptyAction];
    };
    if (_loading) {
        [_emptyView showLoadingWithTitle:@"正在读取仓库…"];
    } else {
        [_emptyView showSymbol:@"arrow.triangle.branch"
                         title:@"这里还不是 Git 仓库"
                        detail:_snapshot.error ?: @"可以初始化仓库，或先添加一个远程地址。"
                   actionTitle:@"初始化仓库"];
    }
}

- (void)handleEmptyAction
{
    if (_snapshot.repository) {
        [self refresh];
        return;
    }
    [self initializeRepository];
}

- (void)initializeRepository
{
    if (_mutating) {
        return;
    }
    [self beginOperation:@"正在初始化仓库…"];
    __weak typeof(self) weakSelf = self;
    [_git runArguments:@[ @"init" ] completion:^(BOOL ok, NSString *output, NSInteger status) {
        [weakSelf finishOperation:ok ? @"仓库已初始化" : @"初始化失败" output:output status:@(status)];
    }];
}

#pragma mark - 菜单 / 动作

- (id)moreMenu
{
    __weak typeof(self) weakSelf = self;
    // 三行下拉菜单（左文右图标）：「暂存全部更改」/「管理分支」/「还原已跟踪文件…」
    UIAction *stageAllAction = [UIAction actionWithTitle:@"暂存全部更改"
                                                   image:[UIImage systemImageNamed:@"checkmark.circle"]
                                              identifier:nil
                                                 handler:^(UIAction *action) {
        [weakSelf stageEverything];
    }];
    UIAction *branch = [UIAction actionWithTitle:@"管理分支" image:[UIImage systemImageNamed:@"arrow.triangle.branch"] identifier:nil handler:^(UIAction *action) {
        [weakSelf selectBranch];
    }];
    UIAction *discard = [UIAction actionWithTitle:@"还原已跟踪文件…" image:[UIImage systemImageNamed:@"arrow.uturn.backward"] identifier:nil handler:^(UIAction *action) {
        [weakSelf discardAll];
    }];
    discard.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[ stageAllAction, branch, discard ]];
}

- (void)stageEverything
{
    if (![self canMutate]) {
        return;
    }
    [self beginOperation:@"正在暂存全部更改…"];
    __weak typeof(self) weakSelf = self;
    [_git runArguments:@[ @"add", @"-A" ] completion:^(BOOL ok, NSString *output, NSInteger status) {
        [weakSelf finishOperation:ok ? @"已暂存全部更改" : @"暂存失败" output:output status:@(status)];
    }];
}

- (void)discardAll
{
    if (![self canMutate]) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"还原已跟踪文件…"
                                                                  message:@"将丢弃这些文件在工作区中的所有修改，此操作不可撤销。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"还原" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        [self beginOperation:@"正在还原已跟踪文件…"];
        [self->_git discardTrackedChanges:^(BOOL ok, NSString *message) {
            [weakSelf finishOperation:message output:@"" status:@(ok ? 0 : -1)];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)stageFile:(id)arg1 unstage:(id)arg2
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    BOOL unstage = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    if (change == nil || ![self canMutate]) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
        [weakSelf finishOperation:message output:@"" status:@(ok ? 0 : -1)];
    };
    if (unstage) {
        [_git unstageChange:change completion:done];
    } else {
        [_git stageChange:change completion:done];
    }
}

- (void)discardFile:(id)arg1
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    if (change == nil || ![self canMutate]) {
        return;
    }
    BOOL untracked = [change[kCAGitChangeUntrackedKey] boolValue];
    NSString *path = change[kCAGitChangePathKey] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:untracked ? @"删除未跟踪文件" : @"还原更改"
                                                                  message:[NSString stringWithFormat:@"%@\n此操作不可撤销。", path]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:(untracked ? @"删除" : @"还原")
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        [self beginOperation:untracked ? @"正在删除…" : @"正在还原…"];
        void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
            [weakSelf finishOperation:message output:@"" status:@(ok ? 0 : -1)];
        };
        if (untracked) {
            [self->_git deleteNewChange:change completion:done];
        } else {
            [self->_git discardChange:change completion:done];
        }
    }]];
    [self anchorAlert:alert toView:self.view];
}

- (void)commit
{
    if (![self canMutate]) {
        return;
    }
    NSString *message = _commitBar.trimmedMessage;
    if (message.length == 0) {
        [self showMessage:@"先写点什么" detail:@"提交信息不能为空。"];
        return;
    }
    BOOL stageAllFirst = [_commitBar scopeIsStagedOnly] ? NO : YES;

    [self beginOperation:@"正在提交…"];
    __weak typeof(self) weakSelf = self;
    [_git commitMessage:message stageAll:@(stageAllFirst) completion:^(BOOL ok, NSString *result) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if (!ok && [result containsString:@"Please tell me who you are"]) {
            [self finishOperation:@"" output:@"" status:@(-1)];
            [self configureIdentityThenCommit];
            return;
        }
        if (ok) {
            [self->_commitBar setMessage:@""];
        }
        [weakSelf finishOperation:result output:@"" status:@(ok ? 0 : -1)];
    }];
}

- (void)configureIdentityThenCommit
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"先配置提交身份"
                                                                  message:@"Git 需要 user.name 与 user.email 才能提交。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"姓名，例如 MT Agent";
        field.text = self->_snapshot.userName;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"邮箱，例如 agent@example.com";
        field.text = self->_snapshot.userEmail;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存并提交" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        NSString *name = alert.textFields.firstObject.text ?: @"";
        NSString *email = alert.textFields.lastObject.text ?: @"";
        [self->_git setUserName:name email:email completion:^(BOOL ok, NSString *message) {
            if (!ok) {
                [weakSelf showMessage:@"保存失败" detail:message];
                return;
            }
            [weakSelf commit];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)configureRemote
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加远程"
                                                                  message:@"填写 HTTPS 地址后即可推送提交。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"https://github.com/user/repo.git";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.text = self->_snapshot.remoteURLs[self->_selectedRemote ?: @"origin"];
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        NSString *url = alert.textFields.firstObject.text ?: @"";
        [self beginOperation:@"正在保存远程…"];
        [self->_git configureRemote:(self->_selectedRemote ?: @"origin") URL:url completion:^(BOOL ok, NSString *message) {
            [weakSelf finishOperation:message output:@"" status:@(ok ? 0 : -1)];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectRemote
{
    NSArray<NSString *> *remotes = _snapshot.remotes;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"远程仓库"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *remote in remotes) {
        NSString *url = _snapshot.remoteURLs[remote];
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ · %@", remote, url ?: @""]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) {
                return;
            }
            self->_selectedRemote = remote;
            [self rebuildModel];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"添加远程…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf configureRemote];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self anchorAlert:sheet toView:self.view];
}

- (void)selectBranch
{
    __weak typeof(self) weakSelf = self;
    [_git readLocalBranches:^(NSArray<NSString *> *branches, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) {
                return;
            }
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"管理分支"
                                                                          message:error
                                                                   preferredStyle:UIAlertControllerStyleActionSheet];
            for (NSString *branch in branches) {
                NSString *title = [branch isEqualToString:self->_snapshot.branch]
                    ? [NSString stringWithFormat:@"%@（当前）", branch]
                    : branch;
                [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    [weakSelf changeBranch:branch create:@NO];
                }]];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"新建分支…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [weakSelf createBranch];
            }]];
            [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            [self anchorAlert:sheet toView:self.view];
        });
    }];
}

- (void)createBranch
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建分支"
                                                                  message:@"输入新分支名，将基于当前分支创建。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"feature/…";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf changeBranch:alert.textFields.firstObject.text create:@YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)changeBranch:(id)arg1 create:(id)arg2
{
    NSString *branch = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    BOOL create = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    if (branch.length == 0 || ![self canMutate]) {
        return;
    }
    [self beginOperation:create ? @"正在创建分支…" : @"正在切换分支…"];
    __weak typeof(self) weakSelf = self;
    [_git switchToBranch:branch create:@(create) completion:^(BOOL ok, NSString *message) {
        [weakSelf finishOperation:message output:@"" status:@(ok ? 0 : -1)];
    }];
}

- (void)fetch { [self performNetworkAction:@"获取"]; }
- (void)pull { [self performNetworkAction:@"拉取"]; }
- (void)push { [self performNetworkAction:@"推送"]; }

- (void)performNetworkAction:(id)arg1
{
    NSString *action = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    if (action.length == 0 || ![self canMutate]) {
        return;
    }
    if (_snapshot.remotes.count == 0) {
        [self configureRemote];
        return;
    }
    _networkAction = [NSString stringWithFormat:@"正在%@…", action];
    _networkBranch = _snapshot.branch;
    [self rebuildModel];

    NSString *remote = _selectedRemote ?: _snapshot.remotes.firstObject;
    __weak typeof(self) weakSelf = self;
    void (^done)(BOOL, NSString *) = ^(BOOL ok, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self->_networkAction = nil;
        self->_networkBranch = nil;
        [self finishOperation:ok ? [message componentsSeparatedByString:@"\n"].firstObject : message
                       output:message
                       status:@(ok ? 0 : -1)];
    };

    if ([action isEqualToString:@"获取"]) {
        [_git fetchFromRemote:remote username:_pushUsername token:_pushToken completion:done];
    } else if ([action isEqualToString:@"拉取"]) {
        [_git pullFromRemote:remote branch:_snapshot.branch username:_pushUsername token:_pushToken completion:done];
    } else {
        if (_pushUsername.length == 0 && _pushToken.length == 0) {
            // 首次推送前先问一次凭据（也可留空用系统凭据助手）
            [self requestRemoteCredentials];
            return;
        }
        [_git pushToRemote:remote
                    branch:_snapshot.branch
                 remoteRef:_snapshot.branch
                  username:_pushUsername
                     token:_pushToken
                completion:done];
    }
}

- (void)requestRemoteCredentials
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"推送凭据"
                                                                  message:@"填写 HTTPS 用户名与访问令牌（只用于本次推送，不会写入仓库配置）。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"用户名";
        field.text = self->_pushUsername;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"访问令牌 / 口令";
        field.secureTextEntry = YES;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续推送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        self->_pushUsername = alert.textFields.firstObject.text;
        self->_pushToken = alert.textFields.lastObject.text;
        [self performNetworkAction:@"推送"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openDiff:(id)arg1 staged:(id)arg2
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    BOOL staged = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    if (change == nil) {
        return;
    }
    CAGitDiffViewController *diff = [[CAGitDiffViewController alloc] init];
    diff.change = change;
    diff.git = _git;
    diff.prefersStaged = @(staged);
    diff.stats = _diffStats;
    [self.navigationController pushViewController:diff animated:YES];
}

#pragma mark - 操作状态

- (void)beginOperation:(id)arg1
{
    _mutating = YES;
    _operationStatus = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"正在执行…";
    [self rebuildModel];
}

- (void)finishOperation:(id)arg1 output:(id)arg2 status:(id)arg3
{
    _mutating = NO;
    _operationStatus = nil;
    NSInteger statusCode = [(NSNumber *)arg3 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg3 integerValue] : 0;
    NSString *title = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil;
    NSString *output = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : nil;

    if (title.length > 0) {
        if (statusCode == 0) {
            [self showSuccess:title detail:output];
        } else {
            [self showMessage:title detail:output];
        }
    }
    [self rebuildModel];
    if (self.onRepositoryChanged) {
        void (^handler)(NSString *) = self.onRepositoryChanged;
        handler(self.workspacePath);
    }
}

- (void)finishFileOperation:(id)arg1 status:(id)arg2
{
    NSInteger statusCode = [(NSNumber *)arg2 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg2 integerValue] : 0;
    [self finishOperation:([arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil) output:nil status:@(statusCode)];
}

- (void)showMessage:(id)arg1 detail:(id)arg2
{
    NSString *title = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"操作失败";
    NSString *detail = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : nil;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:detail
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSuccess:(id)arg1 detail:(id)arg2
{
    NSString *title = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"完成";
    NSString *detail = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : nil;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:detail
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)anchorAlert:(id)arg1 toView:(id)arg2
{
    UIAlertController *alert = [arg1 isKindOfClass:UIAlertController.class] ? (UIAlertController *)arg1 : nil;
    UIView *view = [arg2 isKindOfClass:UIView.class] ? (UIView *)arg2 : self.view;
    if (alert == nil) {
        return;
    }
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = view;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(view.bounds), CGRectGetMaxY(view.bounds) - 8.0, 1.0, 1.0);
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyPrefix:(id)arg1
{
    NSString *prefix = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"/";
    NSString *current = _commitBar.message ?: @"";
    [_commitBar setMessage:[current stringByAppendingString:prefix]];
}

- (void)expandSheet
{
    UISheetPresentationController *sheet = self.sheetPresentationController;
    if (sheet == nil) {
        return;
    }
    if (@available(iOS 15.0, *)) {
        sheet.detents = @[ UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent ];
        sheet.prefersGrabberVisible = YES;
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }
}

- (void)close
{
    if (self.navigationController.presentingViewController != nil) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - 折叠

- (void)toggleKind:(id)arg1
{
    NSNumber *kind = [(NSNumber *)arg1 respondsToSelector:@selector(integerValue)] ? (NSNumber *)arg1 : @(0);
    if ([_collapsedKinds containsObject:kind]) {
        [_collapsedKinds removeObject:kind];
    } else {
        [_collapsedKinds addObject:kind];
    }
    [_tableView reloadData];
}

- (signed long long)kindForSection:(id)arg1
{
    NSInteger section = [(NSNumber *)arg1 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg1 integerValue] : 0;
    NSInteger index = section - 1;   // 分区 0 是仓库摘要卡
    if (index < 0 || index >= (NSInteger)_sectionKinds.count) {
        return (signed long long)CAGitChangeKindUnstaged;
    }
    return (signed long long)[_sectionKinds[index] integerValue];
}

- (signed long long)sideForKind:(id)arg1
{
    NSInteger kind = [(NSNumber *)arg1 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg1 integerValue] : 0;
    return kind == CAGitChangeKindStaged ? 1 : 0;
}

- (id)changesForKind:(id)arg1
{
    NSInteger kind = [(NSNumber *)arg1 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg1 integerValue] : 0;
    switch (kind) {
        case CAGitChangeKindStaged:
            return _stagedChanges;
        case CAGitChangeKindConflict:
            return _conflictChanges;
        default:
            return _unstagedChanges;
    }
}

- (id)changeAtIndexPath:(id)arg1
{
    NSIndexPath *indexPath = [arg1 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg1 : nil;
    if (indexPath == nil || indexPath.section == 0) {
        return nil;
    }
    NSArray *changes = [self changesForKind:@([self kindForSection:@(indexPath.section)])];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)changes.count) {
        return nil;
    }
    return changes[indexPath.row];
}

- (id)statsForChange:(id)arg1 kind:(id)arg2
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    if (change == nil) {
        return nil;
    }
    return _diffStats[change[kCAGitChangePathKey] ?: @""];
}

- (bool)canMutate
{
    if (_mutating) {
        [self showMessage:@"正在执行上一步操作" detail:@"等当前操作结束后再试。"];
        return NO;
    }
    if (_snapshot == nil || !_snapshot.repository) {
        [self showMessage:@"当前工作区不是 Git 仓库" detail:@"先初始化仓库，或换一个工作区。"];
        return NO;
    }
    return YES;
}

- (void)themeDidChange
{
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _commitBar.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [_commitBar applyTheme];
    [_emptyView applyTheme];
    [_tableView reloadData];
}

- (void)traitCollectionDidChange:(id)arg1
{
    // traitCollectionDidChange: 的实参是 UITraitCollection，这里只用来触发重绘
    [super traitCollectionDidChange:([arg1 isKindOfClass:UITraitCollection.class] ? (UITraitCollection *)arg1 : nil)];
    [self themeDidChange];
}

#pragma mark - UITableViewDataSource / Delegate

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)(_sectionKinds.count + 1);
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = [(NSNumber *)arg2 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg2 integerValue] : 0;
    if (section == 0) {
        return 1;
    }
    NSNumber *kind = @([self kindForSection:@(section)]);
    NSArray *changes = [self changesForKind:kind];
    if ([_collapsedKinds containsObject:kind]) {
        return 1;   // 折叠态用一行说明占位
    }
    return MAX(1, (NSInteger)changes.count);
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (indexPath == nil) {
        return [[UITableViewCell alloc] init];
    }

    if (indexPath.section == 0) {
        CAGitSummaryCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAGitSummaryCellID forIndexPath:indexPath];
        __weak typeof(self) weakSelf = self;
        cell.onBranch = ^{ [weakSelf selectBranch]; };
        cell.onRemote = ^{ [weakSelf selectRemote]; };
        cell.onFetch = ^{ [weakSelf fetch]; };
        cell.onPull = ^{ [weakSelf pull]; };
        cell.onPush = ^{ [weakSelf push]; };
        [cell applyModel:_summaryModel];
        return cell;
    }

    NSNumber *kind = @([self kindForSection:@(indexPath.section)]);
    NSArray *changes = [self changesForKind:kind];
    BOOL collapsed = [_collapsedKinds containsObject:kind];

    if (collapsed || changes.count == 0) {
        CAGitCleanCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAGitCleanCellID forIndexPath:indexPath];
        NSInteger kindValue = kind.integerValue;
        NSString *title;
        NSString *detail;
        if (collapsed) {
            title = @"已折叠";
            detail = @"点分区标题可展开。";
        } else if (kindValue == CAGitChangeKindStaged) {
            title = @"还没有暂存的更改";
            detail = @"在「未暂存的更改」里点左侧圆圈即可暂存。";
        } else if (kindValue == CAGitChangeKindConflict) {
            title = @"没有冲突";
            detail = @"工作区干净。";
        } else {
            title = @"工作区是干净的";
            detail = @"没有需要提交的修改。";
        }
        [cell configureWithTitle:title detail:detail];
        return cell;
    }

    CAGitChangeCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAGitChangeCellID forIndexPath:indexPath];
    NSDictionary *change = changes[indexPath.row];
    BOOL staged = (kind.integerValue == CAGitChangeKindStaged);
    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^(NSDictionary *row, BOOL isStaged) {
        [weakSelf stageFile:row unstage:@(isStaged)];
    };
    [cell configureWithChange:change
                         side:@(staged ? 1 : 0)
                        stats:[self statsForChange:change kind:kind]
                      enabled:@([self canMutateSilently])];
    return cell;
}

/// 与 canMutate 同义但不弹提示（用于列表渲染）
- (BOOL)canMutateSilently
{
    return !_mutating && _snapshot != nil && _snapshot.repository;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath == nil || indexPath.section == 0) {
        return;
    }
    NSNumber *kind = @([self kindForSection:@(indexPath.section)]);
    if ([_collapsedKinds containsObject:kind]) {
        [self toggleKind:kind];
        return;
    }
    NSDictionary *change = [self changeAtIndexPath:indexPath];
    if (change) {
        [self openDiff:change staged:@(kind.integerValue == CAGitChangeKindStaged)];
    }
}

- (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2
{
    NSInteger section = [(NSNumber *)arg2 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg2 integerValue] : 0;
    if (section == 0) {
        return nil;
    }
    NSNumber *kind = @([self kindForSection:@(section)]);
    NSArray *changes = [self changesForKind:kind];
    BOOL expanded = ![_collapsedKinds containsObject:kind];

    CAGitGroupHeaderView *header = [[CAGitGroupHeaderView alloc] initWithReuseIdentifier:@"CAGitGroupHeader"];
    NSString *title;
    NSString *symbol;
    UIColor *tint;
    NSString *actionTitle;
    if (kind.integerValue == CAGitChangeKindStaged) {
        title = @"已暂存的更改";
        symbol = @"checkmark.circle";
        tint = UIColor.systemBlueColor;
        actionTitle = @"全部取消暂存";
    } else if (kind.integerValue == CAGitChangeKindConflict) {
        title = @"冲突";
        symbol = @"exclamationmark.triangle";
        tint = UIColor.systemRedColor;
        actionTitle = nil;
    } else {
        title = @"未暂存的更改";
        symbol = @"pencil";
        tint = UIColor.systemOrangeColor;
        actionTitle = @"全部暂存";
    }
    __weak typeof(self) weakSelf = self;
    [header configureWithTitle:title
                         count:@(changes.count)
                        symbol:symbol
                          tint:tint
                      expanded:@(expanded)
                   actionTitle:actionTitle
                 actionEnabled:@([self canMutateSilently] && changes.count > 0)];
    header.onToggle = ^{ [weakSelf toggleKind:kind]; };
    header.onAction = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) {
            return;
        }
        if (kind.integerValue == CAGitChangeKindStaged) {
            for (NSDictionary *change in changes) {
                [self stageFile:change unstage:@YES];
            }
        } else {
            [self stageEverything];
        }
    };
    return header;
}

- (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2
{
    NSInteger section = [(NSNumber *)arg2 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg2 integerValue] : 0;
    return section == 0 ? 8.0 : 40.0;
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    return 8.0;
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = [(NSNumber *)arg2 respondsToSelector:@selector(integerValue)] ? [(NSNumber *)arg2 integerValue] : 0;
    if (section == 1) {
        return @"点左侧圆圈暂存单个文件，点右侧「全部暂存」一次暂存所有更改。";
    }
    if (section == 2) {
        return @"提交时只会包含已暂存的内容。";
    }
    return nil;
}

- (void)tableView:(id)arg1 willDisplayFooterView:(id)arg2 forSection:(id)arg3
{
    UITableViewHeaderFooterView *footer = [arg2 isKindOfClass:UITableViewHeaderFooterView.class] ? (UITableViewHeaderFooterView *)arg2 : nil;
    footer.contentView.backgroundColor = UIColor.clearColor;
}

- (id)tableView:(id)arg1 leadingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (indexPath == nil || indexPath.section == 0) {
        return nil;
    }
    NSNumber *kind = @([self kindForSection:@(indexPath.section)]);
    if ([_collapsedKinds containsObject:kind]) {
        return nil;
    }
    NSDictionary *change = [self changeAtIndexPath:indexPath];
    if (change == nil) {
        return nil;
    }
    BOOL staged = (kind.integerValue == CAGitChangeKindStaged);
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                         title:(staged ? @"取消暂存" : @"暂存")
                                                                       handler:^(UIContextualAction *contextualAction, UIView *sourceView, void (^completion)(BOOL)) {
        [weakSelf stageFile:change unstage:@(staged)];
        completion(YES);
    }];
    action.backgroundColor = staged ? UIColor.systemGrayColor : UIColor.systemGreenColor;
    action.image = [UIImage systemImageNamed:(staged ? @"arrow.uturn.backward" : @"plus")];
    return [UISwipeActionsConfiguration configurationWithActions:@[ action ]];
}

- (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (indexPath == nil || indexPath.section == 0) {
        return nil;
    }
    NSNumber *kind = @([self kindForSection:@(indexPath.section)]);
    if ([_collapsedKinds containsObject:kind]) {
        return nil;
    }
    NSDictionary *change = [self changeAtIndexPath:indexPath];
    if (change == nil) {
        return nil;
    }
    BOOL untracked = [change[kCAGitChangeUntrackedKey] boolValue];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:(untracked ? @"删除" : @"还原")
                                                                       handler:^(UIContextualAction *contextualAction, UIView *sourceView, void (^completion)(BOOL)) {
        [weakSelf discardFile:change];
        completion(YES);
    }];
    action.image = [UIImage systemImageNamed:(untracked ? @"trash" : @"arrow.uturn.backward")];
    return [UISwipeActionsConfiguration configurationWithActions:@[ action ]];
}

- (id)tableView:(id)arg1 contextMenuConfigurationForRowAtIndexPath:(id)arg2 point:(id)arg3
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (indexPath == nil || indexPath.section == 0) {
        return nil;
    }
    NSNumber *kind = @([self kindForSection:@(indexPath.section)]);
    if ([_collapsedKinds containsObject:kind]) {
        return nil;
    }
    NSDictionary *change = [self changeAtIndexPath:indexPath];
    if (change == nil) {
        return nil;
    }
    BOOL staged = (kind.integerValue == CAGitChangeKindStaged);
    NSString *path = change[kCAGitChangePathKey] ?: @"";
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:path
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIAction *toggle = [UIAction actionWithTitle:(staged ? @"取消暂存" : @"暂存")
                                               image:[UIImage systemImageNamed:(staged ? @"arrow.uturn.backward" : @"plus")]
                                          identifier:nil
                                             handler:^(UIAction *action) {
            [weakSelf stageFile:change unstage:@(staged)];
        }];
        UIAction *discard = [UIAction actionWithTitle:@"还原更改"
                                               image:[UIImage systemImageNamed:@"arrow.uturn.backward"]
                                          identifier:nil
                                             handler:^(UIAction *action) {
            [weakSelf discardFile:change];
        }];
        discard.attributes = UIMenuElementAttributesDestructive;
        UIAction *copy = [UIAction actionWithTitle:@"复制路径"
                                             image:[UIImage systemImageNamed:@"doc.on.doc"]
                                        identifier:nil
                                           handler:^(UIAction *action) {
            UIPasteboard.generalPasteboard.string = path;
        }];
        return [UIMenu menuWithTitle:path children:@[ toggle, discard, copy ]];
    }];
}

#pragma mark - 展示态 sheet

- (bool)presentationControllerShouldDismiss:(id)arg1
{
    return !_mutating;
}

- (void)presentationControllerDidDismiss:(id)arg1
{
    if (self.onRepositoryChanged) {
        void (^handler)(NSString *) = self.onRepositoryChanged;
        handler(self.workspacePath);
    }
}

#pragma mark - 访问器

- (NSString *)workspacePath { return _workspacePath; }
- (void)setWorkspacePath:(id)arg1
{
    _workspacePath = [(NSString *)arg1 copy];
    _git = [[CAGitRepository alloc] initWithWorkspacePath:_workspacePath];
}

- (UITableView *)tableView { return _tableView; }
- (void)setTableView:(id)arg1 { _tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil; }

- (id)refreshControl { return _refreshControl; }
- (void)setRefreshControl:(id)arg1 { _refreshControl = [arg1 isKindOfClass:UIRefreshControl.class] ? (UIRefreshControl *)arg1 : nil; }

- (id)commitBar { return _commitBar; }
- (void)setCommitBar:(id)arg1 { _commitBar = [arg1 isKindOfClass:CAGitCommitBar.class] ? (CAGitCommitBar *)arg1 : nil; }

- (id)emptyView { return _emptyView; }
- (void)setEmptyView:(id)arg1 { _emptyView = [arg1 isKindOfClass:CAGitEmptyStateView.class] ? (CAGitEmptyStateView *)arg1 : nil; }

- (UIView *)bottomFiller { return _bottomFiller; }
- (void)setBottomFiller:(id)arg1 { _bottomFiller = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil; }

- (id)git { return _git; }
- (void)setGit:(id)arg1 { _git = [arg1 isKindOfClass:CAGitRepository.class] ? (CAGitRepository *)arg1 : nil; }

- (id)snapshot { return _snapshot; }
- (void)setSnapshot:(id)arg1 { _snapshot = [arg1 isKindOfClass:CAGitSnapshot.class] ? (CAGitSnapshot *)arg1 : nil; }

- (id)summaryModel { return _summaryModel; }
- (id)summaryCell { return nil; }

- (id)moreItem { return _moreItem; }
- (void)setMoreItem:(id)arg1 { _moreItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil; }

- (id)refreshItem { return _refreshItem; }
- (void)setRefreshItem:(id)arg1 { _refreshItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil; }

- (NSArray *)sectionKinds { return _sectionKinds; }
- (void)setSectionKinds:(id)arg1 { _sectionKinds = [(NSArray *)arg1 copy] ?: @[]; }

- (NSArray *)unstagedChanges { return _unstagedChanges; }
- (void)setUnstagedChanges:(id)arg1 { _unstagedChanges = [(NSArray *)arg1 copy] ?: @[]; }

- (NSArray *)stagedChanges { return _stagedChanges; }
- (void)setStagedChanges:(id)arg1 { _stagedChanges = [(NSArray *)arg1 copy] ?: @[]; }

- (NSArray *)conflictChanges { return _conflictChanges; }
- (void)setConflictChanges:(id)arg1 { _conflictChanges = [(NSArray *)arg1 copy] ?: @[]; }

- (NSMutableSet *)collapsedKinds { return _collapsedKinds; }
- (void)setCollapsedKinds:(id)arg1 { _collapsedKinds = [arg1 isKindOfClass:NSMutableSet.class] ? (NSMutableSet *)arg1 : [NSMutableSet set]; }

- (NSDictionary *)diffStats { return _diffStats; }
- (void)setDiffStats:(id)arg1 { _diffStats = [(NSDictionary *)arg1 copy] ?: @{}; }

- (bool)loading { return _loading; }
- (void)setLoading:(id)arg1 { _loading = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)mutating { return _mutating; }
- (void)setMutating:(id)arg1 { _mutating = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)stageAll { return _stageAll; }
- (void)setStageAll:(id)arg1 { _stageAll = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (unsigned long long)refreshGeneration { return _refreshGeneration; }
- (void)setRefreshGeneration:(id)arg1 { _refreshGeneration = [(NSNumber *)arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [(NSNumber *)arg1 unsignedLongLongValue] : 0; }

- (NSString *)operationStatus { return _operationStatus; }
- (void)setOperationStatus:(id)arg1 { _operationStatus = [(NSString *)arg1 copy]; }

- (NSString *)networkAction { return _networkAction; }
- (void)setNetworkAction:(id)arg1 { _networkAction = [(NSString *)arg1 copy]; }

- (NSString *)networkBranch { return _networkBranch; }
- (void)setNetworkBranch:(id)arg1 { _networkBranch = [(NSString *)arg1 copy]; }

- (NSString *)selectedRemote { return _selectedRemote; }
- (void)setSelectedRemote:(id)arg1 { _selectedRemote = [(NSString *)arg1 copy]; }

- (NSString *)pushToken { return _pushToken; }
- (void)setPushToken:(id)arg1 { _pushToken = [(NSString *)arg1 copy]; }

- (NSString *)pushUsername { return _pushUsername; }
- (void)setPushUsername:(id)arg1 { _pushUsername = [(NSString *)arg1 copy]; }

- (id)onRepositoryChanged { return _onRepositoryChanged; }
- (void)setOnRepositoryChanged:(id)arg1 { _onRepositoryChanged = arg1; }

- (id)syncHint { return _operationStatus; }

- (id)remoteSummaryText { return _summaryModel.hint; }

- (NSLayoutConstraint *)tableToBar { return _tableToBar; }
- (void)setTableToBar:(id)arg1 { _tableToBar = [arg1 isKindOfClass:NSLayoutConstraint.class] ? (NSLayoutConstraint *)arg1 : nil; }

- (NSLayoutConstraint *)tableToGuide { return _tableToGuide; }
- (void)setTableToGuide:(id)arg1 { _tableToGuide = [arg1 isKindOfClass:NSLayoutConstraint.class] ? (NSLayoutConstraint *)arg1 : nil; }

#pragma mark - 私有

/// 卡片标题：工作区显示名（Documents 这类）
- (NSString *)ca_workspaceDisplayName
{
    NSString *workspace = _workspacePath ?: @"";
    NSString *documentsDirectory = CARuntimePaths.documentsDirectory;
    if ([workspace isEqualToString:documentsDirectory]) {
        return documentsDirectory.lastPathComponent ?: @"Documents";
    }
    NSString *name = workspace.lastPathComponent;
    if (name.length == 0) {
        return @"工作区";
    }
    return name;
}

@end
