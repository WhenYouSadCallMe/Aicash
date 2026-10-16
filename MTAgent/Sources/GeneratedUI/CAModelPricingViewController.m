//
//  CAModelPricingViewController.m
//
//  模型价格面板（原包：设置页「模型价格  官方 8 · API 0 >」一行点进去的页面）。
//
//  数据来源：CAModelPricingManager（models.dev / litellm / OpenRouter 价格目录 + frankfurter 汇率，
//            落盘 model-pricing-v1.json），第三方模型清单取自 defaults CodexThirdPartyAvailableModels。
//
//  分区：0 官方（officialModels）· 1 第三方（thirdPartyModels）；
//        行右侧为「输入 $x / 输出 $y · 合计≈¥z」价格行，内容来自 officialDisplaySnapshot /
//        thirdPartyDisplaySnapshot 快照（prepareDisplaySnapshots 生成，priceText: 取用）。
//
//  交互：右上 ⟳ 同步（syncPricing → refreshCatalogWithCompletion:，同步中换 spinner 并禁用按钮）、
//        UISearchController 按 slug 过滤、点击行弹 action sheet 展示该模型价格档
//        （pricingCandidatesForModel:providerHint:limit: 未实现时退化成当前一条 + models.dev 只读提示）。
//
//  方法签名逐字沿用头文件（参数统一 id 占位），所以每个方法第一行先强转再用。
//

#import "CAModelPricingViewController.h"
#import "CACommon.h"
#import "CAModelPricingManager.h"

static NSString * const kModelPricingCellReuseIdentifier = @"CAModelPricingCell";

/// 官方分区最多展示的条数（目录可能有上千条）
static const NSUInteger kModelPricingOfficialLimit = 60;

/// 第三方分区最多展示的条数
static const NSUInteger kModelPricingThirdPartyLimit = 20;

/// action sheet 里最多列出的价格档条数
static const NSUInteger kModelPricingCandidateLimit = 8;

typedef NS_ENUM(NSInteger, CAModelPricingSection) {
    CAModelPricingSectionOfficial = 0,
    CAModelPricingSectionThirdParty,
    CAModelPricingSectionCount,
};

/// 统一使用 UITableViewCellStyleValue1（左侧 slug + 右侧价格文本）
@interface CAModelPricingValueCell : UITableViewCell
@end

@implementation CAModelPricingValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

#pragma mark - 模型价格面板

@interface CAModelPricingViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
{
    // 头文件已声明的 setter/getter 对应状态：ivar + 手写访问器（避免与头文件选择器冲突）
    NSDictionary *_officialDisplaySnapshot;
    NSArray *_officialModels;
    UISearchController *_searchController;
    unsigned long long _snapshotGeneration;
    UIBarButtonItem *_syncItem;
    UIActivityIndicatorView *_syncSpinner;
    UIBarButtonItem *_syncSpinnerItem;
    NSDictionary *_thirdPartyDisplaySnapshot;
    NSArray *_thirdPartyModels;

    // 面板自身的展示状态
    UITableView *_pricingTableView;
    UILabel *_countLabel;
    NSArray<NSString *> *_filteredOfficialModels;
    NSArray<NSString *> *_filteredThirdPartyModels;
    NSString *_searchQuery;
    BOOL _syncing;
}

#pragma mark 内部实现
- (void)buildTable;
- (void)buildNavigationItems;
- (void)buildTitleView;
- (void)reloadCatalogModels;
- (void)applySearchFilter;
- (void)updateCountLabel;
- (BOOL)isThirdPartySection:(NSInteger)section;
- (NSArray<NSString *> *)visibleModelsForSection:(NSInteger)section;
- (NSArray<NSString *> *)officialCatalogModels;
- (NSArray<NSString *> *)thirdPartyCatalogModels;
- (NSArray<NSString *> *)modelsInArray:(NSArray *)models matchingQuery:(NSString *)query;
- (NSMutableArray<NSString *> *)mixedSlugsFromKeys:(NSArray<NSString *> *)keys limit:(NSUInteger)limit;
- (NSString *)providerHintForSlug:(NSString *)slug;
- (NSString *)snapshotTextForSlug:(NSString *)slug providerHint:(NSString *)providerHint;
- (NSString *)priceLineForRecord:(NSDictionary *)record;
- (NSString *)usdTextForRate:(id)rate;
- (NSString *)detailTextForRecord:(NSDictionary *)record;
- (NSString *)countText;
- (NSString *)rateSummaryText;
- (NSString *)timestampText:(NSDate *)date;
- (void)setSyncing:(BOOL)syncing;
- (void)presentCandidatesForSlug:(NSString *)slug providerHint:(NSString *)providerHint indexPath:(NSIndexPath *)indexPath;
- (void)presentCandidateDetail:(NSDictionary *)record slug:(NSString *)slug;
- (void)openModelsDevForSlug:(NSString *)slug;
- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message;

