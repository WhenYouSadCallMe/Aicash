//
//  CASubagentSettingsViewController — 子代理设置（模型与思考强度）
//
//  真实视图层级：UITableViewStyleInsetGrouped 分组表格
//      · 分区 0「模型」：一行显示当前子代理模型（右侧 ›）
//      · 分区 1「思考强度」：一行显示当前强度中文名（右侧 ›）
//      · 分区 2「说明」：只读说明行
//  真实数据来源：
//    · defaults 复刻补充键 CodexSubagentModel → 空则回退 CodexSelectedModel（主代理模型）
//    · defaults 复刻补充键 CodexSubagentReasoningEffort → 空则回退 CodexReasoningEffort
//    · 可用强度：CAModelPricingManager -supportedReasoningEffortsForModel:providerHint:
//      → 空则 CAThirdPartyModelCatalog +reasoningLevels → 再空用内置 minimal/low/medium/high
//    · thirdParty：defaults CodexUseThirdPartyProvider
//
//  说明：头文件把原包选择器生成成了 id 占位参数，这里逐字沿用头文件签名，
//        函数体第一行再强转成真实类型使用，避免 -Wmismatched-parameter-types。
//

#import "CASubagentSettingsViewController.h"
#import "CACommon.h"
#import "CACodexEngine.h"
#import "CAModelPricingManager.h"

static NSString *const kCASubagentValueCellReuseIdentifier = @"CASubagentValueCell";

/// 复刻补充键（原包无此键）：子代理专属模型 / 强度；读取时先读它们，为空再回退主代理键
static NSString *const kCASubagentModelDefaultsKey = @"CodexSubagentModel";
static NSString *const kCASubagentEffortDefaultsKey = @"CodexSubagentReasoningEffort";

/// 选项字典的 kind / value 键（presentOptions: 内部使用）
static NSString *const kCASubagentOptionKindKey = @"kind";
static NSString *const kCASubagentOptionValueKey = @"value";
static NSString *const kCASubagentOptionKindEffort = @"effort";

/// 选项表最多展示多少个候选模型
static const NSUInteger kCASubagentModelOptionLimit = 20;

typedef NS_ENUM(NSInteger, CASubagentSection) {
    CASubagentSectionModel = 0,
    CASubagentSectionEffort,
    CASubagentSectionNotes,
    CASubagentSectionCount,
};

typedef NS_ENUM(NSInteger, CASubagentModelRow) {
    CASubagentModelRowCurrent = 0,
    CASubagentModelRowCount,
};

typedef NS_ENUM(NSInteger, CASubagentEffortRow) {
    CASubagentEffortRowCurrent = 0,
    CASubagentEffortRowCount,
};

typedef NS_ENUM(NSInteger, CASubagentNotesRow) {
    CASubagentNotesRowInherit = 0,
    CASubagentNotesRowScope,
    CASubagentNotesRowCount,
};

/// 统一使用 UITableViewCellStyleValue1（左侧标题 + 右侧详情）
@interface CASubagentValueCell : UITableViewCell
@end

@implementation CASubagentValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

/// 头文件把原包的 NSInteger 参数生成成了 id：同时兼容「原始整数位」与「NSNumber」两种调用
static NSInteger CASubagentSignedArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits < 0x1000) return (NSInteger)bits;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument integerValue];
    if ([argument isKindOfClass:NSString.class]) return [(NSString *)argument integerValue];
    return 0;
}

/// 头文件把原包的 bool 参数生成成了 id：同时兼容「原始 0/1 位」与「NSNumber」两种调用
static BOOL CASubagentBooleanArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits == 0) return NO;
    if (bits == 1) return YES;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument boolValue];
    if ([argument isKindOfClass:NSString.class]) return [(NSString *)argument boolValue];
    return YES;
}

/// 强度档位中文名（复刻原包语气；未知档位回退 CAThirdPartyModelCatalog 的原包档位名）
static NSDictionary<NSString *, NSString *> *CASubagentEffortTitles(void)
{
    static NSDictionary<NSString *, NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{
            @"none":    @"无",
            @"minimal": @"最小",
            @"low":     @"低",
            @"medium":  @"中",
            @"high":    @"高",
            @"xhigh":   @"极高",
            @"max":     @"最大",
            @"ultra":   @"极限",
        };
    });
    return titles;
}

@interface CASubagentSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
{
    CACodexEngine *_contextEngine;
    UITableView *_tableView;
}

