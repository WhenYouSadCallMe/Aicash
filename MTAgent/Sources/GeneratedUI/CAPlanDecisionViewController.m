//
//  CAPlanDecisionViewController.m — 审批 / 计划确认对话框（真实界面实现）
//
//  契约来源：codex CLI 的 item/tool/requestUserInput（questions / answers 结构，见 SPEC/复刻规格书.md §4）
//    questions 数组，每项：
//      @{ @"id": questionID, @"header": 小标题, @"question": 正文,
//         @"options": @[ @{ @"label": 选项文本, @"description": 说明 } ],
//         @"secret": @(BOOL), @"freeform": @(BOOL) }
//    completion：void(^)(BOOL approved, NSDictionary *answers, BOOL rememberChoice)
//    answers：@{ questionID: @{ @"answers": @[ 选项文本或自由文本 ] } }
//
//  头文件的选择器参数类型统一是占位 id；实现逐字沿用该签名，函数体第一行局部强转后使用。
//

#import "CAPlanDecisionViewController.h"
#import "CALogger.h"

#pragma mark - 文件内工具（静态函数：不为面板新增选择器）

static const CGFloat kCADecisionCardRadius = 16.0;
static const NSInteger kCADecisionIndicatorTag = 3101;
static const NSInteger kCADecisionCheckTag = 3102;

/// id 占位参数 → BOOL（头文件里真实语义多为 bool）
static BOOL CADecisionBool(id value)
{
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [(NSNumber *)value boolValue];
    }
    return value != nil;
}

/// 统一关闭入口：已 push 则 pop，模态则 dismiss
static void CADecisionDismiss(UIViewController *controller)
{
    if (!controller) return;
    UINavigationController *navigation = controller.navigationController;
    if (navigation && navigation.viewControllers.count > 1) {
        [navigation popViewControllerAnimated:YES];
    } else if (controller.presentingViewController) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
}

static UILabel *CADecisionLabel(NSString *text, UIFont *font, UIColor *color)
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

/// 标准三选项：questions 未提供 options 时由面板自己生成
static NSArray<NSDictionary *> *CADecisionDefaultOptions(void)
{
    return @[
        @{ @"label": @"允许", @"description": @"按上面的说明继续执行" },
        @{ @"label": @"拒绝", @"description": @"先停下，不执行这一步" },
        @{ @"label": @"允许并记住", @"description": @"本次会话内同类请求不再询问", @"remember": @YES },
    ];
}

/// 归一化某个问题的选项；无选项且既非密钥也非自由文本时补上标准三选项
static NSArray<NSDictionary *> *CADecisionOptionsForQuestion(NSDictionary *question)
{
    id raw = question[@"options"];
    NSMutableArray<NSDictionary *> *options = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)raw) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *dictionary = (NSDictionary *)item;
            id label = dictionary[@"label"] ?: dictionary[@"title"] ?: dictionary[@"value"];
            if (![label isKindOfClass:NSString.class] || [(NSString *)label length] == 0) continue;
            NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
            normalized[@"label"] = label;
            id detail = dictionary[@"description"] ?: dictionary[@"detail"] ?: dictionary[@"subtitle"];
            if ([detail isKindOfClass:NSString.class]) normalized[@"description"] = detail;
            if (dictionary[@"remember"] != nil) normalized[@"remember"] = dictionary[@"remember"];
            [options addObject:normalized];
        }
    }
    if (options.count > 0) return options;
    BOOL secret = CADecisionBool(question[@"secret"] ?: question[@"isSecret"]);
    BOOL freeform = CADecisionBool(question[@"freeform"] ?: question[@"isFreeform"]);
    if (secret || freeform) return @[];
    return CADecisionDefaultOptions();
}