@end

@implementation CAModelPricingViewController

- (void)applyTheme
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _pricingTableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _pricingTableView.separatorColor = UIColor.separatorColor;
    self.navigationController.navigationBar.tintColor = UIColor.systemBlueColor;
    if (_countLabel) _countLabel.textColor = UIColor.secondaryLabelColor;
}

- (id)candidateTitle:(id)arg1
{
    NSDictionary *record = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    if (record.count == 0) return @"价格档";

    NSString *title = [NSString stringWithFormat:@"输入 %@ / 输出 %@",
                       [self usdTextForRate:record[@"inputRate"]],
                       [self usdTextForRate:record[@"outputRate"]]];
    NSString *provider = record[@"litellm_provider"] ?: record[@"display_name"] ?: record[@"matchedModel"];
    if ([provider isKindOfClass:NSString.class] && provider.length > 0) {
        title = [title stringByAppendingFormat:@" · %@", provider];
    }
    return title;
}

- (void)closePage
{
    // 作为 push 页面时回退导航栈，作为模态根时直接收起
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (id)modelAtIndexPath:(id)arg1
{
    NSIndexPath *indexPath = [arg1 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg1 : nil;
    if (!indexPath) return nil;

    NSArray<NSString *> *models = [self visibleModelsForSection:indexPath.section];
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= models.count) return nil;
    return models[(NSUInteger)indexPath.row];
}

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)CAModelPricingSectionCount;
}

- (NSDictionary *)officialDisplaySnapshot
{
    return _officialDisplaySnapshot;
}

- (NSArray *)officialModels
{
    return _officialModels;
}

- (void)prepareDisplaySnapshots
{
    NSMutableDictionary<NSString *, NSString *> *official = [NSMutableDictionary dictionary];
    for (NSString *slug in _officialModels) {
        if (![slug isKindOfClass:NSString.class] || slug.length == 0) continue;
        official[slug] = [self snapshotTextForSlug:slug providerHint:[self providerHintForSlug:slug]];
    }
    NSMutableDictionary<NSString *, NSString *> *thirdParty = [NSMutableDictionary dictionary];
    for (NSString *slug in _thirdPartyModels) {
        if (![slug isKindOfClass:NSString.class] || slug.length == 0) continue;
        thirdParty[slug] = [self snapshotTextForSlug:slug providerHint:[self providerHintForSlug:slug]];
    }
    _officialDisplaySnapshot = official.copy;
    _thirdPartyDisplaySnapshot = thirdParty.copy;
    _snapshotGeneration += 1;   // 快照代数：每生成一版 +1（头文件 snapshotGeneration 选择器对外可见）
    [self updateCountLabel];
}

- (id)priceText:(id)arg1
{
    NSString *slug = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : (arg1 ? [arg1 description] : @"");
    if (slug.length == 0) return @"未收录价格";

    NSString *text = _officialDisplaySnapshot[slug];
    if ([text isKindOfClass:NSString.class] && text.length > 0) return text;
    text = _thirdPartyDisplaySnapshot[slug];
    if ([text isKindOfClass:NSString.class] && text.length > 0) return text;
    return @"未收录价格";
}

- (void)pricingDidChange:(id)arg1
{
    // 目录同步在 main queue 上派发通知，这里仍做一次线程防御
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf pricingDidChange:arg1];
        });
        return;
    }

    [self reloadCatalogModels];
    [self prepareDisplaySnapshots];
    [self reloadRows];
}

- (id)providerAtIndexPath:(id)arg1
{
    NSString *slug = [self modelAtIndexPath:arg1];
    if (slug.length == 0) return nil;
    return [self providerHintForSlug:slug];
}

