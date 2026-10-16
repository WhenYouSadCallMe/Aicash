//
//  CAModelPickerViewController.m
//
//  模型选择面板（原包：输入框上方「6.1-Sol ▾」模型胶囊点开后的选择页）。
//
//  分区：
//    0 官方模型   —— CAModelPricingManager.sharedManager.prices 的键（过滤明显非对话模型），
//                    并并入 defaults CodexActiveModelSlug / CodexSelectedModel，保证当前值一定在列表里
//    1 第三方模型 —— defaults CodexThirdPartyAvailableModels；为空时退回 prices 全量前 20 条
//
//  每行：模型 slug（等宽字体）+ 右侧推理强度小字（supportedReasoningEffortsForModel:providerHint: 拼接，
//        取不到时退化为 defaults 里的强度值），当前选中项显示蓝色对勾。
//
//  点击行：官方写 CodexSelectedModel + CodexActiveModelSlug，第三方写 CodexThirdPartyModel，
//          有 onModelSelected（void(^)(NSString *slug, BOOL thirdParty)）时回调，然后 closePicker 收起。
//
//  方法签名逐字沿用头文件（参数统一 id 占位），所以每个方法第一行先强转再用。
//

#import "CAModelPickerViewController.h"
#import "CACommon.h"
#import "CAModelPricingManager.h"

static NSString * const kModelPickerCellReuseIdentifier = @"CAModelPickerCell";

/// 官方分区最多展示的条数（目录可能有上千条，面板只列前面一段）
static const NSUInteger kModelPickerOfficialLimit = 40;

/// 第三方分区退回 prices 时最多展示的条数
static const NSUInteger kModelPickerThirdPartyLimit = 20;

typedef NS_ENUM(NSInteger, CAModelPickerSection) {
    CAModelPickerSectionOfficial = 0,
    CAModelPickerSectionThirdParty,
    CAModelPickerSectionCount,
};

/// 统一使用 UITableViewCellStyleValue1（左侧 slug + 右侧推理强度）
@interface CAModelPickerValueCell : UITableViewCell
@end

@implementation CAModelPickerValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

#pragma mark - 模型选择面板

@interface CAModelPickerViewController () <UITableViewDataSource, UITableViewDelegate>
{
    // 头文件已声明的 setter/getter 对应状态：ivar + 手写访问器（避免与头文件选择器冲突）
    id _onModelSelected;
    UITableView *_tableView;