/// 选项行的选中外观（圆形控件 + 蓝色对勾）
static void CADecisionApplyRowAppearance(UIButton *row, BOOL selected)
{
    UIView *indicator = [row viewWithTag:kCADecisionIndicatorTag];
    UIImageView *check = (UIImageView *)[indicator viewWithTag:kCADecisionCheckTag];
    UIColor *tint = selected ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor;
    indicator.backgroundColor = selected ? UIColor.systemBlueColor : UIColor.clearColor;
    indicator.layer.borderColor = tint.CGColor;
    check.hidden = !selected;
}

/// 选项行：左侧圆形选中控件 + 右侧 label（+ 灰色 description）
static UIButton *CADecisionOptionRow(NSString *title,
                                     NSString *description,
                                     NSInteger questionIndex,
                                     NSInteger optionIndex,
                                     id target,
                                     SEL action)
{
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.tag = questionIndex * 100 + optionIndex;
    row.backgroundColor = UIColor.clearColor;
    [row setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [row setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    if (target && action) {
        [row addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }

    UIView *indicator = [[UIView alloc] initWithFrame:CGRectZero];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.tag = kCADecisionIndicatorTag;
    indicator.layer.cornerRadius = 11.0;
    indicator.layer.borderWidth = 1.5;
    indicator.userInteractionEnabled = NO;
    [row addSubview:indicator];

    UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    check.tag = kCADecisionCheckTag;
    check.contentMode = UIViewContentModeScaleAspectFit;
    check.tintColor = UIColor.whiteColor;
    check.hidden = YES;
    check.userInteractionEnabled = NO;
    [indicator addSubview:check];

    UILabel *titleLabel = CADecisionLabel(title, [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular], UIColor.labelColor);
    titleLabel.userInteractionEnabled = NO;
    [row addSubview:titleLabel];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    [constraints addObjectsFromArray:@[
        [indicator.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:2.0],
        [indicator.topAnchor constraintEqualToAnchor:row.topAnchor constant:2.0],
        [indicator.widthAnchor constraintEqualToConstant:22.0],
        [indicator.heightAnchor constraintEqualToConstant:22.0],

        [check.centerXAnchor constraintEqualToAnchor:indicator.centerXAnchor],
        [check.centerYAnchor constraintEqualToAnchor:indicator.centerYAnchor],
        [check.widthAnchor constraintEqualToConstant:12.0],
        [check.heightAnchor constraintEqualToConstant:12.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:indicator.trailingAnchor constant:12.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-2.0],
        [titleLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
    ]];

    if ([description isKindOfClass:NSString.class] && description.length > 0) {
        UILabel *detailLabel = CADecisionLabel(description, [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular], UIColor.secondaryLabelColor);
        detailLabel.userInteractionEnabled = NO;
        [row addSubview:detailLabel];
        [constraints addObjectsFromArray:@[
            [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [detailLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-2.0],
            [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
            [detailLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-4.0],
        ]];
    } else {
        [constraints addObject:[titleLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-4.0]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

/// 密钥输入行（圆角填充容器 + 安全输入框）
static UIView *CADecisionPrivateRow(UITextField *field)
{
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.tertiarySystemFillColor;
    row.layer.cornerRadius = 12.0;

    field.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.topAnchor constraintEqualToAnchor:row.topAnchor constant:4.0],
        [field.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12.0],
        [field.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0],
        [field.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-4.0],
        [field.heightAnchor constraintGreaterThanOrEqualToConstant:38.0],
    ]];
    return row;
}

/// 自由文本输入行（圆角填充容器 + 多行文本框）
static UIView *CADecisionFreeformRow(UITextView *textView)
{
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.tertiarySystemFillColor;
    row.layer.cornerRadius = 12.0;

    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:row.topAnchor constant:6.0],
        [textView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10.0],
        [textView.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-10.0],
        [textView.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-6.0],
        [textView.heightAnchor constraintGreaterThanOrEqualToConstant:84.0],
    ]];
    return row;
}

#pragma mark - 面板

@interface CAPlanDecisionViewController () <UITextViewDelegate>
{
    NSMutableDictionary *_choiceRows;       // index → 选项行数组（UIButton）
    id _completion;                         // void(^)(BOOL, NSDictionary *, BOOL)
    NSMutableDictionary *_customRows;       // index → 自定义/私密回答行容器
    NSMutableDictionary *_freeformEditors;  // index → UITextView
    NSMutableDictionary *_privateEditors;   // index → UITextField（secureTextEntry）
    NSArray *_questions;                    // 原始问题数组
    UILabel *_remainingLabel;
    BOOL _resolved;
    NSMutableDictionary *_selections;       // index → NSNumber(选项下标)
    UIButton *_submitButton;

    UIScrollView *_scrollView;
    UIView *_bottomBar;
}

@end

@implementation CAPlanDecisionViewController

#pragma mark - 访问器（头文件里声明的选择器）

- (NSMutableDictionary *)choiceRows
{
    return _choiceRows;
}

- (id)completion
{
    return _completion;
}

- (NSMutableDictionary *)customRows
{
    return _customRows;
}

- (void)deferQuestions
{
    if (_resolved) return;
    _resolved = YES;

    void (^completion)(BOOL, NSDictionary *, BOOL) = (void (^)(BOOL, NSDictionary *, BOOL))_completion;
    if (completion) {
        completion(NO, @{}, NO);
    }
    CALog(CALogLevelInfo, @"GENERAL", @"plan decision deferred questions=%lu",
          (unsigned long)_questions.count);
    CADecisionDismiss(self);
}

- (void)finishAllowingUnknown:(id)arg1
{
    if (_resolved) return;

    // 发送者是控件时（“全部允许”按钮）视作 YES；显式传 NO 则退回「稍后处理」
    if (!CADecisionBool(arg1)) {
        [self deferQuestions];
        return;
    }

    for (NSUInteger index = 0; index < _questions.count; index++) {
        if (_selections[@(index)] != nil) continue;
        if ([self textAnswerForIndex:@(index)] != nil) continue;

        NSDictionary *question = [_questions[index] isKindOfClass:NSDictionary.class] ? (NSDictionary *)_questions[index] : @{};
        NSArray<NSDictionary *> *options = CADecisionOptionsForQuestion(question);
        if (options.count > 0) {
            // 未答项按第一个选项补齐
            _selections[@(index)] = @(0);
            continue;
        }
        UITextField *field = _privateEditors[@(index)];
        if (field) field.text = @"（用户已直接放行）";
        UITextView *textView = _freeformEditors[@(index)];
        if (textView) textView.text = @"（用户已直接放行）";
    }

    [self refreshSelectionState];
    [self submitDecisions];
}

- (NSMutableDictionary *)freeformEditors
{
    return _freeformEditors;
}

- (id)initWithQuestions:(id)arg1 completion:(id)arg2
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _questions = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : @[];
        _completion = [arg2 copy];
        _choiceRows = [NSMutableDictionary dictionary];
        _customRows = [NSMutableDictionary dictionary];
        _freeformEditors = [NSMutableDictionary dictionary];
        _privateEditors = [NSMutableDictionary dictionary];
        _selections = [NSMutableDictionary dictionary];
        _resolved = NO;
    }
    return self;
}

- (id)label:(id)arg1 font:(id)arg2 color:(id)arg3
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    UIFont *font = [arg2 isKindOfClass:UIFont.class] ? (UIFont *)arg2 : [UIFont systemFontOfSize:15.0];
    UIColor *color = [arg3 isKindOfClass:UIColor.class] ? (UIColor *)arg3 : UIColor.labelColor;
    return CADecisionLabel(text, font, color);
}