- (void)reloadRows
{
    // 行数与分区脚注（计数 / 汇率）都可能变化，整表刷新最稳
    [_pricingTableView reloadData];
}

- (UISearchController *)searchController
{
    return _searchController;
}

- (void)setOfficialDisplaySnapshot:(id)arg1
{
    _officialDisplaySnapshot = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : nil;
}

- (void)setOfficialModels:(id)arg1
{
    _officialModels = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : nil;
    _filteredOfficialModels = nil;
}

- (void)setSearchController:(id)arg1
{
    _searchController = [arg1 isKindOfClass:UISearchController.class] ? (UISearchController *)arg1 : nil;
}

- (void)setSnapshotGeneration:(id)arg1
{
    // 头文件里该 setter 的参数是 id 占位，真实字段是 unsigned long long
    if ([arg1 isKindOfClass:NSNumber.class]) {
        _snapshotGeneration = [(NSNumber *)arg1 unsignedLongLongValue];
    } else if (arg1) {
        _snapshotGeneration = (unsigned long long)(uintptr_t)arg1;
    } else {
        _snapshotGeneration = 0;
    }
}

- (void)setSyncItem:(id)arg1
{
    _syncItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil;
}

- (void)setSyncSpinner:(id)arg1
{
    _syncSpinner = [arg1 isKindOfClass:UIActivityIndicatorView.class] ? (UIActivityIndicatorView *)arg1 : nil;
}

- (void)setSyncSpinnerItem:(id)arg1
{
    _syncSpinnerItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil;
}

- (void)setThirdPartyDisplaySnapshot:(id)arg1
{
    _thirdPartyDisplaySnapshot = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : nil;
}

- (void)setThirdPartyModels:(id)arg1
{
    _thirdPartyModels = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : nil;
    _filteredThirdPartyModels = nil;
}

- (unsigned long long)snapshotGeneration
{
    return _snapshotGeneration;
}

- (id)syncItem
{
    return _syncItem;
}

- (void)syncPricing
{
    if (_syncing) return;
    [self setSyncing:YES];

    CALog(CALogLevelInfo, @"USAGE", @"model pricing sync requested from pricing page");
    __weak typeof(self) weakSelf = self;
    [[CAModelPricingManager sharedManager] refreshCatalogWithCompletion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;

            [strongSelf setSyncing:NO];
            if (error) {
                [strongSelf presentAlertWithTitle:@"同步失败"
                                          message:error.localizedDescription ?: @"网络错误，稍后重试"];
                return;
            }

            [strongSelf reloadCatalogModels];
            [strongSelf prepareDisplaySnapshots];
            [strongSelf reloadRows];
            [strongSelf presentAlertWithTitle:@"模型价格已更新"
                                      message:[NSString stringWithFormat:@"%@\n%@",
                                               [strongSelf countText], [strongSelf rateSummaryText]]];
        });
    }];
}

- (id)syncSpinner
{
    return _syncSpinner;
}

- (id)syncSpinnerItem
{
    return _syncSpinnerItem;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = (UITableView *)arg1;
    NSIndexPath *indexPath = (NSIndexPath *)arg2;

    CAModelPricingValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kModelPricingCellReuseIdentifier
                                                                  forIndexPath:indexPath];
    if (!cell) {
        cell = [[CAModelPricingValueCell alloc] initWithStyle:UITableViewCellStyleValue1
                                             reuseIdentifier:kModelPricingCellReuseIdentifier];
    }

    NSString *slug = [self modelAtIndexPath:indexPath] ?: @"";

    cell.textLabel.text = slug;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.minimumScaleFactor = 0.75;

    cell.detailTextLabel.text = [self priceText:slug];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.7;

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.tintColor = UIColor.systemBlueColor;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = (UITableView *)arg1;
    NSIndexPath *indexPath = (NSIndexPath *)arg2;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *slug = [self modelAtIndexPath:indexPath] ?: @"";
    if (slug.length == 0) return;
    [self presentCandidatesForSlug:slug providerHint:[self providerAtIndexPath:indexPath] indexPath:indexPath];
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    // arg2 实际是 NSInteger 分区号（占位声明成 id），按整数取用
    NSInteger section = (NSInteger)arg2;
    return (signed long long)[self visibleModelsForSection:section].count;
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = (NSInteger)arg2;
    NSArray<NSString *> *models = [self visibleModelsForSection:section];
    if (models.count == 0) {
        if (_searchQuery.length > 0) {
            return [NSString stringWithFormat:@"没有匹配「%@」的模型。", _searchQuery];
        }
        if ([self isThirdPartySection:section]) {
            return @"本机尚未探测到第三方模型（CodexThirdPartyAvailableModels 为空）。";
        }
        return @"本机还没有模型价格目录，点右上角 ⟳ 同步。";
    }

    NSString *source = [self isThirdPartySection:section]
        ? @"第三方价格按 slug 在本机目录里匹配，可能与 provider 实际计费有出入。"
        : @"官方价格来自 models.dev / OpenRouter 目录，仅供参考。";
    return [NSString stringWithFormat:@"%@\n%@", [self rateSummaryText], source];
}

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    NSInteger section = (NSInteger)arg2;
    return [NSString stringWithFormat:@"%@ · %lu",
            [self isThirdPartySection:section] ? @"第三方模型" : @"官方模型",
            (unsigned long)[self visibleModelsForSection:section].count];
}

