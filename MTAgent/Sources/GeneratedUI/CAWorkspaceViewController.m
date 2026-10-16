//
//  CAWorkspaceViewController — 工作区 sheet 实装（截图 03）
//
//  逐字文案：工作区 / 打开文件夹 / 选择已有项目 / 新建项目 / 在 Documents 中创建 / 全部工作区 /
//            还没有添加项目。打开已有文件夹或新建项目后，会出现在这里。
//
//  真实数据来源：
//    · 条目列表 → NSUserDefaults 的 CodexSavedWorkspaces（路径数组）+ CodexActiveWorkspace（当前工作区），去重排序
//    · 行元信息 → 后台统计每个工作区是否存在 / 可读 / 会话数（CAConversationStore.conversationCountForWorkspace:）
//    · 显示名   → CodexDocumentsWorkspaceDisplayName（Documents 目录用），否则取路径末段
//    · 新建项目 → CARuntimePaths.documentsDirectory 下建目录
//
//  视图结构照截图：抓手条 → 关闭圆钮 + 居中标题 → 两张并排动作卡 → insetGrouped 列表
//  （分组标题「全部工作区」+ 空态 footer 说明）。
//

#import "CAWorkspaceViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAConversationStore.h"
#import "CALogger.h"
#import "CAPathPickerViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface CAWorkspaceViewController () <UIDocumentPickerDelegate> {
    // 与原包 __objc_ivars 对齐
    NSArray<NSDictionary *> *_items;
    NSDictionary<NSString *, NSDictionary *> *_metaByPath;
    unsigned long long _metaGeneration;
    unsigned long long _filzaRequestGeneration;
    id _onActiveWorkspaceChanged;
    UITableView *_tableView;
    id _workspaceBusyProvider;

    // 顶部：抓手条 / 关闭钮 + 标题 / 两张动作卡
    UIView *_grabberView;
    UIView *_headerBar;
    UILabel *_titleLabel;
    UIButton *_closeButton;
    UIStackView *_actionCardsRow;
    UIControl *_openFolderCard;
    UIControl *_createProjectCard;
}

#pragma mark 私有方法（仅本文件使用）

- (void)buildGrabber;
- (void)buildHeaderBar;
- (void)buildActionCards;
- (void)buildTable;
- (UIControl *)actionCardWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle action:(SEL)action;
- (void)recolorViews;
- (void)recolorCardSubviews:(UIView *)view;
- (NSDictionary *)itemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)isItemActive:(NSDictionary *)item;
- (BOOL)isItemBusy:(NSDictionary *)item;
- (BOOL)isItemBusyAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)directoryExistsAtPath:(NSString *)path;
- (void)persistWorkspacePaths:(NSArray<NSString *> *)paths;
- (void)createProjectNamed:(NSString *)projectName;

@end

@implementation CAWorkspaceViewController

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"工作区";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self reloadItems];
    [self buildGrabber];
    [self buildHeaderBar];
    [self buildActionCards];
    [self buildTable];
    [self recolorViews];
    CALog(CALogLevelDebug, @"GENERAL", @"workspace sheet loaded projects=%lu", (unsigned long)self.projectCount);
}

- (void)viewWillAppear:(id)arg1
{
    BOOL animated = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    [super viewWillAppear:animated];
    [self reloadItems];
    [self loadMetadata];
}

#pragma mark - 界面

/// 顶部抓手条（sheet grabber）
- (void)buildGrabber
{
    _grabberView = [[UIView alloc] initWithFrame:CGRectZero];
    _grabberView.translatesAutoresizingMaskIntoConstraints = NO;
    _grabberView.backgroundColor = UIColor.systemGray4Color;
    _grabberView.layer.cornerRadius = 2.5;
    [self.view addSubview:_grabberView];
    [NSLayoutConstraint activateConstraints:@[
        [_grabberView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6.0],
        [_grabberView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_grabberView.widthAnchor constraintEqualToConstant:36.0],
        [_grabberView.heightAnchor constraintEqualToConstant:5.0],
    ]];
}

