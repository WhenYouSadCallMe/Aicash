//
//  CAPlanReviewViewController.m — 计划确认 / 审阅（真实界面实现）
//
//  用途：codex 交付一份计划文本后，由用户「编辑计划」或「批准并执行」。
//    initWithPlan:onEdit:onApprove:
//      onEdit(plan)      —— 关闭面板前把当前文本交回（用户要去改计划）
//      onApprove(plan)   —— 批准并执行，把计划文本交回调用方
//
//  头文件的选择器参数类型统一是占位 id；实现逐字沿用该签名，函数体第一行局部强转后使用。
//

#import "CAPlanReviewViewController.h"
#import "CALogger.h"

#pragma mark - 文件内工具（静态函数：不为面板新增选择器）

/// 统一关闭入口：已 push 则 pop，模态则 dismiss
static void CAPlanReviewDismiss(UIViewController *controller)
{
    if (!controller) return;
    UINavigationController *navigation = controller.navigationController;
    if (navigation && navigation.viewControllers.count > 1) {
        [navigation popViewControllerAnimated:YES];
    } else if (controller.presentingViewController) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
}

/// 轻提示（贴在底部固定条上方，1.6s 后自动消失）
static void CAPlanReviewToast(UIView *hostView, NSString *message)
{
    if (!hostView || message.length == 0) return;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    container.layer.cornerRadius = 12.0;
    container.layer.masksToBounds = YES;
    [hostView addSubview:container];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
        [container.bottomAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.bottomAnchor constant:-132.0],
        [container.widthAnchor constraintLessThanOrEqualToAnchor:hostView.widthAnchor constant:-56.0],

        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14.0],
    ]];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [container removeFromSuperview];
    });
}

#pragma mark - 面板

@interface CAPlanReviewViewController ()
{
    id _onApprove;      // void(^)(NSString *plan)
    id _onEdit;         // void(^)(NSString *plan)
    NSString *_plan;
    UITextView *_planText;

    UIView *_card;
    UILabel *_hintLabel;
    UIButton *_editButton;
    UIButton *_approveButton;
}

@end

@implementation CAPlanReviewViewController

#pragma mark - 访问器（头文件里声明的选择器）