- (void)themeDidChange
{
    [self applyTheme];
    [self reloadRows];
}

- (NSDictionary *)thirdPartyDisplaySnapshot
{
    return _thirdPartyDisplaySnapshot;
}

- (NSArray *)thirdPartyModels
{
    return _thirdPartyModels;
}

- (void)updateSearchResultsForSearchController:(id)arg1
{
    UISearchController *searchController = [arg1 isKindOfClass:UISearchController.class]
        ? (UISearchController *)arg1
        : _searchController;
    NSString *query = searchController.searchBar.text ?: @"";
    _searchQuery = query.length > 0 ? query : nil;

    [self applySearchFilter];
    [self reloadRows];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"模型价格";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self buildTable];
    [self buildNavigationItems];
    [self buildTitleView];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索模型 slug";
    self.searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pricingDidChange:)
                                                 name:CAModelPricingDidChangeNotification
                                               object:nil];

    // 首次进入时价格目录可能还没落盘读出，补一次本地缓存加载
    CAModelPricingManager *manager = [CAModelPricingManager sharedManager];
    if (manager.modelCount == 0) [manager loadCache];

    [self reloadCatalogModels];
    [self prepareDisplaySnapshots];
    [self applyTheme];

    CALog(CALogLevelInfo, @"USAGE", @"model pricing page loaded official=%lu thirdParty=%lu models=%lu",
          (unsigned long)_officialModels.count, (unsigned long)_thirdPartyModels.count, (unsigned long)manager.modelCount);
}

#pragma mark - 界面搭建

- (void)buildTable
{
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 52.0;
    [tableView registerClass:CAModelPricingValueCell.class forCellReuseIdentifier:kModelPricingCellReuseIdentifier];
    [self.view addSubview:tableView];
    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    _pricingTableView = tableView;
}

- (void)buildNavigationItems
{
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(closePage)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"关闭";

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.hidesWhenStopped = YES;
    _syncSpinner = spinner;
    _syncSpinnerItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    _syncItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
                                                 style:UIBarButtonItemStylePlain
                                                target:self
                                                action:@selector(syncPricing)];
    _syncItem.accessibilityLabel = @"同步模型价格";
    self.navigationItem.rightBarButtonItem = _syncItem;
}

- (void)buildTitleView
{
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"模型价格";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.text = [self countText];
    countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    countLabel.textColor = UIColor.secondaryLabelColor;
    countLabel.textAlignment = NSTextAlignmentCenter;
    _countLabel = countLabel;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ titleLabel, countLabel ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 1.0;
    self.navigationItem.titleView = stack;
}

#pragma mark - 数据

- (void)reloadCatalogModels
{
    self.officialModels = [self officialCatalogModels];
    self.thirdPartyModels = [self thirdPartyCatalogModels];
    [self applySearchFilter];
    [self updateCountLabel];
}

