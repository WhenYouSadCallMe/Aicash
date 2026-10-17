//
//  CAUsageViewController - quota and token usage sheet.
//

#import "CAUsageViewController.h"
#import "CACodexEngine.h"
#import "CAConversationStore.h"
#import "CARateLimitManager.h"
#import "CARuntimePaths.h"

@interface CAUsageViewController () {
    CACodexEngine *_engine;
    CAConversationRecord *_record;
    UIStackView *_stackView;
    UIView *_header;
    UILabel *_titleLabel;
    UILabel *_planLabel;
    UILabel *_statusLabel;
    UIButton *_closeButton;
    UIButton *_refreshButton;
    UIActivityIndicatorView *_spinner;
    unsigned long long _quotaRefreshGeneration;
    BOOL _refreshing;
}
@end

@implementation CAUsageViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _engine = CACodexEngine.sharedEngine;
    [self buildLayout];
    [self applyTheme];
    [self reloadSnapshot];
}

- (void)buildLayout
{
    _header = [[UIView alloc] initWithFrame:CGRectZero];
    _header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_header];

    _closeButton = [self buttonWithSymbol:@"xmark" label:@"关闭" action:NSStringFromSelector(@selector(closePage))];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _closeButton.layer.cornerRadius = 15.0;
    [_header addSubview:_closeButton];

    _refreshButton = [self buttonWithSymbol:@"arrow.clockwise" label:@"刷新" action:NSStringFromSelector(@selector(refreshQuota))];
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_header addSubview:_refreshButton];

    _titleLabel = [self labelWithSize:@20 weight:@(UIFontWeightSemibold) secondary:@NO];
    _titleLabel.text = @"用量";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_header addSubview:_titleLabel];

    _planLabel = [self labelWithSize:@13 weight:@(UIFontWeightRegular) secondary:@YES];
    _planLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_header addSubview:_planLabel];

    _statusLabel = [self labelWithSize:@13 weight:@(UIFontWeightRegular) secondary:@YES];
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_header addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    [_header addSubview:_spinner];

    _stackView = [[UIStackView alloc] init];
    _stackView.axis = UILayoutConstraintAxisVertical;
    _stackView.spacing = 12.0;
    _stackView.alignment = UIStackViewAlignmentFill;
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [_header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_header.heightAnchor constraintEqualToConstant:100.0],
        [_closeButton.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor],
        [_closeButton.topAnchor constraintEqualToAnchor:_header.topAnchor],
        [_closeButton.widthAnchor constraintEqualToConstant:32.0],
        [_closeButton.heightAnchor constraintEqualToConstant:30.0],
        [_refreshButton.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor],
        [_refreshButton.topAnchor constraintEqualToAnchor:_header.topAnchor],
        [_refreshButton.widthAnchor constraintEqualToConstant:32.0],
        [_refreshButton.heightAnchor constraintEqualToConstant:30.0],
        [_titleLabel.centerXAnchor constraintEqualToAnchor:_header.centerXAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:_header.topAnchor constant:2.0],
        [_planLabel.centerXAnchor constraintEqualToAnchor:_header.centerXAnchor],
        [_planLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_planLabel.bottomAnchor constant:12.0],
        [_spinner.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_stackView.topAnchor constraintEqualToAnchor:_header.bottomAnchor constant:4.0],
        [_stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_stackView.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16.0],
    ]];
}

- (id)labelWithSize:(id)size weight:(id)weight secondary:(id)secondary
{
    CGFloat pointSize = [size respondsToSelector:@selector(doubleValue)] ? [size doubleValue] : 15.0;
    CGFloat fontWeight = [weight respondsToSelector:@selector(doubleValue)] ? [weight doubleValue] : UIFontWeightRegular;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:pointSize weight:fontWeight];
    label.textColor = [secondary respondsToSelector:@selector(boolValue)] && [secondary boolValue] ? UIColor.secondaryLabelColor : UIColor.labelColor;
    return label;
}