/// 关闭圆钮 + 居中标题「工作区」
- (void)buildHeaderBar
{
    _headerBar = [[UIView alloc] initWithFrame:CGRectZero];
    _headerBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerBar];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    _closeButton.layer.cornerRadius = 15.0;
    _closeButton.clipsToBounds = YES;
    [_closeButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [_headerBar addSubview:_closeButton];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = @"工作区";
    _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [_headerBar addSubview:_titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_headerBar.topAnchor constraintEqualToAnchor:_grabberView.bottomAnchor constant:6.0],
        [_headerBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_headerBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_headerBar.heightAnchor constraintEqualToConstant:44.0],

        [_closeButton.leadingAnchor constraintEqualToAnchor:_headerBar.leadingAnchor constant:16.0],
        [_closeButton.centerYAnchor constraintEqualToAnchor:_headerBar.centerYAnchor],
        [_closeButton.widthAnchor constraintEqualToConstant:30.0],
        [_closeButton.heightAnchor constraintEqualToConstant:30.0],

        [_titleLabel.centerXAnchor constraintEqualToAnchor:_headerBar.centerXAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_headerBar.centerYAnchor],
        [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_closeButton.trailingAnchor constant:8.0],
    ]];
}

/// 两张并排动作卡：打开文件夹 / 新建项目
- (void)buildActionCards
{
    _openFolderCard = [self actionCardWithSymbol:@"folder"
                                           title:@"打开文件夹"
                                        subtitle:@"选择已有项目"
                                          action:@selector(browseDirectory:)];
    _createProjectCard = [self actionCardWithSymbol:@"folder.badge.plus"
                                              title:@"新建项目"
                                           subtitle:@"在 Documents 中创建"
                                             action:@selector(createProject)];

    _actionCardsRow = [[UIStackView alloc] initWithArrangedSubviews:@[ _openFolderCard, _createProjectCard ]];
    _actionCardsRow.axis = UILayoutConstraintAxisHorizontal;
    _actionCardsRow.alignment = UIStackViewAlignmentFill;
    _actionCardsRow.distribution = UIStackViewDistributionFillEqually;
    _actionCardsRow.spacing = 12.0;
    _actionCardsRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_actionCardsRow];

    [NSLayoutConstraint activateConstraints:@[
        [_actionCardsRow.topAnchor constraintEqualToAnchor:_headerBar.bottomAnchor constant:12.0],
        [_actionCardsRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_actionCardsRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_actionCardsRow.heightAnchor constraintGreaterThanOrEqualToConstant:112.0],
    ]];
}

/// 动作卡：蓝底 SF Symbol + 主标题 + 副标题（卡内元素打 tag 便于统一上色）
- (UIControl *)actionCardWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle action:(SEL)action
{
    UIControl *card = [[UIControl alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 12.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    [card addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:symbol];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tag = 1; // 1 = 图标，2 = 主标题，3 = 副标题

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.tag = 2;

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle;
    subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.adjustsFontSizeToFitWidth = YES;
    subtitleLabel.minimumScaleFactor = 0.8;
    subtitleLabel.tag = 3;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, titleLabel, subtitleLabel ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6.0;
    stack.userInteractionEnabled = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.widthAnchor constraintEqualToConstant:32.0],
        [iconView.heightAnchor constraintEqualToConstant:32.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8.0],
        [stack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:12.0],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];
    return card;
}

/// insetGrouped 列表：分组标题「全部工作区」+ 空态 footer 由 UITableView 自身渲染
- (void)buildTable
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.dataSource = (id<UITableViewDataSource>)self;
    _tableView.delegate = (id<UITableViewDelegate>)self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 60.0;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_actionCardsRow.bottomAnchor constant:8.0],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

/// 上色（系统动态色；themeDidChange 时重跑）
- (void)recolorViews
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _grabberView.backgroundColor = UIColor.systemGray4Color;
    _titleLabel.textColor = UIColor.labelColor;
    // 截图 03：灰底白叉圆钮（与设置页 / Git / 抽屉一致）
    _closeButton.tintColor = UIColor.whiteColor;
    _closeButton.backgroundColor = UIColor.systemGrayColor;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorColor = UIColor.separatorColor;
    for (UIControl *card in @[ _openFolderCard, _createProjectCard ]) {
        card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        [self recolorCardSubviews:card];
    }
}

