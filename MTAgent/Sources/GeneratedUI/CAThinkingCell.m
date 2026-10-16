//
//  CAThinkingCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：思考中 / 运行状态卡片（标题 + 时长 + 可展开的明细）。
//  回合进行中时由 CAChatViewController 插入到消息流末尾并在每次状态变化时刷新。
//  注意：头文件里标量字段的 setter 形参是 id，故内部一律用 ivar。
//

#import "CAThinkingCell.h"
#import "CAMessageItem.h"

@interface CAThinkingCell () {
    bool _ambientMusingActive;
    long long _musingPhraseIndex;
    unsigned long long _musingGeneration;
}

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIButton *collapseButton;
@property (nonatomic, strong) NSLayoutConstraint *detailHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *detailTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *collapseHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *collapseTopConstraint;
@property (nonatomic, strong) CAMessageItem *message;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSString *musingPhaseKey;
@property (nonatomic, strong) NSString *musingMessageID;
@property (nonatomic, strong) id onToggle;
@end

@implementation CAThinkingCell

#pragma mark - 生命周期

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        [self setupThinkingCard];
    }
    return self;
}

- (id)initWithFrame:(id)arg1
{
    if ((self = [super initWithFrame:CGRectZero])) {
        [self setupThinkingCard];
    }
    return self;
}

- (void)ensureThinkingUI
{
    if (self.containerView) return;
    [self setupThinkingCard];
}

- (void)setupThinkingCard
{
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _containerView = [[UIView alloc] init];
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    _containerView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    _containerView.layer.cornerRadius = 12.0;
    _containerView.layer.masksToBounds = YES;
    [_containerView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)]];
    [self.contentView addSubview:_containerView];

    _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = UIColor.systemOrangeColor;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_containerView addSubview:_iconView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    [_containerView addSubview:_spinner];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _statusLabel.textColor = UIColor.labelColor;
    _statusLabel.text = @"思考中…";
    [_containerView addSubview:_statusLabel];

    _durationLabel = [[UILabel alloc] init];
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    _durationLabel.textColor = UIColor.secondaryLabelColor;
    [_containerView addSubview:_durationLabel];

    _collapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _collapseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_collapseButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    _collapseButton.tintColor = UIColor.secondaryLabelColor;
    [_collapseButton addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_collapseButton];

    _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.tintColor = UIColor.secondaryLabelColor;
    _chevronView.hidden = YES;
    [_containerView addSubview:_chevronView];

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.numberOfLines = 0;
    _detailLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    _detailLabel.textColor = UIColor.secondaryLabelColor;
    [_containerView addSubview:_detailLabel];

    _detailTopConstraint = [_detailLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:0.0];
    _detailHeightConstraint = [_detailLabel.heightAnchor constraintEqualToConstant:0.0];
    _collapseTopConstraint = [_containerView.heightAnchor constraintGreaterThanOrEqualToConstant:34.0];
    _collapseHeightConstraint = [_containerView.heightAnchor constraintLessThanOrEqualToConstant:600.0];

    [NSLayoutConstraint activateConstraints:@[
        [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3.0],
        [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3.0],
        [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],

        [_iconView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:10.0],
        [_iconView.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:9.0],
        [_iconView.widthAnchor constraintEqualToConstant:14.0],
        [_iconView.heightAnchor constraintEqualToConstant:14.0],

        [_spinner.centerXAnchor constraintEqualToAnchor:_iconView.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:6.0],
        [_statusLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:7.0],

        [_durationLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_statusLabel.trailingAnchor constant:6.0],
        [_durationLabel.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],

        [_collapseButton.leadingAnchor constraintEqualToAnchor:_durationLabel.trailingAnchor constant:4.0],
        [_collapseButton.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-6.0],
        [_collapseButton.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_collapseButton.widthAnchor constraintEqualToConstant:26.0],
        [_collapseButton.heightAnchor constraintEqualToConstant:26.0],

        [_detailLabel.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:10.0],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-10.0],
        [_detailLabel.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-8.0],
        _detailTopConstraint,
        _collapseTopConstraint,
    ]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self stopTimer];
    self.message = nil;
    self.detailLabel.text = @"";
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimer];
    } else if (self.message.activityRunning) {
        [self startTimer];
    }
}

- (id)preferredLayoutAttributesFittingAttributes:(id)arg1
{
    // UITableViewCell 不是 collection view cell：这里直接回传入参（原包同选择器）。
    return arg1;
}

#pragma mark - 配置