- (id)buttonWithSymbol:(id)symbol label:(id)label action:(id)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *name = [symbol isKindOfClass:NSString.class] ? symbol : @"circle";
    [button setImage:[UIImage systemImageNamed:name] forState:UIControlStateNormal];
    button.accessibilityLabel = [label isKindOfClass:NSString.class] ? label : name;
    if ([action isKindOfClass:NSString.class]) [button addTarget:self action:NSSelectorFromString(action) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)applyTheme
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _titleLabel.textColor = UIColor.labelColor;
    _planLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _closeButton.tintColor = UIColor.whiteColor;
    _closeButton.backgroundColor = UIColor.systemGrayColor;
    _refreshButton.tintColor = UIColor.systemBlueColor;
    for (UIView *view in _stackView.arrangedSubviews) [self applyThemeToView:view];
}

- (void)applyThemeToView:(id)arg1
{
    if ([arg1 isKindOfClass:UILabel.class]) ((UILabel *)arg1).textColor = UIColor.labelColor;
    if ([arg1 isKindOfClass:UIProgressView.class]) {
        ((UIProgressView *)arg1).progressTintColor = UIColor.systemBlueColor;
        ((UIProgressView *)arg1).trackTintColor = UIColor.tertiarySystemFillColor;
    }
    if ([arg1 isKindOfClass:UIView.class]) {
        for (UIView *child in ((UIView *)arg1).subviews) [self applyThemeToView:child];
    }
}

- (void)themeDidChange { [self applyTheme]; }
- (void)closePage { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSString *)usageTokenString:(id)value
{
    unsigned long long tokens = [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0;
    if (tokens >= 1000000000ULL) return [NSString stringWithFormat:@"%.1fB", tokens / 1000000000.0];
    if (tokens >= 1000000ULL) return [NSString stringWithFormat:@"%.1fM", tokens / 1000000.0];
    if (tokens >= 1000ULL) return [NSString stringWithFormat:@"%.1fK", tokens / 1000.0];
    return [NSString stringWithFormat:@"%llu", tokens];
}

- (NSString *)friendlyWindowName:(id)window fallback:(id)fallback
{
    NSDictionary *dictionary = [window isKindOfClass:NSDictionary.class] ? window : @{};
    NSString *name = dictionary[@"name"] ?: dictionary[@"label"] ?: dictionary[@"window"];
    if ([name isKindOfClass:NSString.class] && name.length) return name;
    return [fallback isKindOfClass:NSString.class] ? fallback : @"用量窗口";
}

- (NSString *)resetTextForWindow:(id)window
{
    NSDictionary *dictionary = [window isKindOfClass:NSDictionary.class] ? window : @{};
    id reset = dictionary[@"reset_at"] ?: dictionary[@"resetAt"] ?: dictionary[@"resets_at"];
    if ([reset respondsToSelector:@selector(doubleValue)] && [reset doubleValue] > 0) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[reset doubleValue]];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        return [NSString stringWithFormat:@"重置于 %@", [formatter stringFromDate:date]];
    }
    if ([reset isKindOfClass:NSString.class] && [reset length]) return [NSString stringWithFormat:@"重置于 %@", reset];
    return @"";
}