- (void)handleClose;
- (NSString *)subagentEffort;
- (NSArray<NSString *> *)modelCandidates;
- (void)presentModelOptions;
- (void)presentEffortOptions;
- (void)showMessage:(NSString *)message title:(NSString *)title;
- (NSString *)trimmedString:(NSString *)string;

@end

@implementation CASubagentSettingsViewController

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"子代理设置";

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 50.0;
    [_tableView registerClass:CASubagentValueCell.class forCellReuseIdentifier:kCASubagentValueCellReuseIdentifier];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(handleClose)];

    [self refresh];
}

- (void)viewWillAppear:(id)arg1
{
    [super viewWillAppear:CASubagentBooleanArgument(arg1)];
    [self refresh];
}

#pragma mark - 交互

- (void)handleClose
{
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)trimmedString:(NSString *)string
{
    return [(string ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

#pragma mark - 数据

- (id)contextEngine
{
    return _contextEngine;
}

- (void)setContextEngine:(id)arg1
{
    _contextEngine = [arg1 isKindOfClass:CACodexEngine.class] ? (CACodexEngine *)arg1 : nil;
}

- (id)effectiveContextEngine
{
    CACodexEngine *engine = [self contextEngine];
    if ([engine isKindOfClass:CACodexEngine.class]) return engine;
    return [CACodexEngine sharedEngine];
}

- (bool)thirdParty
{
    return [NSUserDefaults.standardUserDefaults boolForKey:CADefaultsUseThirdPartyProvider] ? YES : NO;
}

- (id)selectedModel
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // 复刻补充键优先：CodexSubagentModel；为空回退主代理模型 CodexSelectedModel
    NSString *model = [self trimmedString:[defaults stringForKey:kCASubagentModelDefaultsKey]];
    if (!model.length) model = [self trimmedString:[defaults stringForKey:CADefaultsSelectedModel]];
    if (!model.length) model = [self trimmedString:[defaults stringForKey:CADefaultsActiveModelSlug]];
    if (!model.length) {
        CACodexEngine *engine = [self effectiveContextEngine];
        model = [self trimmedString:engine.thirdPartyModel];
    }
    return model ?: @"";
}

/// 当前思考强度（复刻补充键优先，回退主代理强度键）
- (NSString *)subagentEffort
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *effort = [self trimmedString:[defaults stringForKey:kCASubagentEffortDefaultsKey]];
    if (!effort.length) effort = [self trimmedString:[defaults stringForKey:CADefaultsReasoningEffort]];
    if (!effort.length) effort = [self trimmedString:[defaults stringForKey:CADefaultsActiveEffort]];
    if (!effort.length) effort = @"medium";
    return effort;
}

- (id)efforts
{
    NSString *model = [self selectedModel];
    NSString *providerHint = [self thirdParty] ? @"third-party" : nil;

    // 优先：模型价格目录里该模型支持的档位
    NSArray<NSString *> *supported = [[CAModelPricingManager sharedManager] supportedReasoningEffortsForModel:model
                                                                                                 providerHint:providerHint];
    if ([supported isKindOfClass:NSArray.class] && supported.count) return supported;

    // 退回：原包第三方目录档位
    NSArray<NSString *> *levels = [CAThirdPartyModelCatalog reasoningLevels];
    if (levels.count) return levels;

    // 再退回：内置最小集合
    return @[ @"minimal", @"low", @"medium", @"high" ];
}

- (id)effortTitle:(id)arg1
{
    NSString *level = nil;
    if ([arg1 isKindOfClass:NSString.class]) level = [self trimmedString:(NSString *)arg1];
    else if ([arg1 isKindOfClass:NSNumber.class]) level = [(NSNumber *)arg1 stringValue];
    if (!level.length) return @"中";

    NSString *title = CASubagentEffortTitles()[level.lowercaseString];
    if (title.length) return title;

    // 兜底：原包档位名（CAThirdPartyModelCatalog 只提供英文档位名）
    NSString *catalogTitle = [CAThirdPartyModelCatalog reasoningLevelTitle:level];
    return catalogTitle.length ? catalogTitle : level;
}

- (id)modelItem
{
    NSString *model = [self selectedModel];
    return @{
        @"title": @"子代理模型",
        @"detail": model.length ? model : @"跟随主代理",
        @"value": model ?: @"",
    };
}

- (void)refresh
{
    // 全部字段都是 defaults 直读，重新读盘 + 整表刷新即可
    [_tableView reloadData];
    CALog(CALogLevelDebug, @"GENERAL", @"subagent settings refreshed model=%@ effort=%@ thirdParty=%d",
          [self selectedModel], [self subagentEffort], [self thirdParty] ? 1 : 0);
}

- (void)selectModel:(id)arg1
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *value = nil;
    BOOL isEffort = NO;

    if ([arg1 isKindOfClass:NSString.class]) {
        value = [self trimmedString:(NSString *)arg1];
    } else if ([arg1 isKindOfClass:NSNumber.class]) {
        value = [(NSNumber *)arg1 stringValue];
    } else if ([arg1 isKindOfClass:NSDictionary.class]) {
        NSDictionary *option = (NSDictionary *)arg1;
        id kind = option[kCASubagentOptionKindKey];
        id raw = option[kCASubagentOptionValueKey];
        value = [raw isKindOfClass:NSString.class] ? [self trimmedString:(NSString *)raw]
                                                   : (raw ? [raw description] : nil);
        isEffort = [kind isKindOfClass:NSString.class] && [(NSString *)kind isEqualToString:kCASubagentOptionKindEffort];
    }

    if (!value.length) return;

    if (isEffort) {
        // 强度落盘：CodexSubagentReasoningEffort（复刻补充键）
        [defaults setObject:value forKey:kCASubagentEffortDefaultsKey];
        CALog(CALogLevelInfo, @"GENERAL", @"subagent effort saved level=%@", value);
    } else {
        // 模型落盘：CodexSubagentModel（复刻补充键，仅影响子代理，主代理仍是 CodexSelectedModel）
        [defaults setObject:value forKey:kCASubagentModelDefaultsKey];
        CALog(CALogLevelInfo, @"GENERAL", @"subagent model saved slug=%@", value);
    }

    [self refresh];
}