- (void)recolorCardSubviews:(UIView *)view
{
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIImageView.class]) {
            ((UIImageView *)subview).tintColor = UIColor.systemBlueColor;
        } else if ([subview isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)subview;
            label.textColor = (label.tag == 3) ? UIColor.secondaryLabelColor : UIColor.labelColor;
        }
        [self recolorCardSubviews:subview];
    }
}

- (void)themeDidChange
{
    [self recolorViews];
    [self.tableView reloadData];
}

#pragma mark - 数据

- (NSArray *)items
{
    if (!_items) [self reloadItems];
    return _items ?: @[];
}

- (void)setItems:(id)arg1
{
    _items = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : @[];
}

/// 重新读 defaults（CodexSavedWorkspaces + CodexActiveWorkspace）：去重、按名字排序
- (void)reloadItems
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    NSArray *saved = [defaults arrayForKey:CADefaultsSavedWorkspaces];
    if ([saved isKindOfClass:NSArray.class]) {
        for (id value in saved) {
            if (![value isKindOfClass:NSString.class]) continue;
            NSString *path = [(NSString *)value stringByStandardizingPath];
            if (path.length == 0 || [seen containsObject:path]) continue;
            [seen addObject:path];
            [entries addObject:@{ @"path": path, @"name": path.lastPathComponent ?: path, @"kind": @"project" }];
        }
    }

    // 当前工作区即使不在已保存列表里也要出现（原包：CodexActiveWorkspace 一并展示）
    NSString *active = [defaults stringForKey:CADefaultsActiveWorkspace];
    if (active.length > 0) {
        NSString *path = [active stringByStandardizingPath];
        if (path.length > 0 && ![seen containsObject:path]) {
            [seen addObject:path];
            [entries addObject:@{ @"path": path, @"name": path.lastPathComponent ?: path, @"kind": @"project" }];
        }
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedStandardCompare:right[@"name"]];
    }];
    _items = [entries copy];

    _metaByPath = @{};
    [self.tableView reloadData];
    CALog(CALogLevelDebug, @"GENERAL", @"workspace items reloaded count=%lu", (unsigned long)_items.count);
}

- (NSDictionary *)metaByPath
{
    return _metaByPath ?: @{};
}

- (void)setMetaByPath:(id)arg1
{
    _metaByPath = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : @{};
}

- (unsigned long long)metaGeneration
{
    return _metaGeneration;
}

- (void)setMetaGeneration:(id)arg1
{
    _metaGeneration = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (unsigned long long)filzaRequestGeneration
{
    return _filzaRequestGeneration;
}

- (void)setFilzaRequestGeneration:(id)arg1
{
    _filzaRequestGeneration = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (unsigned long long)projectCount
{
    return (unsigned long long)self.items.count;
}

/// 当前工作区条目（defaults CodexActiveWorkspace）
- (id)activeItem
{
    NSString *active = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace];
    if (active.length == 0) return nil;
    NSString *standardized = [active stringByStandardizingPath];
    for (NSDictionary *item in self.items) {
        NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
        if (path.length > 0 && [path isEqualToString:standardized]) return item;
    }
    return nil;
}

/// 后台统计每个工作区：目录是否存在 / 可读 / 会话数；回主线程写 metaByPath（metaGeneration 代际校验）
- (void)loadMetadata
{
    _metaGeneration += 1;
    unsigned long long generation = _metaGeneration;
    NSArray<NSDictionary *> *snapshot = self.items;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary<NSString *, NSDictionary *> *metadata = [NSMutableDictionary dictionary];
        NSFileManager *fileManager = NSFileManager.defaultManager;
        for (NSDictionary *item in snapshot) {
            NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
            if (path.length == 0) continue;
            BOOL isDirectory = NO;
            BOOL exists = [fileManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
            BOOL readable = exists && [fileManager isReadableFileAtPath:path];
            NSUInteger count = exists ? [[CAConversationStore sharedStore] conversationCountForWorkspace:path] : 0;
            metadata[path] = @{ @"exists": @(exists), @"readable": @(readable), @"conversationCount": @(count) };
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (generation != strongSelf->_metaGeneration) return; // 代际校验：过期结果丢弃
            strongSelf->_metaByPath = metadata;
            [strongSelf.tableView reloadData];
            CALog(CALogLevelDebug, @"GENERAL", @"workspace metadata refreshed count=%lu", (unsigned long)metadata.count);
        });
    });
}

