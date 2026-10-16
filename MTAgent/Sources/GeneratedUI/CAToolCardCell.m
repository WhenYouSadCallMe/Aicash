//
//  CAToolCardCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：工具调用卡片（命令 + 状态 + 输出预览，可展开 / 收起 / 复制 / 中断）。
//  由 CAChatViewController 在解析到 command_execution / mcp_tool_call / file_change 事件时创建。
//

#import "CAToolCardCell.h"
#import "CAToolItem.h"

static CGFloat const kCAToolCardCollapsedOutputHeight = 96.0;
static CGFloat const kCAToolCardMaxOutputHeight       = 420.0;

@interface CAToolCardCell () {
    long long _lastStatus;
    bool _hasRenderedState;
}

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *commandLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *collapseButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *actionCopyButton;
@property (nonatomic, strong) UIButton *fullOutputButton;
@property (nonatomic, strong) UIView *outputContainer;
@property (nonatomic, strong) UILabel *outputLabel;
@property (nonatomic, strong) NSLayoutConstraint *outputHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *outputTopSpacing;
@property (nonatomic, strong) NSLayoutConstraint *outputContentsBottom;
@property (nonatomic, strong) NSLayoutConstraint *fullOutputHeight;
@property (nonatomic, strong) NSLayoutConstraint *fullOutputTop;
@property (nonatomic, strong) CAToolItem *configuredTool;
@property (nonatomic, copy) NSString *rawOutput;
@property (nonatomic, strong) NSAttributedString *renderedOutput;
@property (nonatomic, copy) NSString *renderedOutputSource;
@property (nonatomic, copy) NSString *lastItemID;
@property (nonatomic, strong) id capsuleView;
@property (nonatomic, strong) id onShowFullOutput;
@property (nonatomic, strong) id onStop;
@property (nonatomic, strong) id onToggleExpand;
@end

@implementation CAToolCardCell

#pragma mark - 生命周期

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        [self setupToolCard];
    }
    return self;
}

- (void)ensureToolUI
{
    if (self.containerView) return;
    [self setupToolCard];
}

- (id)initWithFrame:(id)arg1
{
    if ((self = [super initWithFrame:CGRectZero])) {
        [self setupToolCard];
    }
    return self;
}

