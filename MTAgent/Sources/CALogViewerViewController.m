//
//  CALogViewerViewController.m
//
//  日志来源：CALogger -currentLogText（行格式 "<时间> [LEVEL] <正文>"，与 CALogger.m 写入一致）。
//  分类来源：正文里可选的 "[CodexApp][CATEGORY]" 段；解析不到时归入 GENERAL，
//            分类菜单同时列出 CALogger -knownCategories。
//

#import "CALogViewerViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"

static NSString * const kLogCellReuseIdentifier = @"CALogViewerCell";
static const NSTimeInterval kLogAutoRefreshInterval = 2.0;
static const NSUInteger kLogMaxEntries = 4000;

typedef NS_ENUM(NSInteger, CALogLevelFilter) {
    CALogLevelFilterAll = 0,
    CALogLevelFilterDebug,
    CALogLevelFilterInfo,
    CALogLevelFilterWarn,
    CALogLevelFilterError,
};

#pragma mark - 条目模型（私有）

@interface CALogViewerEntry : NSObject
@property (nonatomic, copy) NSString *rawLine;
@property (nonatomic, copy) NSString *levelName;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, strong, nullable) NSDate *timestamp;
@end

@implementation CALogViewerEntry

- (NSString *)displayText
{
    return [NSString stringWithFormat:@"[%@] %@ %@", self.levelName, self.category, self.message];
}

@end

#pragma mark - 日志查看页

@interface CALogViewerViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *levelControl;
@property (nonatomic, strong) UIButton *categoryButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIButton *jumpBottomButton;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, strong, nullable) NSString *fileSignature;
@property (nonatomic, assign) NSUInteger pendingTotal;
@property (nonatomic, strong, nullable) NSArray *pendingEntries;
@property (nonatomic, assign) BOOL reading;
@property (nonatomic, assign) BOOL preparingShare;

- (void)buildTable;
- (void)buildFilterBar;
- (void)buildJumpButton;
- (void)startAutoRefresh;
- (void)stopAutoRefresh;
- (void)refreshTimerTick:(NSTimer *)timer;
- (void)handlePullToRefresh;
- (void)applyFiltersScrollToBottom:(BOOL)scrollToBottom;
- (NSArray<CALogViewerEntry *> *)parseLogText:(NSString *)text;
- (NSString *)currentFileSignature;
- (NSString *)levelNameForFilter:(CALogLevelFilter)filter;
- (void)levelFilterChanged:(UISegmentedControl *)sender;
- (void)selectCategory:(nullable NSString *)category;
- (void)rebuildCategoryMenu;
- (void)moreMenu;
- (void)handleJumpToBottom;
- (void)updateJumpButton;
- (BOOL)isNearBottom;
- (void)hasActiveFilter:(BOOL)flag;
- (NSString *)visibleLogText;
- (nullable NSURL *)writeSnapshotFile;
- (void)placeOnPasteboard:(NSString *)text toast:(NSString *)toast;
- (void)close;

@end

@implementation CALogViewerViewController

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"日志";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                         target:self
                                                                                         action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(moreMenu)];

    [self buildFilterBar];
    [self buildTable];
    [self buildJumpButton];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索日志";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    self.categories = @[ @"GENERAL" ];
    [self rebuildCategoryMenu];
    [self reloadLogForce:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadLogForce:NO];
    [self startAutoRefresh];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopAutoRefresh];
}

- (void)dealloc
{
    [self stopAutoRefresh];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)buildFilterBar
{
    self.levelControl = [[UISegmentedControl alloc] initWithItems:@[ @"全部", @"DEBUG", @"INFO", @"WARN", @"ERROR" ]];
    self.levelControl.selectedSegmentIndex = CALogLevelFilterAll;
    self.levelControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.levelControl addTarget:self action:@selector(levelFilterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.levelControl];

    self.categoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.categoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.categoryButton setTitle:@"全部分类" forState:UIControlStateNormal];
    self.categoryButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.categoryButton.showsMenuAsPrimaryAction = YES;
    [self.view addSubview:self.categoryButton];
}