#pragma mark - 行内容

- (id)nameForItem:(id)arg1
{
    NSDictionary *item = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;

    // Documents 根目录支持自定义显示名（CodexDocumentsWorkspaceDisplayName）
    if (path.length > 0 && [path isEqualToString:[CARuntimePaths.documentsDirectory stringByStandardizingPath]]) {
        NSString *displayName = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsDocumentsDisplayName];
        if (displayName.length > 0) return displayName;
    }

    NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : nil;
    if (name.length > 0) return name;
    return path.lastPathComponent ?: @"未命名工作区";
}

- (id)symbolForItem:(id)arg1
{
    NSDictionary *item = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    if (![self directoryExistsAtPath:path]) return @"folder.badge.questionmark";
    return @"folder.fill";
}

- (id)tintForItem:(id)arg1
{
    NSDictionary *item = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    if (![self directoryExistsAtPath:path]) return UIColor.systemGrayColor;   // 目录缺失：灰
    return [self isItemActive:item] ? UIColor.systemBlueColor : UIColor.systemIndigoColor; // 当前工作区：蓝
}

/// 行右侧元信息：会话数 / 目录不可读 / 未找到目录（warning 出参为 BOOL *，原包签名如此）
- (id)metaTextForItem:(id)arg1 warning:(id)arg2
{
    NSDictionary *item = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    BOOL *warningFlag = (BOOL *)(__bridge void *)arg2;
    if (warningFlag) *warningFlag = NO;

    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    if (path.length == 0) {
        if (warningFlag) *warningFlag = YES;
        return @"未找到目录";
    }

    NSDictionary *meta = self.metaByPath[path];
    BOOL exists = [meta[@"exists"] respondsToSelector:@selector(boolValue)] ? [meta[@"exists"] boolValue] : YES;
    if (!exists) {
        if (warningFlag) *warningFlag = YES;
        return @"未找到目录";
    }

    BOOL readable = [meta[@"readable"] respondsToSelector:@selector(boolValue)] ? [meta[@"readable"] boolValue] : YES;
    if (!readable) {
        if (warningFlag) *warningFlag = YES;
        return @"目录不可读";
    }

    id countValue = meta[@"conversationCount"];
    NSUInteger count = [countValue respondsToSelector:@selector(unsignedIntegerValue)] ? [countValue unsignedIntegerValue] : 0;
    return [NSString stringWithFormat:@"%lu 个会话", (unsigned long)count];
}

- (NSDictionary *)itemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!indexPath) return nil;
    NSArray<NSDictionary *> *items = self.items;
    if ((NSUInteger)indexPath.row >= items.count) return nil;
    return items[(NSUInteger)indexPath.row];
}

- (BOOL)isItemActive:(NSDictionary *)item
{
    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    NSDictionary *active = [self activeItem];
    NSString *activePath = [active[@"path"] isKindOfClass:NSString.class] ? active[@"path"] : nil;
    return (path.length > 0 && activePath.length > 0 && [path isEqualToString:activePath]);
}

- (BOOL)isItemBusy:(NSDictionary *)item
{
    id provider = _workspaceBusyProvider;
    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    if (!provider || path.length == 0) return NO;
    BOOL (^busyProvider)(NSString *) = (BOOL (^)(NSString *))provider;
    return busyProvider ? busyProvider(path) : NO;
}

- (BOOL)isItemBusyAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    return item ? [self isItemBusy:item] : NO;
}