- (void)setupToolCard
{
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _containerView = [[UIView alloc] init];
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    _containerView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _containerView.layer.cornerRadius = 12.0;
    _containerView.layer.masksToBounds = YES;
    _containerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _containerView.layer.borderColor = UIColor.separatorColor.CGColor;
    [_containerView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)]];
    [self.contentView addSubview:_containerView];

    _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"terminal"]];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = UIColor.secondaryLabelColor;
    [_containerView addSubview:_iconView];

    _commandLabel = [[UILabel alloc] init];
    _commandLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _commandLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    _commandLabel.textColor = UIColor.labelColor;
    _commandLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _commandLabel.text = @"工具调用";
    [_containerView addSubview:_commandLabel];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    [_containerView addSubview:_statusLabel];

    _collapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _collapseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_collapseButton setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    _collapseButton.tintColor = UIColor.secondaryLabelColor;
    [_collapseButton addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_collapseButton];

    _stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_stopButton setImage:[UIImage systemImageNamed:@"stop.circle"] forState:UIControlStateNormal];
    _stopButton.tintColor = UIColor.systemRedColor;
    _stopButton.hidden = YES;
    [_stopButton addTarget:self action:@selector(handleStop) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_stopButton];

    _actionCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_actionCopyButton setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    _actionCopyButton.tintColor = UIColor.secondaryLabelColor;
    [_actionCopyButton addTarget:self action:@selector(handleCopyOutput) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_actionCopyButton];

    _outputContainer = [[UIView alloc] init];
    _outputContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _outputContainer.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    _outputContainer.layer.cornerRadius = 8.0;
    _outputContainer.layer.masksToBounds = YES;
    [_containerView addSubview:_outputContainer];

    _outputLabel = [[UILabel alloc] init];
    _outputLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _outputLabel.numberOfLines = 0;
    _outputLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    _outputLabel.textColor = UIColor.secondaryLabelColor;
    _outputLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_outputContainer addSubview:_outputLabel];

    _fullOutputButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _fullOutputButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_fullOutputButton setTitle:@"查看完整输出" forState:UIControlStateNormal];
    _fullOutputButton.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    [_fullOutputButton addTarget:self action:@selector(handleShowFullOutput) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_fullOutputButton];

    _outputTopSpacing = [_outputContainer.topAnchor constraintEqualToAnchor:_commandLabel.bottomAnchor constant:8.0];
    _outputHeightConstraint = [_outputContainer.heightAnchor constraintEqualToConstant:kCAToolCardCollapsedOutputHeight];
    _outputContentsBottom = [_outputLabel.bottomAnchor constraintEqualToAnchor:_outputContainer.bottomAnchor constant:-6.0];
    _fullOutputTop = [_fullOutputButton.topAnchor constraintEqualToAnchor:_outputContainer.bottomAnchor constant:4.0];
    _fullOutputHeight = [_fullOutputButton.heightAnchor constraintEqualToConstant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3.0],
        [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3.0],
        [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_containerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],

        [_iconView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:10.0],
        [_iconView.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:10.0],
        [_iconView.widthAnchor constraintEqualToConstant:14.0],
        [_iconView.heightAnchor constraintEqualToConstant:14.0],

        [_commandLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:6.0],
        [_commandLabel.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],

        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_commandLabel.trailingAnchor constant:6.0],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],

        [_collapseButton.leadingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor constant:2.0],
        [_collapseButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_collapseButton.widthAnchor constraintEqualToConstant:24.0],
        [_collapseButton.heightAnchor constraintEqualToConstant:24.0],

        [_actionCopyButton.leadingAnchor constraintEqualToAnchor:_collapseButton.trailingAnchor constant:2.0],
        [_actionCopyButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_actionCopyButton.widthAnchor constraintEqualToConstant:24.0],
        [_actionCopyButton.heightAnchor constraintEqualToConstant:24.0],

        [_stopButton.leadingAnchor constraintEqualToAnchor:_actionCopyButton.trailingAnchor constant:2.0],
        [_stopButton.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-8.0],
        [_stopButton.centerYAnchor constraintEqualToAnchor:_iconView.centerYAnchor],
        [_stopButton.widthAnchor constraintEqualToConstant:24.0],
        [_stopButton.heightAnchor constraintEqualToConstant:24.0],

        _outputTopSpacing,
        [_outputContainer.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:8.0],
        [_outputContainer.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-8.0],
        _outputHeightConstraint,

        [_outputLabel.topAnchor constraintEqualToAnchor:_outputContainer.topAnchor constant:6.0],
        [_outputLabel.leadingAnchor constraintEqualToAnchor:_outputContainer.leadingAnchor constant:8.0],
        [_outputLabel.trailingAnchor constraintEqualToAnchor:_outputContainer.trailingAnchor constant:-8.0],
        _outputContentsBottom,

        _fullOutputTop,
        [_fullOutputButton.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:8.0],
        _fullOutputHeight,
        [_fullOutputButton.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-8.0],
    ]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.configuredTool = nil;
    self.renderedOutput = nil;
    self.renderedOutputSource = nil;
    self.rawOutput = nil;
    _hasRenderedState = false;
    self.outputLabel.text = @"";
}

- (id)preferredLayoutAttributesFittingAttributes:(id)arg1
{
    // UITableViewCell 不是 collection view cell：这里直接回传入参（原包同选择器）。
    return arg1;
}

#pragma mark - 标量访问器（形参与头文件一致：id）

- (signed long long)lastStatus { return _lastStatus; }

- (void)setLastStatus:(id)arg1
{
    _lastStatus = [arg1 respondsToSelector:@selector(longLongValue)] ? [arg1 longLongValue] : 0;
}

- (bool)hasRenderedState { return _hasRenderedState; }