- (id)action:(id)arg1 fill:(id)arg2 selector:(id)arg3
{
    NSString *title = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    BOOL fill = [arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : (arg2 != nil);
    SEL action = NULL;
    if ([arg3 isKindOfClass:NSString.class]) {
        action = NSSelectorFromString((NSString *)arg3);
    } else if ([arg3 isKindOfClass:NSValue.class]) {
        action = (SEL)[(NSValue *)arg3 pointerValue];
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 12.0;
    button.layer.masksToBounds = YES;
    if (fill) {
        button.backgroundColor = UIColor.systemBlueColor;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.6] forState:UIControlStateDisabled];
    } else {
        button.backgroundColor = UIColor.tertiarySystemFillColor;
        [button setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
        [button setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateDisabled];
    }
    if (action) {
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (void)approvePlan
{
    NSString *plan = self.plan ?: @"";
    if (plan.length == 0) {
        CAPlanReviewToast(self.view, @"没有可执行的计划内容");
        return;
    }

    void (^onApprove)(NSString *) = (void (^)(NSString *))_onApprove;
    if (onApprove) {
        onApprove(plan);
    }
    CALog(CALogLevelInfo, @"GENERAL", @"plan approved length=%lu", (unsigned long)plan.length);
    CAPlanReviewDismiss(self);
}

- (void)close
{
    // 关闭前把当前文本交回调用方（用户可能要去别处改计划）
    if (_onEdit) {
        void (^onEdit)(NSString *) = (void (^)(NSString *))_onEdit;
        onEdit(self.plan ?: @"");
    }
    CAPlanReviewDismiss(self);
}

- (void)editPlan
{
    [self close];
}

- (id)initWithPlan:(id)arg1 onEdit:(id)arg2 onApprove:(id)arg3
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _plan = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"";
        _onEdit = [arg2 copy];
        _onApprove = [arg3 copy];
    }
    return self;
}

- (id)onApprove
{
    return _onApprove;
}

- (id)onEdit
{
    return _onEdit;
}

- (NSString *)plan
{
    return _plan;
}

- (UITextView *)planText
{
    return _planText;
}

- (id)readablePlan
{
    NSString *raw = [_plan isKindOfClass:NSString.class] ? _plan : @"";
    if (raw.length == 0) return @"";

    NSString *normalized = [raw stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    NSMutableArray<NSString *> *cleanedLines = [NSMutableArray array];
    for (NSString *line in [normalized componentsSeparatedByString:@"\n"]) {
        // markdown 代码围栏整行去掉（内容保留）
        NSString *leadingTrimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([leadingTrimmed hasPrefix:@"```"] || [leadingTrimmed hasPrefix:@"~~~"]) continue;

        // 去掉强调残留 ***，只裁掉行尾空白（保留缩进，代码块排版不变）
        NSMutableString *text = [line mutableCopy];
        [text replaceOccurrencesOfString:@"***" withString:@"" options:0 range:NSMakeRange(0, text.length)];
        while (text.length > 0) {
            unichar last = [text characterAtIndex:text.length - 1];
            if (last != ' ' && last != '\t') break;
            [text deleteCharactersInRange:NSMakeRange(text.length - 1, 1)];
        }
        [cleanedLines addObject:text];
    }

    // 折叠多余空行（连续空行压成一行）
    NSMutableArray<NSString *> *output = [NSMutableArray array];
    BOOL previousBlank = NO;
    for (NSString *line in cleanedLines) {
        BOOL blank = (line.length == 0);
        if (blank && previousBlank) continue;
        [output addObject:line];
        previousBlank = blank;
    }

    NSString *result = [output componentsJoinedByString:@"\n"];
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)setOnApprove:(id)arg1
{
    _onApprove = [arg1 copy];
}

- (void)setOnEdit:(id)arg1
{
    _onEdit = [arg1 copy];
}

- (void)setPlan:(id)arg1
{
    _plan = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"";
    if (_planText) {
        NSString *body = [self readablePlan];
        _planText.text = body.length > 0 ? body : @"（没有可审阅的计划内容）";
        _planText.textColor = body.length > 0 ? UIColor.labelColor : UIColor.secondaryLabelColor;
        if (_approveButton) _approveButton.enabled = (body.length > 0);
    }
}

- (void)setPlanText:(id)arg1
{
    _planText = [arg1 isKindOfClass:UITextView.class] ? (UITextView *)arg1 : nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"计划确认";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(close)];
    close.accessibilityLabel = @"关闭";
    self.navigationItem.leftBarButtonItem = close;

    NSString *body = [self readablePlan];
    BOOL hasPlan = (body.length > 0);

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _hintLabel.text = hasPlan ? @"确认后 codex 会按这份计划执行；需要改动就点「编辑计划」。" : @"codex 还没有给出可执行的计划。";
    _hintLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    _hintLabel.textColor = UIColor.secondaryLabelColor;
    _hintLabel.numberOfLines = 0;
    [self.view addSubview:_hintLabel];

    _card = [[UIView alloc] initWithFrame:CGRectZero];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _card.layer.cornerRadius = 16.0;
    _card.layer.masksToBounds = YES;
    [self.view addSubview:_card];

    _planText = [[UITextView alloc] initWithFrame:CGRectZero];
    _planText.translatesAutoresizingMaskIntoConstraints = NO;
    _planText.editable = NO;
    _planText.selectable = YES;
    _planText.backgroundColor = UIColor.clearColor;
    _planText.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    _planText.textColor = hasPlan ? UIColor.labelColor : UIColor.secondaryLabelColor;
    _planText.text = hasPlan ? body : @"（没有可审阅的计划内容）";
    _planText.textContainerInset = UIEdgeInsetsMake(4.0, 4.0, 4.0, 4.0);
    _planText.alwaysBounceVertical = YES;
    [_card addSubview:_planText];

    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:bottomBar];

    UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;
    [bottomBar addSubview:separator];

    _editButton = (UIButton *)[self action:@"编辑计划" fill:@NO selector:@"editPlan"];
    [bottomBar addSubview:_editButton];

    _approveButton = (UIButton *)[self action:@"批准并执行" fill:@YES selector:@"approvePlan"];
    _approveButton.enabled = hasPlan;
    [bottomBar addSubview:_approveButton];

    [NSLayoutConstraint activateConstraints:@[
        [_hintLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [_hintLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [_hintLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0],

        [_card.topAnchor constraintEqualToAnchor:_hintLabel.bottomAnchor constant:12.0],
        [_card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_card.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:-12.0],

        [_planText.topAnchor constraintEqualToAnchor:_card.topAnchor constant:12.0],
        [_planText.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12.0],
        [_planText.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12.0],
        [_planText.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-12.0],

        [bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [separator.topAnchor constraintEqualToAnchor:bottomBar.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],

        [_editButton.topAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:12.0],
        [_editButton.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor constant:16.0],
        [_editButton.heightAnchor constraintEqualToConstant:46.0],

        [_approveButton.topAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:12.0],
        [_approveButton.leadingAnchor constraintEqualToAnchor:_editButton.trailingAnchor constant:12.0],
        [_approveButton.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor constant:-16.0],
        [_approveButton.heightAnchor constraintEqualToConstant:46.0],
        [_approveButton.widthAnchor constraintEqualToAnchor:_editButton.widthAnchor],
        [_approveButton.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor constant:-12.0],
    ]];

    CALog(CALogLevelDebug, @"GENERAL", @"plan review loaded hasPlan=%d length=%lu",
          hasPlan ? 1 : 0, (unsigned long)body.length);
}

@end
