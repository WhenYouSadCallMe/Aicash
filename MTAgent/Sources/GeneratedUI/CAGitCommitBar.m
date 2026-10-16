//
//  CAGitCommitBar.m — 提交栏
//
//  版式对齐原版截图（06/07）：
//    · 顶部分段控件：「全部更改 <N>」/「仅已暂存 <M>」（选中段白胶囊）
//    · 下一行：输入框（占位「这次修改了什么?」）+ 右侧「✓ 提交」按钮（不可提交时置灰）
//    · 顶部 0.5pt 分隔线；整条固定底部并让出 safe area（由使用方负责约束）
//

#import "CAGitCommitBar.h"

@interface CAGitCommitBar () <UITextViewDelegate>
{
    UISegmentedControl *_scopeControl;
    UITextView *_textView;
    UILabel *_placeholder;
    UIButton *_commitButton;
    UILabel *_hintLabel;
    UIView *_topLine;
    NSLayoutConstraint *_textHeightConstraint;
    NSLayoutConstraint *_hintHeightConstraint;
    CGFloat _textHeight;
    CGFloat _lastTextWidth;
    id _onCommit;
    id _onScopeChange;
    id _onTextChange;
    id _onBeginEditing;
    id _onPrefix;
    BOOL _scopeStagedOnly;
}
@end

@implementation CAGitCommitBar