- (void)configureWithMessage:(id)arg1
{
    [self ensureThinkingUI];
    CAMessageItem *item = [arg1 isKindOfClass:CAMessageItem.class] ? arg1 : nil;
    self.message = item;

    BOOL running = item.activityRunning;
    long long kind = item.activityKind;
    NSString *title = item.activityTitle.length > 0 ? item.activityTitle : @"思考中…";
    if (kind == CAMessageActivityKindNotice) title = item.activityTitle ?: @"提示";

    self.statusLabel.text = title;
    self.statusLabel.textColor = (kind == CAMessageActivityKindNotice && !running) ? UIColor.secondaryLabelColor : UIColor.labelColor;

    NSString *detail = item.activityDetail ?: @"";
    BOOL expanded = item.activityExpanded;
    self.detailLabel.text = detail;
    self.detailLabel.hidden = !expanded || detail.length == 0;
    self.detailTopConstraint.constant = self.detailLabel.hidden ? 0.0 : 6.0;
    self.detailHeightConstraint.active = self.detailLabel.hidden;
    [self.collapseButton setImage:[UIImage systemImageNamed:(expanded ? @"chevron.up" : @"chevron.down")] forState:UIControlStateNormal];
    self.collapseButton.hidden = detail.length == 0;

    if (running) {
        [self.spinner startAnimating];
        self.iconView.hidden = YES;
    } else {
        [self.spinner stopAnimating];
        self.iconView.hidden = NO;
        self.iconView.image = [UIImage systemImageNamed:(kind == CAMessageActivityKindNotice ? @"exclamationmark.triangle" : @"checkmark.circle")];
        self.iconView.tintColor = (kind == CAMessageActivityKindNotice) ? UIColor.systemOrangeColor : UIColor.systemGreenColor;
    }

    [self refreshDuration];
    if (running) [self startTimer]; else [self stopTimer];
}

- (void)handleTap
{
    CAMessageItem *item = self.message;
    if (item && item.activityDetail.length > 0) {
        [item toggleActivityExpanded];
        [self configureWithMessage:item];
    }
    id toggle = self.onToggle;
    if ([toggle isKindOfClass:NSClassFromString(@"NSBlock")]) {
        void (^block)(CAMessageItem *) = toggle;
        block(item);
    }
}

#pragma mark - 时长

- (void)startTimer
{
    if (self.timer) return;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
}

- (void)stopTimer
{
    if (!self.timer) return;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)updateTimer
{
    [self refreshDuration];
}

- (void)refreshDuration
{
    self.durationLabel.text = [self durationText];
}

- (id)durationText
{
    CAMessageItem *item = self.message;
    if (!item) return @"";
    double duration = item.activityRunning ? [[NSDate date] timeIntervalSinceDate:item.activityStartedAt ?: [NSDate date]] : item.activityDuration;
    if (duration <= 0) return @"";
    if (duration < 60) return [NSString stringWithFormat:@"%.0fs", duration];
    return [NSString stringWithFormat:@"%.0fm%.0fs", floor(duration / 60.0), fmod(duration, 60.0)];
}

- (CGRect)expandedBodyRectForCollapseSnapshot
{
    return [self.containerView convertRect:self.detailLabel.frame toView:self.contentView];
}

#pragma mark - 环境闲聊（原包动画，聊天主流程不需要）

- (bool)shouldUseAmbientMusingForMessage:(id)arg1
{
    return NO;
}

- (bool)canContinueAmbientGeneration:(id)arg1
{
    return NO;
}

- (id)musingsForCurrentMessage
{
    return @[];
}

- (signed long long)nextMusingIndex
{
    return 0;
}

- (void)startAmbientMusingForMessage:(id)arg1
{
    // TODO(parity): 环境闲聊动画
}

- (void)cancelAmbientMusing
{
    _ambientMusingActive = false;
    [self stopTimer];
}

- (void)pauseVisualActivityForInactivity
{
    // TODO(parity)
}

- (void)showMusingDotsForPhrase:(id)arg1 round:(id)arg2 dot:(id)arg3 generation:(id)arg4
{
    // TODO(parity)
}

- (void)showMusingPhraseAtIndex:(id)arg1 generation:(id)arg2
{
    // TODO(parity)
}

- (void)typeMusingPhrase:(id)arg1 character:(id)arg2 generation:(id)arg3
{
    // TODO(parity)
}

- (bool)gestureRecognizer:(id)arg1 shouldReceiveTouch:(id)arg2
{
    return YES;
}

- (void)thinkingAppDidBecomeActive:(id)arg1
{
    if (self.message.activityRunning) [self startTimer];
}

- (void)thinkingAppWillResignActive:(id)arg1
{
    [self stopTimer];
}

@end