    // 面板自身的展示状态
    NSArray<NSString *> *_officialSlugs;
    NSArray<NSString *> *_thirdPartySlugs;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;

#pragma mark 内部实现

- (void)applyThemeColors;
- (BOOL)isThirdPartySection:(NSInteger)section;
- (BOOL)isNonChatSlug:(NSString *)slug;
- (NSString *)slugAtIndexPath:(NSIndexPath *)indexPath;
- (NSMutableArray<NSString *> *)mixedSlugsFromKeys:(NSArray<NSString *> *)keys limit:(NSUInteger)limit;
- (NSString *)providerHintForSlug:(NSString *)slug;
- (NSString *)selectedOfficialSlug;
- (NSString *)selectedThirdPartySlug;
- (NSString *)reasoningSummaryForSlug:(NSString *)slug thirdParty:(BOOL)thirdParty;
- (void)applySelectionAtIndexPath:(NSIndexPath *)indexPath;

@end

@implementation CAModelPickerViewController

- (void)closePicker
{
    // 作为 push 页面时回退导航栈，作为模态根时直接收起
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (id)onModelSelected
{
    return _onModelSelected;
}

- (void)setOnModelSelected:(id)arg1
{
    // ARC 下把 block 存进强引用 id ivar 会自动搬到堆上
    _onModelSelected = arg1;
}

- (void)setTableView:(id)arg1
{
    _tableView = (UITableView *)arg1;
}

- (UITableView *)tableView
{
    return _tableView;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = (UITableView *)arg1;
    NSIndexPath *indexPath = (NSIndexPath *)arg2;

    CAModelPickerValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kModelPickerCellReuseIdentifier
                                                                 forIndexPath:indexPath];
    if (!cell) {
        cell = [[CAModelPickerValueCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                             reuseIdentifier:kModelPickerCellReuseIdentifier];
    }

    BOOL thirdParty = [self isThirdPartySection:indexPath.section];
    NSString *slug = [self slugAtIndexPath:indexPath];

    cell.textLabel.text = slug ?: @"";
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.minimumScaleFactor = 0.75;

    // 副标题：仅显示推理档位（短格式），换行交给 Subtitle 样式的多行 detailTextLabel
    cell.detailTextLabel.text = [self reasoningSummaryForSlug:slug thirdParty:thirdParty];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 1;

    NSString *current = thirdParty ? [self selectedThirdPartySlug] : [self selectedOfficialSlug];
    BOOL selected = slug.length > 0 && [slug isEqualToString:current];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
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
    [self applySelectionAtIndexPath:indexPath];
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    // arg2 实际是 NSInteger 分区号（占位声明成 id），按整数取用
    NSInteger section = (NSInteger)arg2;
    NSUInteger count = [self isThirdPartySection:section] ? _thirdPartySlugs.count : _officialSlugs.count;
    return (signed long long)count;
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = (NSInteger)arg2;
    if ([self isThirdPartySection:section]) {
        return @"第三方模型来自本机 provider 的可用模型清单（CodexThirdPartyAvailableModels）。价格来自 models.dev / OpenRouter 目录，仅供参考。";
    }
    return @"价格来自 models.dev / OpenRouter 目录，仅供参考。";
}

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    NSInteger section = (NSInteger)arg2;
    return [self isThirdPartySection:section] ? @"第三方模型" : @"官方模型";
}

- (void)themeDidChange
{
    [self applyThemeColors];
    [_tableView reloadData];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"选择模型";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(closePicker)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"关闭";

    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = UITableViewAutomaticDimension;
    tableView.estimatedRowHeight = 48.0;
    [tableView registerClass:CAModelPickerValueCell.class forCellReuseIdentifier:kModelPickerCellReuseIdentifier];
    [self.view addSubview:tableView];
    [NSLayoutConstraint activateConstraints:@[
        [tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.tableView = tableView;

    [self applyThemeColors];
    [self rebuildSlugs];

    CALog(CALogLevelInfo, @"GENERAL", @"model picker loaded official=%lu thirdParty=%lu",
          (unsigned long)_officialSlugs.count, (unsigned long)_thirdPartySlugs.count);
}

- (void)viewWillAppear:(id)arg1
{
    // BOOL 形参在 arm64 上就落在 x1，占位 id 非空即 YES——还原成 BOOL 传给 super
    [super viewWillAppear:arg1 != nil];

    // 回到面板时重算候选与选中态：期间模型目录可能刚同步过
    [self applyThemeColors];
    [self rebuildSlugs];
    [_tableView reloadData];
}

#pragma mark - UITableViewDataSource（可选方法）

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // 未配置第三方 provider 时只显示官方分区（原版行为：第三方列表为空则不渲染该分区）
    return _thirdPartySlugs.count > 0 ? CAModelPickerSectionCount : 1;
}

#pragma mark - 内部实现

- (void)rebuildSlugs
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    // 官方：内置 models.json（原包资源，8 个官方 slug）——顺序与原包一致
    NSMutableArray<NSString *> *official = [NSMutableArray array];
    NSString *modelsPath = [NSBundle.mainBundle pathForResource:@"models" ofType:@"json"];
    NSData *modelsData = modelsPath ? [NSData dataWithContentsOfFile:modelsPath] : nil;
    if (modelsData) {
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:modelsData options:0 error:NULL];
        NSArray<NSDictionary *> *models = payload[@"models"];
        if ([models isKindOfClass:NSArray.class]) {
            for (NSDictionary *m in models) {
                NSString *slug = m[@"slug"];
                if ([slug isKindOfClass:NSString.class] && slug.length > 0) [official addObject:slug];
            }
        }
    }
    // 当前值必须出现在列表最前（目录未收录当前模型时也要补上）
    for (NSString *current in @[ [defaults stringForKey:CADefaultsActiveModelSlug] ?: @"",
                                 [defaults stringForKey:CADefaultsSelectedModel] ?: @"" ]) {
        if (current.length == 0) continue;
        [official removeObject:current];
        [official insertObject:current atIndex:0];
    }
    if (official.count == 0) {
        // models.json 缺失时的兜底
        [official addObjectsFromArray:@[ @"gpt-6.1-sol", @"gpt-6-sol", @"gpt-6-luna", @"gpt-5.6-sol", @"gpt-5.6-terra", @"gpt-5.6-luna", @"gpt-5.5", @"gpt-6-astra" ]];
    }
    _officialSlugs = official;

    // 第三方：仅取本机 provider 探测到的可用模型；未配置就保持空（不冒充官方清单）
    NSMutableOrderedSet<NSString *> *thirdParty = [NSMutableOrderedSet orderedSet];
    id stored = [defaults objectForKey:CADefaultsThirdPartyAvailable];
    if ([stored isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)stored) {
            if (![item isKindOfClass:NSString.class]) continue;
            NSString *slug = [(NSString *)item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (slug.length == 0) continue;
            [thirdParty addObject:slug];
            if (thirdParty.count >= kModelPickerThirdPartyLimit) break;
        }
    }
    _thirdPartySlugs = thirdParty.array;
}

- (void)applyThemeColors
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.separatorColor = UIColor.separatorColor;
    self.navigationController.navigationBar.tintColor = UIColor.systemBlueColor;
}