- (BOOL)directoryExistsAtPath:(NSString *)path
{
    if (path.length == 0) return NO;
    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
    return exists && isDirectory;
}

- (void)persistWorkspacePaths:(NSArray<NSString *> *)paths
{
    [NSUserDefaults.standardUserDefaults setObject:(paths ?: @[]) forKey:CADefaultsSavedWorkspaces];
}

#pragma mark - 工作区操作

/// 选中工作区：写 defaults（CodexActiveWorkspace，Documents 下另写显示名）→ 回调宿主 → 关闭 sheet
- (void)activatePath:(id)arg1 name:(id)arg2
{
    NSString *rawPath = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    NSString *path = [rawPath stringByStandardizingPath];
    if (path.length == 0) {
        [self showError:@"工作区路径为空。" title:@"无法打开"];
        return;
    }
    NSString *name = [arg2 isKindOfClass:NSString.class] ? [(NSString *)arg2 copy] : nil;
    if (name.length == 0) name = path.lastPathComponent ?: path;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:path forKey:CADefaultsActiveWorkspace];

    // Documents 下的工作区：显示名写进 CodexDocumentsWorkspaceDisplayName（原包同款键）
    NSString *documents = [CARuntimePaths.documentsDirectory stringByStandardizingPath];
    if ([path isEqualToString:documents] || [path hasPrefix:[documents stringByAppendingString:@"/"]]) {
        [defaults setObject:name forKey:CADefaultsDocumentsDisplayName];
    }

    // 已保存列表补齐该路径（去重）
    NSMutableArray<NSString *> *saved = [[defaults arrayForKey:CADefaultsSavedWorkspaces] mutableCopy] ?: [NSMutableArray array];
    if (![saved containsObject:path]) {
        [saved addObject:path];
        [self persistWorkspacePaths:saved];
    }

    CALog(CALogLevelInfo, @"GENERAL", @"workspace activated path=%@ name=%@", path, name);
    [self reloadItems];
    [self loadMetadata];
    [self finishSelection];
}

/// 结束选择：回调宿主（onActiveWorkspaceChanged block）并关闭 sheet
- (void)finishSelection
{
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace] ?: @"";
    void (^callback)(NSString *) = (void (^)(NSString *))_onActiveWorkspaceChanged;
    if (callback) callback(path);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleClose
{
    CALog(CALogLevelDebug, @"GENERAL", @"workspace sheet closed");
    [self dismissViewControllerAnimated:YES completion:nil];
}

/// 打开文件夹：UIDocumentPickerViewController 选目录 → activatePath:name:
- (void)browseDirectory:(id)arg1
{
    UIView *sender = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
    // 两条路径：应用内目录选择器（CAPathPickerViewController，可新建文件夹）/ 系统文件选择器
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"打开文件夹"
                                                                  message:@"选择已有项目所在的目录。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"应用内浏览" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        CAPathPickerViewController *picker = [[CAPathPickerViewController alloc] initWithPath:CARuntimePaths.documentsDirectory];
        picker.onDirectorySelected = ^(NSString *directory) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || directory.length == 0) return;
            [strongSelf activatePath:directory name:directory.lastPathComponent];
        };
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:picker];
        [self presentViewController:navigation animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"系统文件选择器" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
        picker.allowsMultipleSelection = NO;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = sender ?: self.view;
        sheet.popoverPresentationController.sourceRect = sender ? sender.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
    CALog(CALogLevelDebug, @"GENERAL", @"workspace folder picker presented sender=%@", sender ? NSStringFromClass(sender.class) : @"(none)");
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessing = [url startAccessingSecurityScopedResource];
    NSString *path = url.path;
    if (accessing) [url stopAccessingSecurityScopedResource];
    if (path.length == 0) {
        [self showError:@"无法读取所选文件夹路径。" title:@"打开文件夹"];
        return;
    }
    [self activatePath:path name:url.lastPathComponent];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    CALog(CALogLevelDebug, @"GENERAL", @"workspace folder picker cancelled");
}