- (void)buildTable
{
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kLogCellReuseIdentifier];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"暂无日志";
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.levelControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [self.levelControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],
        [self.levelControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],

        [self.categoryButton.topAnchor constraintEqualToAnchor:self.levelControl.bottomAnchor constant:6.0],
        [self.categoryButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.categoryButton.bottomAnchor constant:6.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)buildJumpButton
{
    self.jumpBottomButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.jumpBottomButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.jumpBottomButton setImage:[UIImage systemImageNamed:@"arrow.down.circle.fill"] forState:UIControlStateNormal];
    self.jumpBottomButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.jumpBottomButton.layer.cornerRadius = 18.0;
    self.jumpBottomButton.hidden = YES;
    [self.jumpBottomButton addTarget:self action:@selector(handleJumpToBottom) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.jumpBottomButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.jumpBottomButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.jumpBottomButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16.0],
        [self.jumpBottomButton.widthAnchor constraintEqualToConstant:36.0],
        [self.jumpBottomButton.heightAnchor constraintEqualToConstant:36.0],
    ]];
}

- (void)rebuildCategoryMenu
{
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    [names addObject:@"GENERAL"];
    for (NSString *category in [[CALogger sharedLogger] knownCategories]) {
        if (category.length > 0) [names addObject:category.uppercaseString];
    }
    for (CALogViewerEntry *entry in self.allEntries) {
        if (entry.category.length > 0) [names addObject:entry.category];
    }
    self.categories = names.array;

    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    [actions addObject:[UIAction actionWithTitle:@"全部分类" image:nil identifier:nil handler:^(UIAction *action) {
        [weakSelf selectCategory:nil];
    }]];
    for (NSString *category in self.categories) {
        UIAction *action = [UIAction actionWithTitle:category image:nil identifier:nil handler:^(UIAction *action) {
            [weakSelf selectCategory:action.title];
        }];
        [actions addObject:action];
    }
    self.categoryButton.menu = [UIMenu menuWithTitle:@"分类" children:actions];
}

#pragma mark - 读取 / 解析

- (NSString *)currentFileSignature
{
    NSString *path = [[CALogger sharedLogger] logFilePath];
    if (path.length == 0) path = [CARuntimePaths.logsDirectory stringByAppendingPathComponent:@"CodexApp.log"];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
    if (!attributes) return @"(missing)";
    return [NSString stringWithFormat:@"%@-%@", attributes[NSFileSize], attributes[NSFileModificationDate]];
}

- (void)reloadLogForce:(BOOL)force
{
    if (self.reading) return;
    NSString *signature = [self currentFileSignature];
    if (!force && [signature isEqualToString:self.fileSignature ?: @""]) return;

    self.reading = YES;
    self.fileSignature = signature;
    NSString *text = [[CALogger sharedLogger] currentLogText];

    // 附加崩溃报告（Library/CrashReports/crash-*.log），便于真机闪退定位
    NSString *crashDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    crashDir = [crashDir stringByAppendingPathComponent:@"CrashReports"];
    NSMutableString *crashText = [NSMutableString string];
    [[NSFileManager defaultManager] contentsOfDirectoryAtPath:crashDir error:NULL];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:crashDir error:NULL]) {
        if (![name hasPrefix:@"crash-"] || ![name hasSuffix:@".log"]) continue;
        NSString *content = [NSString stringWithContentsOfFile:[crashDir stringByAppendingPathComponent:name]
                                                      encoding:NSUTF8StringEncoding error:NULL];
        if (content.length) [crashText appendFormat:@"\n[CRASH] %@\n%@\n", name, content];
    }
    if (crashText.length) text = text.length ? [text stringByAppendingString:crashText] : crashText;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray<CALogViewerEntry *> *entries = [weakSelf parseLogText:text];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.allEntries = entries;
            strongSelf.totalEntryCount = entries.count;
            strongSelf.reading = NO;
            strongSelf.hasLoadedOnce = YES;
            [strongSelf rebuildCategoryMenu];
            [strongSelf applyFiltersScrollToBottom:YES];
        });
    });
}