- (NSArray<NSString *> *)officialCatalogModels
{
    NSArray<NSString *> *keys = [[CAModelPricingManager sharedManager].prices.allKeys
                                 sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableArray<NSString *> *slugs = [self mixedSlugsFromKeys:keys limit:kModelPricingOfficialLimit];

    // 当前使用的模型必须在列表最前（目录未收录时也要补上）
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *current = [defaults stringForKey:CADefaultsActiveModelSlug];
    if (current.length == 0) current = [defaults stringForKey:CADefaultsSelectedModel];
    if (current.length > 0) {
        [slugs removeObject:current];
        [slugs insertObject:current atIndex:0];
    }

    if (slugs.count == 0) {
        // 目录尚未同步时的兜底候选，保证页面不空屏
        [slugs addObjectsFromArray:@[ @"openai/gpt-5-codex", @"openai/gpt-5", @"anthropic/claude-sonnet-4",
                                      @"google/gemini-2.5-pro", @"deepseek/deepseek-chat" ]];
    }
    return slugs;
}

- (NSArray<NSString *> *)thirdPartyCatalogModels
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableOrderedSet<NSString *> *slugs = [NSMutableOrderedSet orderedSet];

    id stored = [defaults objectForKey:CADefaultsThirdPartyAvailable];
    if ([stored isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)stored) {
            if (![item isKindOfClass:NSString.class]) continue;
            NSString *slug = [(NSString *)item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (slug.length == 0) continue;
            [slugs addObject:slug];
            if (slugs.count >= kModelPricingThirdPartyLimit) break;
        }
    }
    NSString *current = [defaults stringForKey:CADefaultsThirdPartyModel];
    if (current.length > 0) [slugs addObject:current];

    if (slugs.count == 0) {
        // 本机没有第三方目录：先取价格目录里的 openrouter 系列（本身就是第三方聚合），再退回全量轮转
        NSMutableArray<NSString *> *fallback = [NSMutableArray array];
        NSArray<NSString *> *keys = [[CAModelPricingManager sharedManager].prices.allKeys
                                     sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *slug in keys) {
            if (![slug isKindOfClass:NSString.class]) continue;
            if (![slug.lowercaseString hasPrefix:@"openrouter/"]) continue;
            [fallback addObject:slug];
            if (fallback.count >= kModelPricingThirdPartyLimit) break;
        }
        if (fallback.count == 0) {
            [fallback addObjectsFromArray:[self mixedSlugsFromKeys:keys limit:kModelPricingThirdPartyLimit]];
        }
        if (fallback.count > 0) return fallback;
        return @[ @"claude-sonnet-4", @"deepseek-chat", @"qwen3-coder", @"kimi-k2", @"glm-4.6" ];
    }
    return slugs.array;
}

- (NSMutableArray<NSString *> *)mixedSlugsFromKeys:(NSArray<NSString *> *)keys limit:(NSUInteger)limit
{
    // 按 provider 分组：价格目录键形如 "openai/gpt-5"，直接截断前 N 条会退化成单家清单
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *providers = [NSMutableArray array];
    for (NSString *slug in keys) {
        if (![slug isKindOfClass:NSString.class] || slug.length == 0) continue;
        NSString *provider = [self providerHintForSlug:slug] ?: @"未标注";
        NSMutableArray<NSString *> *bucket = groups[provider];
        if (!bucket) {
            bucket = [NSMutableArray array];
            groups[provider] = bucket;
            [providers addObject:provider];
        }
        [bucket addObject:slug];
    }

    // provider 顺序：openai 家族优先，其余按字母序
    [providers sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSString *left = (NSString *)obj1;
        NSString *right = (NSString *)obj2;
        BOOL leftOfficial = [left isEqualToString:@"openai"];
        BOOL rightOfficial = [right isEqualToString:@"openai"];
        if (leftOfficial != rightOfficial) return leftOfficial ? NSOrderedAscending : NSOrderedDescending;
        return [left localizedStandardCompare:right];
    }];

    // 轮转取用：每一轮每个 provider 各出一条，直到取满或取尽
    NSMutableArray<NSString *> *mixed = [NSMutableArray array];
    NSUInteger round = 0;
    while (mixed.count < limit) {
        BOOL added = NO;
        for (NSString *provider in providers) {
            NSMutableArray<NSString *> *bucket = groups[provider];
            if (round >= bucket.count) continue;
            [mixed addObject:bucket[round]];
            added = YES;
            if (mixed.count >= limit) break;
        }
        if (!added) break;
        round += 1;
    }
    return mixed;
}