- (id)initWithFrame:(id)arg1
{
    CGRect frame = CGRectZero;
    if ([arg1 isKindOfClass:NSValue.class]) {
        frame = [(NSValue *)arg1 CGRectValue];
    }
    if ((self = [super initWithFrame:frame])) {
        _textHeight = 34.0;
        _scopeStagedOnly = NO;

        _topLine = [[UIView alloc] init];
        _topLine.translatesAutoresizingMaskIntoConstraints = NO;

        _scopeControl = [[UISegmentedControl alloc] initWithItems:@[ @"全部更改", @"仅已暂存" ]];
        _scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
        _scopeControl.selectedSegmentIndex = 0;
        _scopeControl.apportionsSegmentWidthsByContent = NO;
        [_scopeControl addTarget:self action:@selector(scopeChanged) forControlEvents:UIControlEventValueChanged];

        _textView = [[UITextView alloc] init];
        _textView.translatesAutoresizingMaskIntoConstraints = NO;
        _textView.delegate = self;
        _textView.font = [UIFont systemFontOfSize:15.0];
        _textView.backgroundColor = UIColor.clearColor;
        _textView.textContainerInset = UIEdgeInsetsMake(7.0, 9.0, 7.0, 9.0);
        _textView.textContainer.lineFragmentPadding = 0.0;
        _textView.layer.cornerRadius = 10.0;
        _textView.layer.cornerCurve = kCACornerCurveContinuous;
        _textView.scrollEnabled = NO;

        _placeholder = [[UILabel alloc] init];
        _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
        _placeholder.font = [UIFont systemFontOfSize:15.0];
        _placeholder.text = @"这次修改了什么?";
        _placeholder.userInteractionEnabled = NO;

        _commitButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _commitButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_commitButton setTitle:@"✓ 提交" forState:UIControlStateNormal];
        _commitButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _commitButton.layer.cornerRadius = 10.0;
        _commitButton.layer.cornerCurve = kCACornerCurveContinuous;
        _commitButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 14.0, 0.0, 14.0);
        [_commitButton addTarget:self action:@selector(commitTapped) forControlEvents:UIControlEventTouchUpInside];

        _hintLabel = [[UILabel alloc] init];
        _hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _hintLabel.font = [UIFont systemFontOfSize:12.0];
        _hintLabel.numberOfLines = 2;
        _hintLabel.hidden = YES;

        for (UIView *subview in @[ _topLine, _scopeControl, _textView, _placeholder, _commitButton, _hintLabel ]) {
            [self addSubview:subview];
        }

        _textHeightConstraint = [_textView.heightAnchor constraintEqualToConstant:_textHeight];
        _hintHeightConstraint = [_hintLabel.heightAnchor constraintEqualToConstant:0.0];

        [NSLayoutConstraint activateConstraints:@[
            [_topLine.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_topLine.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_topLine.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_topLine.heightAnchor constraintEqualToConstant:0.5],

            [_scopeControl.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
            [_scopeControl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [_scopeControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [_scopeControl.heightAnchor constraintEqualToConstant:32.0],

            [_textView.topAnchor constraintEqualToAnchor:_scopeControl.bottomAnchor constant:8.0],
            [_textView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            _textHeightConstraint,
            [_commitButton.leadingAnchor constraintEqualToAnchor:_textView.trailingAnchor constant:8.0],
            [_commitButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [_commitButton.centerYAnchor constraintEqualToAnchor:_textView.centerYAnchor],
            [_commitButton.widthAnchor constraintGreaterThanOrEqualToConstant:78.0],
            [_commitButton.heightAnchor constraintEqualToConstant:34.0],

            [_placeholder.leadingAnchor constraintEqualToAnchor:_textView.leadingAnchor constant:13.0],
            [_placeholder.topAnchor constraintEqualToAnchor:_textView.topAnchor constant:9.0],

            [_hintLabel.topAnchor constraintEqualToAnchor:_textView.bottomAnchor constant:4.0],
            [_hintLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [_hintLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [_hintLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
            _hintHeightConstraint,
        ]];

        [self applyTheme];
        [self updatePlaceholder];
    }
    return self;
}

#pragma mark - 配置

- (void)configureWithStageAll:(id)arg1 allCount:(id)arg2 stagedCount:(id)arg3 canEdit:(id)arg4 canCommit:(id)arg5 hint:(id)arg6
{
    BOOL stageAll = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO;
    NSUInteger allCount = [(NSNumber *)arg2 respondsToSelector:@selector(unsignedIntegerValue)] ? [(NSNumber *)arg2 unsignedIntegerValue] : 0;
    NSUInteger stagedCount = [(NSNumber *)arg3 respondsToSelector:@selector(unsignedIntegerValue)] ? [(NSNumber *)arg3 unsignedIntegerValue] : 0;
    BOOL canEdit = [(NSNumber *)arg4 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg4 boolValue] : YES;
    BOOL canCommit = [(NSNumber *)arg5 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg5 boolValue] : NO;
    NSString *hint = [arg6 isKindOfClass:NSString.class] ? (NSString *)arg6 : nil;

    // 分段标题与截图逐字一致：「全部更改 24154」「仅已暂存 0」
    [_scopeControl setTitle:[NSString stringWithFormat:@"全部更改 %lu", (unsigned long)allCount] forSegmentAtIndex:0];
    [_scopeControl setTitle:[NSString stringWithFormat:@"仅已暂存 %lu", (unsigned long)stagedCount] forSegmentAtIndex:1];

    // 「全部更改」在没有任何更改时不可点（避免生成空提交）
    [_scopeControl setEnabled:(allCount > 0) forSegmentAtIndex:0];
    [_scopeControl setEnabled:(stagedCount > 0) forSegmentAtIndex:1];

    _textView.editable = canEdit;
    _textView.userInteractionEnabled = canEdit;
    _commitButton.enabled = canCommit && canEdit;
    _hintLabel.text = hint;
    _hintLabel.hidden = (hint.length == 0);
    _hintHeightConstraint.constant = (hint.length == 0) ? 0.0 : 32.0;

    if (!stageAll && _scopeStagedOnly) {
        _scopeStagedOnly = NO;
        _scopeControl.selectedSegmentIndex = 0;
    }
    [self applyTheme];
    [self updatePlaceholder];
}

#pragma mark - 状态

- (NSString *)message { return _textView.text ?: @""; }
- (void)setMessage:(id)arg1
{
    _textView.text = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    [self textChanged];
}

- (NSString *)trimmedMessage
{
    return [self.message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (BOOL)scopeIsStagedOnly { return _scopeStagedOnly; }

#pragma mark - 交互

- (void)commitTapped
{
    void (^handler)(NSString *) = _onCommit;
    if (handler) {
        handler(self.trimmedMessage);
    }
}

- (void)scopeChanged
{
    _scopeStagedOnly = (_scopeControl.selectedSegmentIndex == 1);
    void (^handler)(BOOL) = _onScopeChange;
    if (handler) {
        handler(_scopeStagedOnly);
    }
}

- (void)textChanged
{
    [self updatePlaceholder];
    void (^handler)(NSString *) = _onTextChange;
    if (handler) {
        handler(self.message);
    }
}

- (void)focusMessage
{
    if (_textView.editable) {
        [_textView becomeFirstResponder];
    }
}

- (void)prefixTapped:(id)arg1
{
    void (^handler)(id) = _onPrefix;
    if (handler) {
        handler(arg1);
    }
}

- (void)doneTapped
{
    [_textView resignFirstResponder];
}

- (void)updatePlaceholder
{
    _placeholder.hidden = (self.message.length > 0);
}

- (id)buildAccessoryView
{
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, UIScreen.mainScreen.bounds.size.width, 44.0)];
    UIBarButtonItem *slash = [[UIBarButtonItem alloc] initWithTitle:@"/"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(prefixTapped:)];
    slash.accessibilityLabel = @"插入前缀";
    UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                                            style:UIBarButtonItemStyleDone
                                                           target:self
                                                           action:@selector(doneTapped)];
    toolbar.items = @[ slash, flexible, done ];
    [toolbar sizeToFit];
    return toolbar;
}

#pragma mark - 布局 / 主题

- (void)updateTextHeightAnimated:(id)arg1
{
    BOOL animated = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO;
    CGFloat width = CGRectGetWidth(_textView.bounds) - _textView.textContainerInset.left - _textView.textContainerInset.right;
    if (width <= 0.0) {
        return;
    }
    CGSize fitting = [_textView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    CGFloat height = MAX(34.0, MIN(96.0, ceil(fitting.height)));
    if (fabs(height - _textHeight) < 0.5) {
        return;
    }
    _textHeight = height;
    _textHeightConstraint.constant = height;
    void (^changes)(void) = ^{
        [self.superview layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.18 animations:changes];
    } else {
        changes();
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    // 首次布局时按内容算一次高度；宽度变化时重算
    CGFloat width = CGRectGetWidth(_textView.bounds);
    if (width > 0.0 && fabs(width - _lastTextWidth) > 0.5) {
        _lastTextWidth = width;
        [self updateTextHeightAnimated:@NO];
    }

    _textView.layer.cornerRadius = 10.0;
    _commitButton.layer.cornerRadius = 10.0;
    _textView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _scopeControl.selectedSegmentTintColor = UIColor.secondarySystemGroupedBackgroundColor;
}

- (void)applyTheme
{
    self.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _topLine.backgroundColor = UIColor.separatorColor;
    _placeholder.textColor = UIColor.placeholderTextColor;
    _textView.textColor = UIColor.labelColor;
    _hintLabel.textColor = UIColor.secondaryLabelColor;

    BOOL enabled = _commitButton.enabled;
    _commitButton.backgroundColor = enabled ? [UIColor.systemBlueColor colorWithAlphaComponent:0.14]
                                            : UIColor.tertiarySystemFillColor;
    [_commitButton setTitleColor:enabled ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor forState:UIControlStateNormal];
    [_commitButton setTitleColor:enabled ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor forState:UIControlStateDisabled];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    [self applyTheme];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(id)arg1
{
    [self textChanged];
    [self updateTextHeightAnimated:@YES];
}

- (void)textViewDidBeginEditing:(id)arg1
{
    void (^handler)(void) = _onBeginEditing;
    if (handler) {
        handler();
    }
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    return YES;
}

#pragma mark - 回调访问器

- (id)onBeginEditing { return _onBeginEditing; }
- (void)setOnBeginEditing:(id)arg1 { _onBeginEditing = arg1; }

- (id)onCommit { return _onCommit; }
- (void)setOnCommit:(id)arg1 { _onCommit = arg1; }

- (id)onPrefix { return _onPrefix; }
- (void)setOnPrefix:(id)arg1 { _onPrefix = arg1; }

- (id)onScopeChange { return _onScopeChange; }
- (void)setOnScopeChange:(id)arg1 { _onScopeChange = arg1; }

- (id)onTextChange { return _onTextChange; }
- (void)setOnTextChange:(id)arg1 { _onTextChange = arg1; }

@end