/// 新建项目：输入名字 → 在 Documents 下建目录 → activatePath:name:
- (void)createProject
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建项目"
                                                                  message:@"在 Documents 中创建"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"项目名称";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf createProjectNamed:alert.textFields.firstObject.text];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createProjectNamed:(NSString *)projectName
{
    NSString *rawName = [projectName isKindOfClass:NSString.class] ? projectName : @"";
    NSString *name = [rawName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) {
        [self showError:@"项目名称不能为空。" title:@"新建项目"];
        return;
    }
    if ([name containsString:@"/"] || [name containsString:@":"] || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        [self showError:@"项目名称不能包含 / 或 : 等特殊字符。" title:@"新建项目"];
        return;
    }

    NSString *path = [CARuntimePaths.documentsDirectory stringByAppendingPathComponent:name];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if ([fileManager fileExistsAtPath:path]) {
        [self showError:[NSString stringWithFormat:@"已存在同名项目：%@", name] title:@"新建项目"];
        return;
    }

    NSError *error = nil;
    BOOL created = [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (!created) {
        [self showError:[NSString stringWithFormat:@"创建失败：%@", error.localizedDescription ?: @"未知错误"] title:@"新建项目"];
        return;
    }
    CALog(CALogLevelInfo, @"GENERAL", @"workspace project created path=%@", path);
    [self activatePath:path name:name];
}

/// 移除条目：二次确认后只从 CodexSavedWorkspaces 列表移除（磁盘内容不动）
- (void)removeItem:(id)arg1
{
    NSDictionary *item = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    if (item == nil) {
        NSIndexPath *indexPath = [arg1 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg1 : nil;
        item = [self itemAtIndexPath:indexPath];
        path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    }
    if (path.length == 0) return;
    if ([self isItemBusy:item]) {
        [self showError:@"该工作区还有会话在运行，先停止运行再移除。" title:@"无法移除"];
        return;
    }

    NSString *name = [self nameForItem:item] ?: path;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"移除“%@”？", name]
                                                                  message:@"只从列表移除，磁盘上的文件不会被删除。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSMutableArray<NSString *> *saved = [[NSUserDefaults.standardUserDefaults arrayForKey:CADefaultsSavedWorkspaces] mutableCopy] ?: [NSMutableArray array];
        if ([saved containsObject:path]) [saved removeObject:path];
        [strongSelf persistWorkspacePaths:saved];
        [strongSelf reloadItems];
        [strongSelf loadMetadata];
        CALog(CALogLevelInfo, @"GENERAL", @"workspace removed from list path=%@", path);
    }]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyPath:(id)arg1
{
    NSString *path = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    if (path.length == 0 && [arg1 isKindOfClass:NSDictionary.class]) {
        NSDictionary *item = arg1;
        path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    }
    if (path.length == 0) return;
    UIPasteboard.generalPasteboard.string = path;
    CALog(CALogLevelInfo, @"GENERAL", @"workspace path copied=%@", path);
}

/// Filza 跳转：filza:// scheme（失败提示未安装），filzaRequestGeneration 做代际校验
- (void)openPathInFilza:(id)arg1
{
    NSString *path = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    if (path.length == 0 && [arg1 isKindOfClass:NSDictionary.class]) {
        NSDictionary *item = arg1;
        path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : nil;
    }
    if (path.length == 0) return;

    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"filza://%@", encoded ?: path]];
    if (!url) {
        [self showError:@"路径无法生成 Filza 链接。" title:@"打开失败"];
        return;
    }

    _filzaRequestGeneration += 1;
    unsigned long long generation = _filzaRequestGeneration;
    __weak typeof(self) weakSelf = self;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (generation != strongSelf->_filzaRequestGeneration) return; // 代际校验：已有更新的跳转请求
        [strongSelf showError:@"未检测到 Filza。请先安装 Filza 文件管理器。" title:@"打开失败"];
    }];
}

/// 统一错误提示
- (void)showError:(id)arg1 title:(id)arg2
{
    NSString *message = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    NSString *title = [arg2 isKindOfClass:NSString.class] ? arg2 : @"工作区";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    CALog(CALogLevelWarn, @"GENERAL", @"workspace alert title=%@ message=%@", title, message ?: @"");
}