- (void)applySearchFilter
{
    NSString *query = [_searchQuery stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) {
        _filteredOfficialModels = nil;
        _filteredThirdPartyModels = nil;
        return;
    }
    _filteredOfficialModels = [self modelsInArray:_officialModels matchingQuery:query];
    _filteredThirdPartyModels = [self modelsInArray:_thirdPartyModels matchingQuery:query];
}

- (NSArray<NSString *> *)modelsInArray:(NSArray *)models matchingQuery:(NSString *)query
{
    NSMutableArray<NSString *> *matched = [NSMutableArray array];
    for (id item in models) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *slug = (NSString *)item;
        if ([slug rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [matched addObject:slug];
        }
    }
    return matched;
}

- (void)updateCountLabel
{
    _countLabel.text = [self countText];
}

- (NSString *)countText
{
    return [NSString stringWithFormat:@"官方 %lu · API %lu",
            (unsigned long)_officialModels.count, (unsigned long)_thirdPartyModels.count];
}

- (BOOL)isThirdPartySection:(NSInteger)section
{
    return section == CAModelPricingSectionThirdParty;
}

- (NSArray<NSString *> *)visibleModelsForSection:(NSInteger)section
{
    BOOL thirdParty = [self isThirdPartySection:section];
    if (_searchQuery.length == 0) {
        NSArray *all = thirdParty ? _thirdPartyModels : _officialModels;
        return [all isKindOfClass:NSArray.class] ? all : @[];
    }
    NSArray *filtered = thirdParty ? _filteredThirdPartyModels : _filteredOfficialModels;
    return [filtered isKindOfClass:NSArray.class] ? filtered : @[];
}

- (NSString *)providerHintForSlug:(NSString *)slug
{
    // 价格目录键形如 "openai/gpt-5"，前缀就是 provider 提示
    NSRange slash = [slug rangeOfString:@"/"];
    if (slash.location == NSNotFound || slash.location == 0) return nil;
    return [slug substringToIndex:slash.location];
}

- (NSString *)snapshotTextForSlug:(NSString *)slug providerHint:(NSString *)providerHint
{
    NSDictionary *record = [[CAModelPricingManager sharedManager] pricingForModel:slug providerHint:providerHint];
    if (![record isKindOfClass:NSDictionary.class] || record.count == 0) return @"未收录价格";
    return [self priceLineForRecord:record];
}

- (NSString *)priceLineForRecord:(NSDictionary *)record
{
    NSString *line = [NSString stringWithFormat:@"输入 %@ / 输出 %@",
                      [self usdTextForRate:record[@"inputRate"]],
                      [self usdTextForRate:record[@"outputRate"]]];

    // 每百万 token 的「输入+输出」合计折算人民币（汇率未取到时 displayCNYFromUSD: 返回 nil）
    double inputRate = [record[@"inputRate"] respondsToSelector:@selector(doubleValue)] ? [record[@"inputRate"] doubleValue] : 0;
    double outputRate = [record[@"outputRate"] respondsToSelector:@selector(doubleValue)] ? [record[@"outputRate"] doubleValue] : 0;
    NSString *cny = [CAModelPricingManager displayCNYFromUSD:(inputRate + outputRate)];
    if (cny.length > 0) line = [line stringByAppendingFormat:@" · 合计≈%@", cny];

    return line;
}

- (NSString *)usdTextForRate:(id)rate
{
    if (![rate respondsToSelector:@selector(doubleValue)]) return @"—";
    double value = [rate doubleValue];
    if (!(value > 0)) return @"—";
    return [CAModelPricingManager displayUSD:value];
}