- (NSMutableDictionary *)privateEditors
{
    return _privateEditors;
}

- (NSArray *)questions
{
    return _questions;
}

- (void)refreshSelectionState
{
    if (!_remainingLabel && !_submitButton) return;

    NSUInteger pending = 0;
    for (NSUInteger index = 0; index < _questions.count; index++) {
        if (_selections[@(index)] == nil && [self textAnswerForIndex:@(index)] == nil) {
            pending++;
        }
        NSArray<UIButton *> *rows = _choiceRows[@(index)];
        NSNumber *selection = _selections[@(index)];
        for (NSUInteger optionIndex = 0; optionIndex < rows.count; optionIndex++) {
            CADecisionApplyRowAppearance(rows[optionIndex],
                                         selection != nil && selection.unsignedIntegerValue == optionIndex);
        }
    }

    if (_remainingLabel) {
        _remainingLabel.text = (pending == 0)
            ? @"全部已确认"
            : [NSString stringWithFormat:@"还有 %lu 项待确认", (unsigned long)pending];
    }
    if (_submitButton) {
        BOOL enabled = (pending == 0);
        _submitButton.enabled = enabled;
        _submitButton.backgroundColor = enabled ? UIColor.systemBlueColor : UIColor.tertiarySystemFillColor;
        [_submitButton setTitleColor:(enabled ? UIColor.whiteColor : UIColor.secondaryLabelColor)
                            forState:UIControlStateNormal];
    }
}

