//
//  CAPathPickerViewController — 目录选择器（仅浏览文件夹）
//
//  原包对应面板：工作区 → 「打开文件夹」/「新建项目」时的目录选择层。
//  真实数据来源：NSFileManager 列 currentPath 下的目录；选中结果通过 -onDirectorySelected 回调给调用方。
//  边界：只允许在沙盒可达目录内浏览，路径到达 / 时不再上移。
//

#import "CAPathPickerViewController.h"
#import "CARuntimePaths.h"
#import "CACommon.h"

static NSString * const kCAPathPickerCellIdentifier = @"CAPathPickerCell";

@interface CAPathPickerViewController () <UITableViewDataSource, UITableViewDelegate>
{
    NSString *_currentPath;                // -currentPath / -setCurrentPath: 的真实存储
    NSArray *_entries;                     // 当前目录下的子目录名（含隐藏项）
    id _onDirectorySelected;               // 选中回调（取 currentPath）
    UIView *_pathBar;                      // 顶部路径条
    UILabel *_pathLabel;                   // 路径文本（中间省略）
    NSString *_readGeneration;             // -readGeneration / -setReadGeneration:（代际校验用的标记）
    UIBarButtonItem *_selectItem;          // 导航栏「选择」
    UIBarButtonItem *_createItem;          // 导航栏「新建文件夹」
    UITableView *_tableView;
    UIButton *_upButton;                   // 上一级
    UIStackView *_bottomBar;               // 底部两个动作按钮
    unsigned long long _readGenerationCounter;
}

#pragma mark - 私有辅助（工具方法，不属于原包选择器）

- (NSString *)entryNameAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)isAtRootPath:(NSString *)path;
- (NSUInteger)directoryEntryCountAtPath:(NSString *)path;
- (BOOL)isValidFolderName:(NSString *)name;
- (void)handleGoUp;

@end

@implementation CAPathPickerViewController

#pragma mark - 关闭 / 选中

- (void)cancel
{
    UINavigationController *navigation = self.navigationController;
    if (navigation && navigation.viewControllers.firstObject != self) {
        [navigation popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectCurrentDirectory
{
    NSString *path = _currentPath;
    if (_onDirectorySelected) {
        void (^callback)(NSString *) = (void (^)(NSString *))_onDirectorySelected;
        callback(path);
    }
    CALog(CALogLevelInfo, @"GENERAL", @"path picker selected path=%@", path ?: @"(none)");
    [self cancel];
}

#pragma mark - 新建

- (void)createFolder
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建文件夹"
                                                                  message:[NSString stringWithFormat:@"位置：%@", _currentPath ?: @""]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"文件夹名称";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![strongSelf isValidFolderName:name]) {
            [strongSelf showError:@"名字不能为空，也不能包含 / 或 \\。"];
            return;
        }

        NSString *target = [strongSelf->_currentPath stringByAppendingPathComponent:name];
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:target
                                     withIntermediateDirectories:NO
                                                      attributes:nil
                                                           error:&error]) {
            [strongSelf showError:[NSString stringWithFormat:@"创建失败：%@", error.localizedDescription ?: @"未知错误"]];
            return;
        }
        CALog(CALogLevelInfo, @"GENERAL", @"path picker created folder %@", target);
        [strongSelf reloadDirectory];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 路径

- (NSString *)currentPath
{
    return _currentPath;
}

- (NSArray *)entries
{
    return _entries;
}

- (id)initWithPath:(id)arg1
{
    self = [super init];
    if (self) {
        NSString *path = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil;
        BOOL isDirectory = NO;
        if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
            // 缺省 / 非法路径一律回落到 Documents
            path = [CARuntimePaths documentsDirectory];
        }
        _currentPath = [path copy];
        _entries = @[];
        _readGeneration = @"0";
        _readGenerationCounter = 0;
    }
    return self;
}