- (NSDictionary *)normalizedWindowsFromSnapshot:(NSDictionary *)snapshot
{
    id direct = snapshot[@"windows"];
    NSMutableDictionary *windows = [NSMutableDictionary dictionary];
    if ([direct isKindOfClass:NSDictionary.class]) {
        for (NSString *key in @[@"primary", @"secondary"]) {
            id value = direct[key];
            if ([value isKindOfClass:NSDictionary.class]) windows[key] = value;
            else if ([value respondsToSelector:@selector(doubleValue)]) windows[key] = @{ @"used_percent": value };
        }
    }
    NSArray *containers = @[ snapshot, snapshot[@"rate_limits"] ?: @{}, snapshot[@"rateLimits"] ?: @{},
                             snapshot[@"rate_limits_by_limit_id"] ?: @{}, snapshot[@"rateLimitsByLimitId"] ?: @{} ];
    for (id object in containers) {
        if (![object isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *container = object;
        for (NSString *key in @[@"primary", @"secondary"]) {
            if (windows[key]) continue;
            id value = container[key];
            if ([value isKindOfClass:NSDictionary.class]) windows[key] = value;
            else if ([value respondsToSelector:@selector(doubleValue)]) windows[key] = @{ @"used_percent": value };
        }
        for (id child in container.allValues) {
            if (![child isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *dictionary = child;
            for (NSString *key in @[@"primary", @"secondary"]) {
                if (windows[key]) continue;
                id value = dictionary[key];
                if ([value isKindOfClass:NSDictionary.class]) windows[key] = value;
                else if ([value respondsToSelector:@selector(doubleValue)]) windows[key] = @{ @"used_percent": value };
            }
        }
    }
    return windows;
}

- (void)addWindowCard:(id)arg1 fallback:(id)fallback
{
    NSDictionary *window = [arg1 isKindOfClass:NSDictionary.class] ? arg1 : @{};
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 12.0;

    UILabel *title = [self labelWithSize:@16 weight:@(UIFontWeightSemibold) secondary:@NO];
    title.text = [self friendlyWindowName:window fallback:fallback];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *value = [self labelWithSize:@28 weight:@(UIFontWeightSemibold) secondary:@NO];
    id percent = window[@"used_percent"] ?: window[@"usedPercent"] ?: window[@"percent"];
    value.text = [percent respondsToSelector:@selector(doubleValue)] ? [NSString stringWithFormat:@"%.0f%%", [percent doubleValue]] : @"—";
    value.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *reset = [self labelWithSize:@13 weight:@(UIFontWeightRegular) secondary:@YES];
    reset.text = [self resetTextForWindow:window];
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.translatesAutoresizingMaskIntoConstraints = NO;
    progress.progressTintColor = UIColor.systemBlueColor;
    progress.trackTintColor = UIColor.tertiarySystemFillColor;
    progress.progress = [percent respondsToSelector:@selector(doubleValue)] ? (float)MIN(1.0, MAX(0.0, [percent doubleValue] / 100.0)) : 0.0;
    [card addSubview:title]; [card addSubview:value]; [card addSubview:reset]; [card addSubview:progress];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [value.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [value.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [reset.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [reset.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:3.0],
        [reset.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [progress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [progress.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [progress.topAnchor constraintEqualToAnchor:reset.bottomAnchor constant:10.0],
        [progress.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
        [progress.heightAnchor constraintEqualToConstant:3.0],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:132.0],
    ]];
    [_stackView addArrangedSubview:card];
}

- (void)addEquivalentUsageCostCard
{
    unsigned long long input = _engine.totalInputTokens;
    unsigned long long output = _engine.totalOutputTokens;
    unsigned long long reasoning = _engine.totalReasoningTokens;
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 12.0;
    UILabel *title = [self labelWithSize:@16 weight:@(UIFontWeightSemibold) secondary:@NO];
    title.text = @"本次会话 token";
    UILabel *detail = [self labelWithSize:@14 weight:@(UIFontWeightRegular) secondary:@YES];
    detail.numberOfLines = 0;
    detail.text = [NSString stringWithFormat:@"输入 %@  ·  输出 %@  ·  推理 %@", [self usageTokenString:@(input)], [self usageTokenString:@(output)], [self usageTokenString:@(reasoning)]];
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 6.0;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
    ]];
    [_stackView addArrangedSubview:card];
}

- (void)reloadSnapshot
{
    for (UIView *view in [_stackView.arrangedSubviews copy]) {
        [_stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    CARateLimitManager *manager = CARateLimitManager.sharedManager;
    NSDictionary *snapshot = manager.snapshot;
    _planLabel.text = [NSString stringWithFormat:@"方案：%@", manager.planName ?: @"Codex"];
    _statusLabel.text = manager.available ? (manager.lastUpdatedAt ? [NSString stringWithFormat:@"最近更新：%@", manager.lastUpdatedAt] : @"配额数据已更新") : (manager.unavailableReason.length ? manager.unavailableReason : @"暂未获取配额数据");
    NSDictionary *windows = [self normalizedWindowsFromSnapshot:snapshot];
    NSDictionary *primary = [windows[@"primary"] isKindOfClass:NSDictionary.class] ? windows[@"primary"] : @{};
    NSDictionary *secondary = [windows[@"secondary"] isKindOfClass:NSDictionary.class] ? windows[@"secondary"] : @{};
    [self addWindowCard:primary fallback:@"主限额"];
    [self addWindowCard:secondary fallback:@"次限额"];
    [self addEquivalentUsageCostCard];
    [self applyTheme];
}

- (void)refreshQuota
{
    if (_refreshing) return;
    _refreshing = YES;
    _quotaRefreshGeneration += 1;
    [_spinner startAnimating];
    _refreshButton.enabled = NO;
    _statusLabel.text = @"正在刷新配额…";
    __weak typeof(self) weakSelf = self;
    void (^finish)(NSDictionary *, NSError *) = ^(NSDictionary *limits, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (limits.count) [CARateLimitManager.sharedManager updateWithServerSnapshot:limits];
            strongSelf->_refreshing = NO;
            [strongSelf->_spinner stopAnimating];
            strongSelf->_refreshButton.enabled = YES;
            [strongSelf reloadSnapshot];
            if (error && !limits.count) strongSelf->_statusLabel.text = error.localizedDescription ?: @"刷新失败，显示本地快照";
        });
    };
    if (_engine.persistentAppServer.isRunning) {
        [_engine refreshOfficialRateLimitsWithCompletion:finish];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ finish(nil, [NSError errorWithDomain:@"CodexApp.Usage" code:1 userInfo:@{NSLocalizedDescriptionKey: @"常驻会话未运行，显示本地快照"}]); });
    }
}

- (bool)refreshing { return _refreshing; }
- (CACodexEngine *)engine { return _engine; }
- (void)setEngine:(id)value { _engine = [value isKindOfClass:CACodexEngine.class] ? value : CACodexEngine.sharedEngine; }
- (CAConversationRecord *)record { return _record; }
- (void)setRecord:(id)value { _record = [value isKindOfClass:CAConversationRecord.class] ? value : nil; }
- (UIStackView *)stackView { return _stackView; }
- (void)setStackView:(id)value { _stackView = [value isKindOfClass:UIStackView.class] ? value : nil; }
- (UIView *)header { return _header; }
- (void)setHeader:(id)value { _header = [value isKindOfClass:UIView.class] ? value : nil; }
- (UILabel *)titleLabel { return _titleLabel; }
- (void)setTitleLabel:(id)value { _titleLabel = [value isKindOfClass:UILabel.class] ? value : nil; }
- (UILabel *)planLabel { return _planLabel; }
- (void)setPlanLabel:(id)value { _planLabel = [value isKindOfClass:UILabel.class] ? value : nil; }
- (UILabel *)statusLabel { return _statusLabel; }
- (void)setStatusLabel:(id)value { _statusLabel = [value isKindOfClass:UILabel.class] ? value : nil; }
- (UIButton *)closeButton { return _closeButton; }
- (void)setCloseButton:(id)value { _closeButton = [value isKindOfClass:UIButton.class] ? value : nil; }
- (UIButton *)refreshButton { return _refreshButton; }
- (void)setRefreshButton:(id)value { _refreshButton = [value isKindOfClass:UIButton.class] ? value : nil; }
- (id)spinner { return _spinner; }
- (void)setSpinner:(id)value { _spinner = [value isKindOfClass:UIActivityIndicatorView.class] ? value : nil; }
- (unsigned long long)quotaRefreshGeneration { return _quotaRefreshGeneration; }
- (void)setQuotaRefreshGeneration:(id)value { _quotaRefreshGeneration = [value respondsToSelector:@selector(unsignedLongLongValue)] ? [value unsignedLongLongValue] : 0; }
- (void)setRefreshing:(id)value { _refreshing = [value respondsToSelector:@selector(boolValue)] && [value boolValue]; }

@end
