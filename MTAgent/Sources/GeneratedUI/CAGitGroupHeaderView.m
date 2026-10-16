//
//  CAGitGroupHeaderView.m — 分区标题行（橙色笔图标 + 标题 + 计数胶囊 + 右侧动作 + 折叠箭头）
//
//  原包 ivar：_actionButton / _chevronView / _countChip / _iconView / _onAction / _onToggle / _tapArea / _titleLabel。
//  版式对齐截图 06：左侧橙色铅笔图标 → 标题「未暂存的更改」→ 灰色计数胶囊「24154」
//                  → 右侧蓝色文字按钮「全部暂存」→ 折叠箭头 chevron.down（展开时朝下，折叠时朝右）。
//

#import "CAGitGroupHeaderView.h"
#import "CAGitChipLabel.h"

@interface CAGitGroupHeaderView ()
{
    UILabel *_titleLabel;
    CAGitChipLabel *_countChip;
    UIImageView *_iconView;
    UIButton *_actionButton;
    UIImageView *_chevronView;
    UIView *_tapArea;
    id _onAction;
    id _onToggle;
}
@end

@implementation CAGitGroupHeaderView

- (id)initWithReuseIdentifier:(id)arg1
{
    if ((self = [super initWithFrame:CGRectZero])) {
        self.backgroundColor = UIColor.systemGroupedBackgroundColor;

        _tapArea = [[UIView alloc] init];
        _tapArea.translatesAutoresizingMaskIntoConstraints = NO;
        _tapArea.backgroundColor = UIColor.clearColor;

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];

        _countChip = [[CAGitChipLabel alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
        _countChip.translatesAutoresizingMaskIntoConstraints = NO;
        _countChip.hidden = YES;

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.tintColor = UIColor.tertiaryLabelColor;
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;

        [self addSubview:_tapArea];
        for (UIView *subview in @[ _iconView, _titleLabel, _countChip, _actionButton, _chevronView ]) {
            [self addSubview:subview];
        }
        // 点击标题区折叠/展开；点击按钮只触发动作
        [_tapArea addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleTapped)]];

        [NSLayoutConstraint activateConstraints:@[
            [_tapArea.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_tapArea.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_tapArea.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_tapArea.trailingAnchor constraintEqualToAnchor:_actionButton.leadingAnchor],

            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:16.0],
            [_iconView.heightAnchor constraintEqualToConstant:16.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:8.0],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_countChip.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:8.0],
            [_countChip.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_countChip.heightAnchor constraintGreaterThanOrEqualToConstant:20.0],

            [_actionButton.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-6.0],
            [_actionButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_chevronView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [_chevronView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:12.0],
            [_chevronView.heightAnchor constraintEqualToConstant:12.0],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(id)arg1 count:(id)arg2 symbol:(id)arg3 tint:(id)arg4 expanded:(id)arg5 actionTitle:(id)arg6 actionEnabled:(id)arg7
{
    _titleLabel.text = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";

    NSUInteger count = [(NSNumber *)arg2 respondsToSelector:@selector(unsignedIntegerValue)] ? [(NSNumber *)arg2 unsignedIntegerValue] : 0;
    _countChip.hidden = (arg2 == nil);
    [_countChip configureWithText:[NSString stringWithFormat:@"%lu", (unsigned long)count] color:UIColor.secondaryLabelColor];

    NSString *symbol = [arg3 isKindOfClass:NSString.class] ? (NSString *)arg3 : @"pencil";
    UIColor *tint = [arg4 isKindOfClass:UIColor.class] ? (UIColor *)arg4 : UIColor.systemOrangeColor;
    _iconView.image = [UIImage systemImageNamed:symbol];
    _iconView.tintColor = tint;

    BOOL expanded = [(NSNumber *)arg5 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg5 boolValue] : YES;
    _chevronView.image = [UIImage systemImageNamed:expanded ? @"chevron.down" : @"chevron.right"];

    NSString *actionTitle = [arg6 isKindOfClass:NSString.class] ? (NSString *)arg6 : nil;
    BOOL actionEnabled = [(NSNumber *)arg7 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg7 boolValue] : YES;
    [_actionButton setTitle:actionTitle forState:UIControlStateNormal];
    _actionButton.hidden = (actionTitle.length == 0);
    _actionButton.enabled = actionEnabled;
    [_actionButton setTitleColor:actionEnabled ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor forState:UIControlStateNormal];
}

- (void)prepareForReuse
{
    _titleLabel.text = nil;
    _countChip.text = nil;
    _countChip.hidden = YES;
    _onAction = nil;
    _onToggle = nil;
}

- (void)actionTapped
{
    void (^handler)(void) = _onAction;
    if (handler) {
        handler();
    }
}

- (void)toggleTapped
{
    void (^handler)(void) = _onToggle;
    if (handler) {
        handler();
    }
}

- (id)onAction { return _onAction; }
- (void)setOnAction:(id)arg1 { _onAction = arg1; }

- (id)onToggle { return _onToggle; }
- (void)setOnToggle:(id)arg1 { _onToggle = arg1; }

@end