- (NSString *)detailTextForRecord:(NSDictionary *)record
{
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"输入：%@ / 1M tokens", [self usdTextForRate:record[@"inputRate"]]]];
    [lines addObject:[NSString stringWithFormat:@"输出：%@ / 1M tokens", [self usdTextForRate:record[@"outputRate"]]]];
    if ([record[@"cacheReadRate"] respondsToSelector:@selector(doubleValue)]) {
        [lines addObject:[NSString stringWithFormat:@"缓存读：%@ / 1M tokens", [self usdTextForRate:record[@"cacheReadRate"]]]];
    }
    if ([record[@"cacheWriteRate"] respondsToSelector:@selector(doubleValue)]) {
        [lines addObject:[NSString stringWithFormat:@"缓存写：%@ / 1M tokens", [self usdTextForRate:record[@"cacheWriteRate"]]]];
    }
    if ([record[@"reasoningRate"] respondsToSelector:@selector(doubleValue)]) {
        [lines addObject:[NSString stringWithFormat:@"推理输出：%@ / 1M tokens", [self usdTextForRate:record[@"reasoningRate"]]]];
    }
    if ([record[@"max_input_tokens"] respondsToSelector:@selector(unsignedLongLongValue)]) {
        [lines addObject:[NSString stringWithFormat:@"上下文窗口：%llu tokens",
                          [record[@"max_input_tokens"] unsignedLongLongValue]]];
    }

    NSString *provider = record[@"litellm_provider"] ?: record[@"display_name"] ?: record[@"matchedModel"];
    if ([provider isKindOfClass:NSString.class] && provider.length > 0) {
        [lines addObject:[NSString stringWithFormat:@"来源：%@", provider]];
    }
    [lines addObject:[self rateSummaryText]];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)rateSummaryText
{
    CAModelPricingManager *manager = [CAModelPricingManager sharedManager];
    NSString *updated = manager.lastUpdatedAt ? [self timestampText:manager.lastUpdatedAt] : @"未记录";
    if (manager.usdToCNYRate > 0) {
        return [NSString stringWithFormat:@"价格单位：美元 / 每百万 token；汇率 1 USD ≈ %.2f CNY（目录更新时间 %@）。",
                manager.usdToCNYRate, updated];
    }
    return [NSString stringWithFormat:@"价格单位：美元 / 每百万 token；汇率未获取（目录更新时间 %@）。", updated];
}

- (NSString *)timestampText:(NSDate *)date
{
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    });
    return [formatter stringFromDate:date ?: [NSDate date]];
}

#pragma mark - 交互

- (void)setSyncing:(BOOL)syncing
{
    _syncing = syncing;
    if (!_syncItem || !_syncSpinnerItem) return;

    _syncItem.enabled = !syncing;
    if (syncing) {
        [_syncSpinner startAnimating];
        self.navigationItem.rightBarButtonItems = @[ _syncSpinnerItem ];
    } else {
        [_syncSpinner stopAnimating];
        self.navigationItem.rightBarButtonItems = @[ _syncItem ];
    }
}

- (void)presentCandidatesForSlug:(NSString *)slug providerHint:(NSString *)providerHint indexPath:(NSIndexPath *)indexPath
{
    CAModelPricingManager *manager = [CAModelPricingManager sharedManager];

    // 价格档：原包实现了 pricingCandidatesForModel:providerHint:limit: 时优先取全集
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    if ([manager respondsToSelector:@selector(pricingCandidatesForModel:providerHint:limit:)]) {
        id raw = [manager pricingCandidatesForModel:slug providerHint:providerHint limit:@(kModelPricingCandidateLimit)];
        if ([raw isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)raw) {
                if ([item isKindOfClass:NSDictionary.class]) [candidates addObject:item];
            }
        }
    }
    NSDictionary *current = [manager pricingForModel:slug providerHint:providerHint];
    if (candidates.count == 0 && [current isKindOfClass:NSDictionary.class]) {
        [candidates addObject:current];
    }

    NSString *message = candidates.count > 0
        ? [NSString stringWithFormat:@"命中 %lu 条价格档", (unsigned long)candidates.count]
        : @"本机目录暂未收录该模型的价格";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:slug
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    for (NSDictionary *record in candidates) {
        NSString *title = [self candidateTitle:record];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf presentCandidateDetail:record slug:slug];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"在 models.dev 查看（只读）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf openModelsDevForSlug:slug];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = _pricingTableView;
        sheet.popoverPresentationController.sourceRect = indexPath && _pricingTableView
            ? [_pricingTableView rectForRowAtIndexPath:indexPath]
            : _pricingTableView.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentCandidateDetail:(NSDictionary *)record slug:(NSString *)slug
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:slug
                                                                  message:[self detailTextForRecord:record]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    NSString *line = [self priceLineForRecord:record];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制价格行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ · %@", slug, line];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openModelsDevForSlug:(NSString *)slug
{
    NSString *encoded = [slug stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: slug;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://models.dev/?q=%@", encoded]];
    if (!url) return;

    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    CALog(CALogLevelInfo, @"USAGE", @"model pricing open models.dev slug=%@", slug);
}

- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