- (NSArray<CALogViewerEntry *> *)parseLogText:(NSString *)text
{
    NSMutableArray<CALogViewerEntry *> *entries = [NSMutableArray array];
    if (text.length == 0) return entries;

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger start = lines.count > kLogMaxEntries ? lines.count - kLogMaxEntries : 0;
    NSRegularExpression *levelRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[(DEBUG|INFO|WARN|ERROR)\\]" options:0 error:NULL];
    NSRegularExpression *categoryRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[CodexApp\\]\\[([^\\]]+)\\]" options:0 error:NULL];

    for (NSUInteger index = start; index < lines.count; index++) {
        NSString *line = lines[index];
        if (line.length == 0) continue;

        CALogViewerEntry *entry = [[CALogViewerEntry alloc] init];
        entry.rawLine = line;

        NSString *level = @"INFO";
        NSTextCheckingResult *levelMatch = [levelRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (levelMatch.numberOfRanges > 1) {
            level = [line substringWithRange:[levelMatch rangeAtIndex:1]];
        }
        entry.levelName = level;

        NSString *category = @"GENERAL";
        NSTextCheckingResult *categoryMatch = [categoryRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (categoryMatch.numberOfRanges > 1) {
            category = [line substringWithRange:[categoryMatch rangeAtIndex:1]];
        }
        entry.category = category;
        entry.message = line;

        [entries addObject:entry];
    }
    return entries;
}

#pragma mark - 过滤

- (void)levelFilterChanged:(UISegmentedControl *)sender
{
    [self applyFiltersScrollToBottom:NO];
}

- (void)selectCategory:(NSString *)category
{
    self.categoryFilter = category.length > 0 ? category : nil;
    [self.categoryButton setTitle:self.categoryFilter ?: @"全部分类" forState:UIControlStateNormal];
    [self applyFiltersScrollToBottom:NO];
}

- (NSString *)levelNameForFilter:(CALogLevelFilter)filter
{
    switch (filter) {
        case CALogLevelFilterDebug: return @"DEBUG";
        case CALogLevelFilterInfo:  return @"INFO";
        case CALogLevelFilterWarn:  return @"WARN";
        case CALogLevelFilterError: return @"ERROR";
        default:                    return nil;
    }
}

- (void)applyFiltersScrollToBottom:(BOOL)scrollToBottom
{
    NSString *level = [self levelNameForFilter:(CALogLevelFilter)self.levelControl.selectedSegmentIndex];
    NSString *query = self.searchQuery.length > 0 ? self.searchQuery : nil;
    NSString *category = self.categoryFilter;

    NSMutableArray<CALogViewerEntry *> *visible = [NSMutableArray array];
    for (CALogViewerEntry *entry in self.allEntries) {
        if (level && ![entry.levelName isEqualToString:level]) continue;
        if (category && ![entry.category isEqualToString:category]) continue;
        if (query && [entry.rawLine rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        [visible addObject:entry];
    }

    self.visibleEntries = visible;
    self.emptyLabel.hidden = visible.count > 0;
    [self.tableView reloadData];

    if (scrollToBottom && visible.count > 0) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)visible.count - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
    [self updateJumpButton];
}

- (void)hasActiveFilter:(BOOL)flag
{
    self.emptyLabel.text = flag ? @"没有匹配的日志" : @"暂无日志";
}

#pragma mark - 自动刷新

- (void)startAutoRefresh
{
    if (self.refreshTimer) return;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:kLogAutoRefreshInterval
                                                         target:self
                                                       selector:@selector(refreshTimerTick:)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopAutoRefresh
{
    if (!self.refreshTimer) return;
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)refreshTimerTick:(NSTimer *)timer
{
    if (self.userIsScrolling || self.searchController.isActive) return;
    if (self.presentedViewController) return;
    [self reloadLogForce:NO];
}

- (void)handlePullToRefresh
{
    self.fileSignature = nil;
    [self reloadLogForce:YES];
    [self.refreshControl endRefreshing];
}

#pragma mark - 输出

- (NSString *)visibleLogText
{
    NSMutableString *text = [NSMutableString string];
    for (CALogViewerEntry *entry in self.visibleEntries) {
        [text appendString:entry.rawLine];
        [text appendString:@"\n"];
    }
    return text;
}

- (NSURL *)writeSnapshotFile
{
    NSString *text = [self visibleLogText];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"CodexApp-log-%@.log", [formatter stringFromDate:[NSDate date]]];
    NSString *path = [CARuntimePaths.tmpDirectory stringByAppendingPathComponent:name];

    NSError *error = nil;
    if (![CARuntimePaths ensureDirectory:path.stringByDeletingLastPathComponent mode:0700 error:&error]) {
        CALog(CALogLevelWarn, @"GENERAL", @"log snapshot directory failed: %@", error);
    }
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        CALog(CALogLevelWarn, @"GENERAL", @"log snapshot failed: %@", error);
        return nil;
    }
    return [NSURL fileURLWithPath:path];
}

- (void)handleCopyVisibleLogs
{
    NSString *text = [self visibleLogText];
    [self placeOnPasteboard:text toast:[NSString stringWithFormat:@"已复制 %lu 行", (unsigned long)self.visibleEntries.count]];
}

- (void)placeOnPasteboard:(NSString *)text toast:(NSString *)toast
{
    UIPasteboard.generalPasteboard.string = text ?: @"";
    CALog(CALogLevelInfo, @"GENERAL", @"log copied chars=%lu", (unsigned long)text.length);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:toast preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

- (void)handleShareLogFile
{
    if (self.preparingShare) return;
    self.preparingShare = YES;
    NSURL *url = [self writeSnapshotFile];
    self.preparingShare = NO;
    if (!url) return;

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.view;
    activity.popoverPresentationController.sourceRect = self.view.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)handleExportLogFile
{
    NSURL *url = [self writeSnapshotFile];
    if (!url) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ url ] asCopy:YES];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)confirmClearLog
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                  message:@"将删除本机日志文件（含轮转文件）"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[CALogger sharedLogger] clear];
        strongSelf.fileSignature = nil;
        strongSelf.allEntries = @[];
        strongSelf.visibleEntries = @[];
        strongSelf.totalEntryCount = 0;
        [strongSelf.tableView reloadData];
        [strongSelf updateJumpButton];
        [strongSelf reloadLogForce:YES];
        CALog(CALogLevelInfo, @"GENERAL", @"log cleared by user");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)moreMenu
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制可见日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleCopyVisibleLogs];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享日志文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleShareLogFile];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"导出日志文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleExportLogFile];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self confirmClearLog];
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