- (void)reloadDirectory
{
    NSString *path = _currentPath.length ? _currentPath : [CARuntimePaths documentsDirectory];

    // 代际校验：快速切换目录时，旧结果不允许覆盖新结果
    _readGenerationCounter += 1;
    unsigned long long generation = _readGenerationCounter;
    self.readGeneration = [NSString stringWithFormat:@"%llu", generation];

    NSError *error = nil;
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:&error];
    if (!names) {
        NSString *fallback = [CARuntimePaths documentsDirectory];
        BOOL fallbackUsable = ![fallback isEqualToString:path] &&
            [NSFileManager.defaultManager fileExistsAtPath:fallback];
        [self showError:[NSString stringWithFormat:@"无法读取目录：%@\n%@",
                         path, error.localizedDescription ?: @"未知错误"]];
        if (fallbackUsable) {
            _currentPath = [fallback copy];
            [self reloadDirectory];
        }
        return;
    }

    NSMutableArray<NSString *> *directories = [NSMutableArray array];
    for (NSString *name in names) {   // 含隐藏项（以 . 开头也列出）
        NSString *child = [path stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:child isDirectory:&isDirectory]) continue;
        if (!isDirectory) continue;   // 只显示文件夹
        [directories addObject:name];
    }
    [directories sortUsingSelector:@selector(localizedStandardCompare:)];

    if (generation != _readGenerationCounter) return;   // 结果过期，丢弃

    self.entries = directories;
    _pathLabel.text = path;
    _upButton.enabled = ![self isAtRootPath:path];
    _upButton.alpha = _upButton.enabled ? 1.0 : 0.4;
    [_tableView reloadData];
}

#pragma mark - getter / setter

- (id)createItem
{
    return _createItem;
}

- (void)setCreateItem:(id)arg1
{
    _createItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil;
}

- (void)setCurrentPath:(id)arg1
{
    _currentPath = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : nil;
}

- (void)setEntries:(id)arg1
{
    _entries = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : @[];
}

- (id)onDirectorySelected
{
    return _onDirectorySelected;
}

- (void)setOnDirectorySelected:(id)arg1
{
    _onDirectorySelected = [arg1 copy];   // block 拷到堆；nil 安全
}

- (UIView *)pathBar
{
    return _pathBar;
}

- (void)setPathBar:(id)arg1
{
    _pathBar = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
}

- (UILabel *)pathLabel
{
    return _pathLabel;
}

- (void)setPathLabel:(id)arg1
{
    _pathLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (NSString *)readGeneration
{
    return _readGeneration;
}

- (void)setReadGeneration:(id)arg1
{
    if ([arg1 isKindOfClass:NSString.class]) {
        _readGeneration = [(NSString *)arg1 copy];
    } else if ([arg1 isKindOfClass:NSNumber.class]) {
        _readGeneration = [[(NSNumber *)arg1 stringValue] copy];
    } else {
        _readGeneration = nil;
    }
}

- (id)selectItem
{
    return _selectItem;
}

- (void)setSelectItem:(id)arg1
{
    _selectItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil;
}

- (void)setTableView:(id)arg1
{
    _tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
}

- (UITableView *)tableView
{
    return _tableView;
}

#pragma mark - 错误提示

- (void)showError:(id)arg1
{
    NSString *message = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法完成"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    return (signed long long)_entries.count;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return nil;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAPathPickerCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kCAPathPickerCellIdentifier];
    }

    NSString *name = [self entryNameAtIndexPath:indexPath];
    if (!name.length) return cell;

    NSString *child = [_currentPath stringByAppendingPathComponent:name];
    cell.textLabel.text = name;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 项", (unsigned long)[self directoryEntryCountAtPath:child]];
    cell.imageView.image = [UIImage systemImageNamed:@"folder"];
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

    NSString *name = [self entryNameAtIndexPath:indexPath];
    if (!name.length) return;

    NSString *child = [_currentPath stringByAppendingPathComponent:name];
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:child isDirectory:&isDirectory] || !isDirectory) {
        [self showError:[NSString stringWithFormat:@"目录已不存在：%@", child]];
        [self reloadDirectory];
        return;
    }
    [self setCurrentPath:child];
    [self reloadDirectory];
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    if (section != 0) return nil;
    return @"仅显示文件夹（隐藏目录也会列出）。选中「选择此文件夹」即把当前路径返回给调用方。";
}

#pragma mark - 主题