- (void)setHasRenderedState:(id)arg1
{
    _hasRenderedState = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

#pragma mark - 配置

- (void)configureWithToolItem:(id)arg1
{
    [self ensureToolUI];
    CAToolItem *tool = [arg1 isKindOfClass:CAToolItem.class] ? arg1 : nil;
    self.configuredTool = tool;
    self.lastItemID = tool.itemId;
    _lastStatus = (long long)tool.status;

    NSString *command = tool.command.length > 0 ? tool.command : @"工具调用";
    self.commandLabel.text = [self compactCommand:command];

    BOOL running = (tool.status == CAToolStatusRunning);
    if (running) {
        self.statusLabel.text = @"运行中";
        self.statusLabel.textColor = UIColor.systemOrangeColor;
    } else if (tool.status == CAToolStatusFailed) {
        self.statusLabel.text = [NSString stringWithFormat:@"失败（退出码 %lld）", tool.exitCode];
        self.statusLabel.textColor = UIColor.systemRedColor;
    } else {
        self.statusLabel.text = tool.exitCode != 0 ? [NSString stringWithFormat:@"退出码 %lld", tool.exitCode] : @"已完成";
        self.statusLabel.textColor = tool.exitCode != 0 ? UIColor.systemOrangeColor : UIColor.systemGreenColor;
    }
    self.stopButton.hidden = !running;
    self.iconView.tintColor = running ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;

    NSString *output = tool.output ?: @"";
    self.outputLabel.text = output;
    self.outputContainer.hidden = output.length == 0;
    self.outputTopSpacing.constant = output.length > 0 ? 8.0 : 0.0;
    self.outputHeightConstraint.constant = tool.isExpanded ? kCAToolCardMaxOutputHeight : kCAToolCardCollapsedOutputHeight;
    [self.collapseButton setImage:[UIImage systemImageNamed:(tool.isExpanded ? @"chevron.up" : @"chevron.down")] forState:UIControlStateNormal];
    self.fullOutputButton.hidden = output.length == 0;
    self.fullOutputHeight.constant = output.length > 0 ? 24.0 : 0.0;
    self.actionCopyButton.hidden = output.length == 0;
    self.renderedOutputSource = output;
    _hasRenderedState = true;
}

- (id)compactCommand:(id)arg1
{
    NSString *command = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    NSArray<NSString *> *parts = [command componentsSeparatedByString:@"\n"];
    NSString *first = parts.firstObject ?: command;
    if (first.length > 160) first = [NSString stringWithFormat:@"%@…", [first substringToIndex:160]];
    return first;
}

- (void)loadCompleteOutput:(id)arg1
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : @"";
    self.rawOutput = text;
    self.outputLabel.text = text;
    self.configuredTool.output = text;
}

#pragma mark - 交互

- (void)handleTap
{
    CAToolItem *tool = self.configuredTool;
    if (!tool) return;
    [tool setIsExpanded:@(!tool.isExpanded)];
    [self configureWithToolItem:tool];
    id toggle = self.onToggleExpand;
    if ([toggle isKindOfClass:NSClassFromString(@"NSBlock")]) {
        void (^block)(CAToolItem *) = toggle;
        block(tool);
    }
}

- (void)handleCopyOutput
{
    NSString *text = self.rawOutput.length > 0 ? self.rawOutput : (self.configuredTool.output ?: @"");
    if (text.length == 0) return;
    UIPasteboard.generalPasteboard.string = text;
}

- (void)handleShowFullOutput
{
    id handler = self.onShowFullOutput;
    if ([handler isKindOfClass:NSClassFromString(@"NSBlock")]) {
        void (^block)(CAToolItem *) = handler;
        block(self.configuredTool);
        return;
    }
    [self handleTap];
}

- (void)handleStop
{
    id handler = self.onStop;
    if ([handler isKindOfClass:NSClassFromString(@"NSBlock")]) {
        void (^block)(CAToolItem *) = handler;
        block(self.configuredTool);
    }
}

- (CGRect)expandedBodyRectForCollapseSnapshot
{
    return [self.containerView convertRect:self.outputContainer.frame toView:self.contentView];
}

@end