#pragma mark - 滚动 / 跳转

- (void)updateJumpButton
{
    BOOL nearBottom = [self isNearBottom];
    self.jumpBottomButton.hidden = nearBottom || self.visibleEntries.count == 0;
}

- (BOOL)isNearBottom
{
    CGFloat offset = self.tableView.contentOffset.y + self.tableView.bounds.size.height;
    return offset >= self.tableView.contentSize.height - 40.0;
}

- (void)handleJumpToBottom
{
    if (self.visibleEntries.count == 0) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)self.visibleEntries.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionBottom animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.userIsScrolling = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) self.userIsScrolling = NO;
    [self updateJumpButton];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    self.userIsScrolling = NO;
    [self updateJumpButton];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    [self updateJumpButton];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateJumpButton];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *query = searchController.searchBar.text;
    self.searchQuery = query.length > 0 ? query : nil;
    [self applyFiltersScrollToBottom:NO];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.visibleEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kLogCellReuseIdentifier forIndexPath:indexPath];
    CALogViewerEntry *entry = self.visibleEntries[(NSUInteger)indexPath.row];

    cell.textLabel.text = [entry displayText];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = UIColor.labelColor;

    if ([entry.levelName isEqualToString:@"ERROR"]) {
        cell.textLabel.textColor = UIColor.systemRedColor;
    } else if ([entry.levelName isEqualToString:@"WARN"]) {
        cell.textLabel.textColor = UIColor.systemOrangeColor;
    } else if ([entry.levelName isEqualToString:@"DEBUG"]) {
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
    }
    return cell;
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                        point:(CGPoint)point
{
    CALogViewerEntry *entry = self.visibleEntries[(NSUInteger)indexPath.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        UIAction *copy = [UIAction actionWithTitle:@"复制该行" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *action) {
            [self placeOnPasteboard:entry.rawLine toast:@"已复制该行"];
        }];
        UIAction *filter = [UIAction actionWithTitle:[NSString stringWithFormat:@"只看分类 %@", entry.category] image:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] identifier:nil handler:^(UIAction *action) {
            [self selectCategory:entry.category];
        }];
        return [UIMenu menuWithTitle:@"" children:@[ copy, filter ]];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CALogViewerEntry *entry = self.visibleEntries[(NSUInteger)indexPath.row];
    [self placeOnPasteboard:entry.rawLine toast:@"已复制该行"];
}

@end