- (void)themeDidChange
{
    // 系统语义色：浅色 / 深色自动跟随
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.separatorColor = UIColor.separatorColor;
    _pathBar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _pathLabel.textColor = UIColor.labelColor;
    _upButton.tintColor = UIColor.systemBlueColor;
    [_tableView reloadData];
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"选择文件夹";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILayoutGuide *margins = self.view.layoutMarginsGuide;

    // 顶部路径条：当前路径（中间省略）+ 上一级
    _pathBar = [[UIView alloc] initWithFrame:CGRectZero];
    _pathBar.translatesAutoresizingMaskIntoConstraints = NO;
    _pathBar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _pathBar.layer.cornerRadius = 12.0;
    _pathBar.layer.masksToBounds = YES;
    [self.view addSubview:_pathBar];
    [self setPathBar:_pathBar];

    _pathLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pathLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;   // 路径中间省略
    _pathLabel.textColor = UIColor.labelColor;
    _pathLabel.text = _currentPath;
    [_pathBar addSubview:_pathLabel];
    [self setPathLabel:_pathLabel];

    _upButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _upButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_upButton setTitle:@"上一级" forState:UIControlStateNormal];
    [_upButton setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateNormal];
    _upButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [_upButton addTarget:self action:@selector(handleGoUp) forControlEvents:UIControlEventTouchUpInside];
    [_pathBar addSubview:_upButton];

    [NSLayoutConstraint activateConstraints:@[
        [_pathBar.topAnchor constraintEqualToAnchor:margins.topAnchor constant:8.0],
        [_pathBar.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_pathBar.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_pathBar.heightAnchor constraintEqualToConstant:44.0],

        [_pathLabel.leadingAnchor constraintEqualToAnchor:_pathBar.leadingAnchor constant:12.0],
        [_pathLabel.centerYAnchor constraintEqualToAnchor:_pathBar.centerYAnchor],
        [_pathLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_upButton.leadingAnchor constant:-8.0],

        [_upButton.trailingAnchor constraintEqualToAnchor:_pathBar.trailingAnchor constant:-12.0],
        [_upButton.centerYAnchor constraintEqualToAnchor:_pathBar.centerYAnchor],
    ]];

    // 目录列表
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 52.0;
    [self.view addSubview:_tableView];
    [self setTableView:_tableView];

    // 底部动作：新建文件夹 / 选择此文件夹
    _bottomBar = [[UIStackView alloc] initWithFrame:CGRectZero];
    _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomBar.axis = UILayoutConstraintAxisHorizontal;
    _bottomBar.distribution = UIStackViewDistributionFillEqually;
    _bottomBar.spacing = 12.0;

    UIButton *createButton = [UIButton buttonWithType:UIButtonTypeSystem];
    createButton.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    createButton.layer.cornerRadius = 12.0;
    createButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [createButton setTitle:@"新建文件夹" forState:UIControlStateNormal];
    [createButton setImage:[UIImage systemImageNamed:@"folder.badge.plus"] forState:UIControlStateNormal];
    [createButton addTarget:self action:@selector(createFolder) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addArrangedSubview:createButton];

    UIButton *selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    selectButton.backgroundColor = UIColor.systemBlueColor;
    selectButton.tintColor = UIColor.whiteColor;
    selectButton.layer.cornerRadius = 12.0;
    selectButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [selectButton setTitle:@"选择此文件夹" forState:UIControlStateNormal];
    [selectButton addTarget:self action:@selector(selectCurrentDirectory) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addArrangedSubview:selectButton];

    [self.view addSubview:_bottomBar];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_pathBar.bottomAnchor constant:8.0],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:_bottomBar.topAnchor constant:-8.0],

        [_bottomBar.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-8.0],
        [_bottomBar.heightAnchor constraintEqualToConstant:48.0],
    ]];

    // 导航栏：左「取消」，右侧按钮存到 -createItem / -selectItem
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(cancel)];
    UIBarButtonItem *select = [[UIBarButtonItem alloc] initWithTitle:@"选择"
                                                               style:UIBarButtonItemStyleDone
                                                              target:self
                                                              action:@selector(selectCurrentDirectory)];
    UIBarButtonItem *create = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(createFolder)];
    [self setSelectItem:select];
    [self setCreateItem:create];
    self.navigationItem.rightBarButtonItems = @[ select, create ];

    [self themeDidChange];
    [self reloadDirectory];
}

#pragma mark - 私有辅助实现

- (NSString *)entryNameAtIndexPath:(NSIndexPath *)indexPath
{
    if (!indexPath) return nil;
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= _entries.count) return nil;
    id name = _entries[(NSUInteger)indexPath.row];
    return [name isKindOfClass:NSString.class] ? (NSString *)name : nil;
}

- (BOOL)isAtRootPath:(NSString *)path
{
    NSString *standardized = path.stringByStandardizingPath;
    return [standardized isEqualToString:@"/"];
}

- (NSUInteger)directoryEntryCountAtPath:(NSString *)path
{
    NSArray<NSString *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:NULL];
    return children.count;
}

- (BOOL)isValidFolderName:(NSString *)name
{
    if (!name.length) return NO;
    if ([name containsString:@"/"] || [name containsString:@"\\"]) return NO;
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) return NO;
    return YES;
}

- (void)handleGoUp
{
    NSString *path = _currentPath;
    if (!path.length || [self isAtRootPath:path]) {
        _upButton.enabled = NO;
        return;
    }
    NSString *parent = path.stringByDeletingLastPathComponent;
    if (!parent.length || [parent isEqualToString:path]) {
        _upButton.enabled = NO;
        return;
    }
    [self setCurrentPath:parent];
    [self reloadDirectory];
}

@end