- (BOOL)isThirdPartySection:(NSInteger)section
{
    return section == CAModelPickerSectionThirdParty;
}

- (BOOL)isNonChatSlug:(NSString *)slug
{
    static NSArray<NSString *> *keywords;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keywords = @[ @"embed", @"whisper", @"tts", @"moderation", @"dall-e", @"rerank", @"transcribe",
                      @"realtime", @"speech", @"audio", @"image", @"video", @"sora", @"ocr",
                      @"davinci", @"babbage", @"curie", @"text-ada", @"stable-diffusion", @"flux" ];
    });
    NSString *lowered = slug.lowercaseString;
    for (NSString *keyword in keywords) {
        if ([lowered containsString:keyword]) return YES;
    }
    return NO;
}

- (NSString *)slugAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray<NSString *> *rows = [self isThirdPartySection:indexPath.section] ? _thirdPartySlugs : _officialSlugs;
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= rows.count) return nil;
    return rows[(NSUInteger)indexPath.row];
}

- (NSMutableArray<NSString *> *)mixedSlugsFromKeys:(NSArray<NSString *> *)keys limit:(NSUInteger)limit
{
    // 按 provider 分组：价格目录键形如 "openai/gpt-5"，同家模型太多时面板会退化成单家清单
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *providers = [NSMutableArray array];
    for (NSString *slug in keys) {
        if (![slug isKindOfClass:NSString.class] || slug.length == 0) continue;
        if ([self isNonChatSlug:slug]) continue;
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

- (NSString *)providerHintForSlug:(NSString *)slug
{
    // 价格目录键形如 "openai/gpt-5"，前缀就是 provider 提示
    NSRange slash = [slug rangeOfString:@"/"];
    if (slash.location == NSNotFound || slash.location == 0) return nil;
    return [slug substringToIndex:slash.location];
}

- (NSString *)selectedOfficialSlug
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *active = [defaults stringForKey:CADefaultsActiveModelSlug];
    if (active.length > 0) return active;
    NSString *selected = [defaults stringForKey:CADefaultsSelectedModel];
    NSString *thirdParty = [defaults stringForKey:CADefaultsThirdPartyModel];
    if (selected.length > 0 && ![selected isEqualToString:thirdParty ?: @""]) return selected;
    return @"";
}

- (NSString *)selectedThirdPartySlug
{
    return [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsThirdPartyModel] ?: @"";
}

- (NSString *)reasoningSummaryForSlug:(NSString *)slug thirdParty:(BOOL)thirdParty
{
    if (slug.length == 0) return @"";

    NSArray<NSString *> *levels = [[CAModelPricingManager sharedManager] supportedReasoningEffortsForModel:slug
                                                                                             providerHint:[self providerHintForSlug:slug]];
    if (levels.count == 0) {
        // 目录查不到：不显示长兜底串，保持行内干净（默认档位在强度面板里可选）
        return nil;
    }
    NSMutableArray<NSString *> *shown = [NSMutableArray array];
    for (NSString *level in levels) {
        if (![level isKindOfClass:NSString.class] || level.length == 0) continue;
        [shown addObject:level];
        if (shown.count >= 3) break;
    }
    NSString *text = [shown componentsJoinedByString:@" / "];
    return levels.count > shown.count ? [text stringByAppendingString:@" …"] : text;
}

- (void)applySelectionAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *slug = [self slugAtIndexPath:indexPath];
    if (slug.length == 0) return;

    BOOL thirdParty = [self isThirdPartySection:indexPath.section];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (thirdParty) {
        [defaults setObject:slug forKey:CADefaultsThirdPartyModel];
    } else {
        [defaults setObject:slug forKey:CADefaultsSelectedModel];
        [defaults setObject:slug forKey:CADefaultsActiveModelSlug];
    }

    CALog(CALogLevelInfo, @"GENERAL", @"model picker selected slug=%@ thirdParty=%d", slug, thirdParty ? 1 : 0);

    id handler = _onModelSelected;
    if (handler) {
        void (^callback)(NSString *, BOOL) = (void (^)(NSString *, BOOL))handler;
        callback(slug, thirdParty);
    }

    [_tableView reloadData];
    [self closePicker];
}

@end