#pragma mark - 访问器（原包选择器保留）

- (UITableView *)tableView
{
    return _tableView;
}

- (void)setTableView:(id)arg1
{
    _tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
}

- (id)onActiveWorkspaceChanged
{
    return _onActiveWorkspaceChanged;
}

- (void)setOnActiveWorkspaceChanged:(id)arg1
{
    _onActiveWorkspaceChanged = [arg1 isKindOfClass:NSClassFromString(@"NSBlock")] ? [arg1 copy] : arg1;
}

- (id)workspaceBusyProvider
{
    return _workspaceBusyProvider;
}

/// 可选 block：BOOL(^)(NSString *path)，YES 表示该工作区有会话在跑
- (void)setWorkspaceBusyProvider:(id)arg1
{
    _workspaceBusyProvider = [arg1 isKindOfClass:NSClassFromString(@"NSBlock")] ? [arg1 copy] : arg1;
}

#pragma mark - UITableViewDataSource / Delegate

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return 1;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    return (signed long long)self.items.count;
}

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    return @"全部工作区";
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    // 空态说明（截图 03）：没有条目时用分组 footer 显示灰字说明
    if (self.projectCount > 0) return nil;
    return @"还没有添加项目。打开已有文件夹或新建项目后，会出现在这里。";
}

- (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2
{
    return self.projectCount > 0 ? UITableViewAutomaticDimension : 36.0;
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    return self.projectCount > 0 ? 0.0 : UITableViewAutomaticDimension;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"CAWorkspaceCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CAWorkspaceCell"];
    }

    BOOL warning = NO;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = [self nameForItem:item];
    content.secondaryText = [self metaTextForItem:item warning:(__bridge id)(void *)&warning];
    content.secondaryTextProperties.color = warning ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    content.image = [UIImage systemImageNamed:[self symbolForItem:item]];
    content.imageProperties.tintColor = [self tintForItem:item];
    content.textProperties.color = [self isItemActive:item] ? UIColor.systemBlueColor : UIColor.labelColor;
    cell.contentConfiguration = content;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    if ([self isItemBusyAtIndexPath:indexPath]) {
        // 有会话在跑：行右侧转圈（同时禁止删除）
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        cell.accessoryView = spinner;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.accessoryView = nil;
        cell.accessoryType = [self isItemActive:item] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (bool)tableView:(id)arg1 shouldHighlightRowAtIndexPath:(id)arg2
{
    return YES;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    if (!item) return;
    [self activatePath:item[@"path"] name:[self nameForItem:item]];
}

- (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    if (!item) return nil;
    if ([self isItemBusyAtIndexPath:indexPath]) return nil; // 有会话在跑：禁止删除

    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                        title:@"删除"
                                                                      handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf removeItem:item];
        completionHandler(YES);
    }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[ delete ]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (id)tableView:(id)arg1 contextMenuConfigurationForRowAtIndexPath:(id)arg2 point:(id)arg3
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    if (!item) return nil;

    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return nil;

        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:@"复制路径"
                                               image:[UIImage systemImageNamed:@"doc.on.doc"]
                                          identifier:nil
                                             handler:^(UIAction *action) {
            [strongSelf copyPath:item];
        }]];
        [actions addObject:[UIAction actionWithTitle:@"在 Filza 打开"
                                               image:[UIImage systemImageNamed:@"arrow.up.forward.app"]
                                          identifier:nil
                                             handler:^(UIAction *action) {
            [strongSelf openPathInFilza:item];
        }]];
        if (![strongSelf isItemBusyAtIndexPath:indexPath]) {
            UIAction *remove = [UIAction actionWithTitle:@"删除"
                                                   image:[UIImage systemImageNamed:@"trash"]
                                              identifier:nil
                                                 handler:^(UIAction *action) {
                [strongSelf removeItem:item];
            }];
            remove.attributes = UIMenuElementAttributesDestructive;
            [actions addObject:remove];
        }
        return [UIMenu menuWithTitle:@"" children:actions];
    }];
}

@end