- (UILabel *)remainingLabel
{
    return _remainingLabel;
}

- (bool)resolved
{
    return _resolved ? YES : NO;
}

- (void)secretFieldChanged:(id)arg1
{
    [self refreshSelectionState];
}

- (void)selectChoice:(id)arg1
{
    UIView *row = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
    if (!row) return;

    NSInteger questionIndex = row.tag / 100;
    NSInteger optionIndex = row.tag % 100;
    if (questionIndex < 0 || (NSUInteger)questionIndex >= _questions.count) return;

    // 单选题：直接覆盖该题的选择
    _selections[@(questionIndex)] = @(optionIndex);
    [self refreshSelectionState];
}

- (NSMutableDictionary *)selections
{
    return _selections;
}

- (void)setChoiceRows:(id)arg1
{
    _choiceRows = [arg1 isKindOfClass:NSMutableDictionary.class] ? (NSMutableDictionary *)arg1 : nil;
}

- (void)setCompletion:(id)arg1
{
    _completion = [arg1 copy];
}

- (void)setCustomRows:(id)arg1
{
    _customRows = [arg1 isKindOfClass:NSMutableDictionary.class] ? (NSMutableDictionary *)arg1 : nil;
}

- (void)setFreeformEditors:(id)arg1
{
    _freeformEditors = [arg1 isKindOfClass:NSMutableDictionary.class] ? (NSMutableDictionary *)arg1 : nil;
}

- (void)setPrivateEditors:(id)arg1
{
    _privateEditors = [arg1 isKindOfClass:NSMutableDictionary.class] ? (NSMutableDictionary *)arg1 : nil;
}

- (void)setQuestions:(id)arg1
{
    _questions = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : @[];
}