- (NSArray<NSString *> *)modelCandidates
{
    NSMutableOrderedSet<NSString *> *slugs = [NSMutableOrderedSet orderedSet];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    id available = [defaults objectForKey:CADefaultsThirdPartyAvailable];
    if ([available isKindOfClass:NSArray.class]) {
        for (id slug in (NSArray *)available) {
            if ([slug isKindOfClass:NSString.class] && [(NSString *)slug length] > 0) [slugs addObject:slug];
        }
    }

    CACodexEngine *engine = [self effectiveContextEngine];
    for (NSString *slug in engine.thirdPartyAvailableModels) {
        if ([slug isKindOfClass:NSString.class] && slug.length > 0) [slugs addObject:slug];
    }

    for (NSString *slug in [CAModelPricingManager sharedManager].prices.allKeys) {
        if (slug.length > 0) [slugs addObject:slug];
    }

    NSString *current = [self selectedModel];
    if (current.length) [slugs addObject:current];
    NSString *primary = [self trimmedString:[defaults stringForKey:CADefaultsSelectedModel]];
    if (primary.length) [slugs addObject:primary];

    return slugs.array;
}

#pragma mark - 选项弹窗

- (void)presentModelOptions
{
    NSArray<NSString *> *candidates = [self modelCandidates];
    NSString *current = [self selectedModel];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"子代理模型"
                                                                  message:[NSString stringWithFormat:@"候选 %lu 个 · 当前 %@",
                                                                           (unsigned long)candidates.count,
                                                                           current.length ? current : @"跟随主代理"]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    NSUInteger shown = 0;
    for (NSString *slug in candidates) {
        if (shown >= kCASubagentModelOptionLimit) break;
        shown += 1;
        NSString *title = [slug isEqualToString:current] ? [NSString stringWithFormat:@"✓ %@", slug] : slug;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self selectModel:slug];
        }]];
    }
    if (!candidates.count) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"暂无候选，先刷新一次模型目录" style:UIAlertActionStyleDefault handler:nil]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"跟随主代理（清除子代理覆盖）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCASubagentModelDefaultsKey];
        [self refresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _tableView;
    sheet.popoverPresentationController.sourceRect = _tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentEffortOptions
{
    NSArray *levels = [self efforts];
    NSString *current = [self subagentEffort];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"思考强度"
                                                                  message:[NSString stringWithFormat:@"当前 %@（%@）",
                                                                           [self effortTitle:current], current]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    for (id rawLevel in levels) {
        NSString *level = [rawLevel isKindOfClass:NSString.class] ? (NSString *)rawLevel : [rawLevel description];
        if (!level.length) continue;
        NSString *title = [NSString stringWithFormat:@"%@（%@）", [self effortTitle:level], level];
        if ([level isEqualToString:current]) title = [NSString stringWithFormat:@"✓ %@", title];
        NSDictionary *option = @{ kCASubagentOptionKindKey: kCASubagentOptionKindEffort, kCASubagentOptionValueKey: level };
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self selectModel:option];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _tableView;
    sheet.popoverPresentationController.sourceRect = _tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentOptions:(id)arg1 cell:(id)arg2
{
    UITableViewCell *cell = [arg2 isKindOfClass:UITableViewCell.class] ? (UITableViewCell *)arg2 : nil;
    NSIndexPath *indexPath = cell ? [_tableView indexPathForCell:cell] : nil;
    if (!indexPath && [arg1 isKindOfClass:NSIndexPath.class]) indexPath = (NSIndexPath *)arg1;

    NSInteger section = indexPath ? indexPath.section : CASubagentSectionModel;
    if ((CASubagentSection)section == CASubagentSectionEffort) {
        [self presentEffortOptions];
        return;
    }
    [self presentModelOptions];
}

#pragma mark - UITableViewDataSource

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)CASubagentSectionCount;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = CASubagentSignedArgument(arg2);

    switch ((CASubagentSection)section) {
        case CASubagentSectionModel:
            return (signed long long)CASubagentModelRowCount;
        case CASubagentSectionEffort:
            return (signed long long)CASubagentEffortRowCount;
        case CASubagentSectionNotes:
            return (signed long long)CASubagentNotesRowCount;
        default:
            return 0;
    }
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;

    if (!tableView || !indexPath) {
        return [[CASubagentValueCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    }

    CASubagentValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kCASubagentValueCellReuseIdentifier
                                                               forIndexPath:indexPath];
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = @"";
    cell.textLabel.textColor = UIColor.labelColor;
    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    switch ((CASubagentSection)indexPath.section) {
        case CASubagentSectionModel: {
            NSString *model = [self selectedModel];
            cell.textLabel.text = @"子代理模型";
            cell.detailTextLabel.text = model.length ? model : @"跟随主代理";
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"cpu"];
            cell.imageView.tintColor = UIColor.secondaryLabelColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case CASubagentSectionEffort: {
            NSString *effort = [self subagentEffort];
            cell.textLabel.text = @"思考强度";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@（%@）", [self effortTitle:effort], effort];
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.imageView.image = [UIImage systemImageNamed:@"brain"];
            cell.imageView.tintColor = UIColor.secondaryLabelColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case CASubagentSectionNotes:
        default: {
            if (indexPath.row == CASubagentNotesRowInherit) {
                cell.textLabel.text = @"继承规则";
                cell.detailTextLabel.text = @"子代理默认继承主代理模型";
            } else {
                cell.textLabel.text = @"覆盖范围";
                cell.detailTextLabel.text = @"仅子代理生效，主代理不受影响";
            }
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = CASubagentSignedArgument(arg2);

    switch ((CASubagentSection)section) {
        case CASubagentSectionModel:
            return @"不指定时子代理沿用主代理模型（CodexSelectedModel）。";
        case CASubagentSectionEffort:
            return @"强度覆盖只写入子代理键 CodexSubagentReasoningEffort，未设置时回退主代理强度。";
        case CASubagentSectionNotes:
        default:
            return @"子代理默认继承主代理模型与思考强度，除非在此单独指定；两个覆盖键分别为 CodexSubagentModel 与 CodexSubagentReasoningEffort。";
    }
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    NSInteger section = CASubagentSignedArgument(arg2);
    if ((CASubagentSection)section == CASubagentSectionNotes) return 62.0;
    if ((CASubagentSection)section == CASubagentSectionEffort) return 46.0;
    return UITableViewAutomaticDimension;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return;

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ((CASubagentSection)indexPath.section == CASubagentSectionNotes) {
        [self showMessage:[NSString stringWithFormat:@"子代理模型：%@\n思考强度：%@（%@）\n\n%@",
                           [self modelItem][@"detail"],
                           [self effortTitle:[self subagentEffort]],
                           [self subagentEffort],
                           @"子代理默认继承主代理模型与思考强度，除非在此单独指定。"]
                    title:@"子代理设置"];
        return;
    }
    [self presentOptions:indexPath cell:cell];
}

@end