- (void)setRemainingLabel:(id)arg1
{
    _remainingLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (void)setResolved:(id)arg1
{
    _resolved = CADecisionBool(arg1);
}

- (void)setSelections:(id)arg1
{
    _selections = [arg1 isKindOfClass:NSMutableDictionary.class] ? (NSMutableDictionary *)arg1 : nil;
}

- (void)setSubmitButton:(id)arg1
{
    _submitButton = [arg1 isKindOfClass:UIButton.class] ? (UIButton *)arg1 : nil;
}

- (UIButton *)submitButton
{
    return _submitButton;
}

- (void)submitDecisions
{
    if (_resolved) return;

    NSMutableDictionary *answers = [NSMutableDictionary dictionary];
    BOOL rememberChoice = NO;
    BOOL denied = NO;

    for (NSUInteger index = 0; index < _questions.count; index++) {
        NSDictionary *question = [_questions[index] isKindOfClass:NSDictionary.class] ? (NSDictionary *)_questions[index] : @{};
        id identifier = question[@"id"] ?: question[@"questionId"] ?: question[@"key"];
        NSString *questionID = [identifier isKindOfClass:NSString.class] ? (NSString *)identifier
                                                                         : [NSString stringWithFormat:@"q%lu", (unsigned long)index];
        NSArray<NSDictionary *> *options = CADecisionOptionsForQuestion(question);
        NSMutableDictionary *answer = [NSMutableDictionary dictionary];

        NSNumber *selection = _selections[@(index)];
        if (selection != nil && selection.unsignedIntegerValue < options.count) {
            NSDictionary *option = options[selection.unsignedIntegerValue];
            NSString *label = [option[@"label"] isKindOfClass:NSString.class] ? option[@"label"] : @"";
            // app-server 的 RequestUserInputAnswer 使用 answers 数组，不是自定义 choice 字段。
            if (label.length > 0) answer[@"answers"] = @[ label ];
            BOOL remember = CADecisionBool(option[@"remember"]) || [label containsString:@"记住"];
            if (remember) {
                rememberChoice = YES;
            }
            if ([label isEqualToString:@"拒绝"]) denied = YES;
        }

        NSString *text = [self textAnswerForIndex:@(index)];
        if (text.length > 0) answer[@"answers"] = @[ text ];

        if (answer.count > 0) answers[questionID] = answer;
    }

    _resolved = YES;
    BOOL approved = !denied;

    void (^completion)(BOOL, NSDictionary *, BOOL) = (void (^)(BOOL, NSDictionary *, BOOL))_completion;
    if (completion) {
        completion(approved, answers, rememberChoice);
    }
    CALog(CALogLevelInfo, @"GENERAL", @"plan decision submitted approved=%d answers=%lu remember=%d",
          approved ? 1 : 0, (unsigned long)answers.count, rememberChoice ? 1 : 0);

    CADecisionDismiss(self);
}

- (id)textAnswerForIndex:(id)arg1
{
    if (![arg1 respondsToSelector:@selector(unsignedIntegerValue)]) return nil;
    NSUInteger index = [(NSNumber *)arg1 unsignedIntegerValue];
    if (index >= _questions.count) return nil;

    UITextField *field = _privateEditors[@(index)];
    if (field && field.text.length > 0) {
        return [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    UITextView *textView = _freeformEditors[@(index)];
    if (textView && textView.text.length > 0) {
        return [textView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return nil;
}

- (void)textViewDidChange:(id)arg1
{
    [self refreshSelectionState];
}

- (void)viewDidAppear:(id)arg1
{
    [super viewDidAppear:CADecisionBool(arg1)];

    // 聚焦第一个需要输入的控件
    for (NSUInteger index = 0; index < _questions.count; index++) {
        UITextField *field = _privateEditors[@(index)];
        if (field && field.text.length == 0) {
            [field becomeFirstResponder];
            return;
        }
        UITextView *textView = _freeformEditors[@(index)];
        if (textView && textView.text.length == 0) {
            [textView becomeFirstResponder];
            return;
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"需要你的确认";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(deferQuestions)];
    close.accessibilityLabel = @"稍后处理";
    self.navigationItem.leftBarButtonItem = close;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"全部允许"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(finishAllowingUnknown:)];

    // 底部固定条：待确认计数 + 提交
    _bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:_bottomBar];

    UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;
    [_bottomBar addSubview:separator];

    _remainingLabel = CADecisionLabel(@"", [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular], UIColor.secondaryLabelColor);
    [_bottomBar addSubview:_remainingLabel];

    _submitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _submitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_submitButton setTitle:@"提交" forState:UIControlStateNormal];
    _submitButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _submitButton.layer.cornerRadius = 12.0;
    _submitButton.layer.masksToBounds = YES;
    [_submitButton addTarget:self action:@selector(submitDecisions) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_submitButton];

    // 问题卡片：标题（header）+ 正文（question）+ 选项行 / 输入行
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:_scrollView];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 16.0;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:column];

    for (NSUInteger index = 0; index < _questions.count; index++) {
        NSDictionary *question = [_questions[index] isKindOfClass:NSDictionary.class] ? (NSDictionary *)_questions[index] : @{};
        BOOL secret = CADecisionBool(question[@"secret"] ?: question[@"isSecret"]);
        BOOL freeform = CADecisionBool(question[@"freeform"] ?: question[@"isFreeform"]);
        NSArray<NSDictionary *> *options = CADecisionOptionsForQuestion(question);

        id header = question[@"header"];
        id body = question[@"question"] ?: question[@"prompt"] ?: question[@"text"];
        NSString *headerText = [header isKindOfClass:NSString.class] ? (NSString *)header : @"";
        NSString *bodyText = [body isKindOfClass:NSString.class] ? (NSString *)body : @"";

        UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        card.layer.cornerRadius = kCADecisionCardRadius;
        card.layer.masksToBounds = YES;
        [column addArrangedSubview:card];

        UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[]];
        content.axis = UILayoutConstraintAxisVertical;
        content.spacing = 10.0;
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
            [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
            [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
            [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0],
        ]];

        if (headerText.length > 0) {
            [content addArrangedSubview:CADecisionLabel(headerText,
                                                        [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold],
                                                        UIColor.systemBlueColor)];
        }
        if (bodyText.length > 0) {
            [content addArrangedSubview:CADecisionLabel(bodyText,
                                                        [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold],
                                                        UIColor.labelColor)];
        }

        NSMutableArray<UIButton *> *rows = [NSMutableArray array];
        for (NSUInteger optionIndex = 0; optionIndex < options.count; optionIndex++) {
            NSDictionary *option = options[optionIndex];
            UIButton *row = CADecisionOptionRow(option[@"label"], option[@"description"],
                                                (NSInteger)index, (NSInteger)optionIndex,
                                                self, @selector(selectChoice:));
            [content addArrangedSubview:row];
            [rows addObject:row];
        }
        if (rows.count > 0) {
            _choiceRows[@(index)] = rows;
        }

        if (secret) {
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
            field.borderStyle = UITextBorderStyleNone;
            field.secureTextEntry = YES;
            field.font = [UIFont systemFontOfSize:15.0];
            field.textColor = UIColor.labelColor;
            field.placeholder = @"在这里输入（不会显示明文）";
            [field addTarget:self action:@selector(secretFieldChanged:) forControlEvents:UIControlEventEditingChanged];
            _privateEditors[@(index)] = field;
            UIView *row = CADecisionPrivateRow(field);
            _customRows[@(index)] = row;
            [content addArrangedSubview:row];
        }

        if (freeform) {
            UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
            textView.backgroundColor = UIColor.clearColor;
            textView.font = [UIFont systemFontOfSize:15.0];
            textView.textColor = UIColor.labelColor;
            textView.delegate = self;
            textView.scrollEnabled = NO;
            _freeformEditors[@(index)] = textView;
            UIView *row = CADecisionFreeformRow(textView);
            if (_customRows[@(index)] == nil) {
                _customRows[@(index)] = row;
            }
            [content addArrangedSubview:row];
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [column.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [column.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor constant:16.0],
        [column.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
        [column.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-24.0],
        [column.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor constant:-32.0],

        [_bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [separator.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],

        [_remainingLabel.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor constant:10.0],
        [_remainingLabel.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor constant:16.0],
        [_remainingLabel.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor constant:-16.0],

        [_submitButton.topAnchor constraintEqualToAnchor:_remainingLabel.bottomAnchor constant:8.0],
        [_submitButton.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor constant:16.0],
        [_submitButton.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor constant:-16.0],
        [_submitButton.heightAnchor constraintEqualToConstant:46.0],
        [_submitButton.bottomAnchor constraintEqualToAnchor:_bottomBar.bottomAnchor constant:-12.0],

        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_bottomBar.topAnchor],
    ]];

    [self refreshSelectionState];
}

@end
