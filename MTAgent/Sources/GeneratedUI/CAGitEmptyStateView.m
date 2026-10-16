//
//  CAGitEmptyStateView.m — Git 面板的空态 / 加载态
//
//  原包 ivar：_actionButton / _detailLabel / _iconView / _iconWell / _onAction / _spinner / _titleLabel。
//  用法：
//    showSymbol:title:detail:actionTitle:  正常空态（图标 + 标题 + 说明 + 可选动作按钮）
//    showLoadingWithTitle:                 加载态（转圈 + 文案）
//

#import "CAGitEmptyStateView.h"

@interface CAGitEmptyStateView ()
{
    UIView *_iconWell;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_detailLabel;
    UIButton *_actionButton;
    UIActivityIndicatorView *_spinner;
    id _onAction;
}
@end

@implementation CAGitEmptyStateView

- (id)initWithFrame:(id)arg1
{
    CGRect frame = CGRectZero;
    if ([arg1 isKindOfClass:NSValue.class]) {
        frame = [(NSValue *)arg1 CGRectValue];
    }
    if ((self = [super initWithFrame:frame])) {
        _iconWell = [[UIView alloc] init];
        _iconWell.translatesAutoresizingMaskIntoConstraints = NO;
        _iconWell.layer.cornerRadius = 34.0;
        _iconWell.layer.cornerCurve = kCACornerCurveContinuous;
        _iconWell.backgroundColor = UIColor.tertiarySystemFillColor;

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconWell addSubview:_iconView];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        [_iconWell addSubview:_spinner];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [UIFont systemFontOfSize:14.0];
        _detailLabel.textColor = UIColor.secondaryLabelColor;
        _detailLabel.textAlignment = NSTextAlignmentCenter;
        _detailLabel.numberOfLines = 0;

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
        _actionButton.layer.cornerRadius = 10.0;
        _actionButton.layer.cornerCurve = kCACornerCurveContinuous;
        _actionButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
        _actionButton.hidden = YES;
        [_actionButton addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];

        for (UIView *subview in @[ _iconWell, _titleLabel, _detailLabel, _actionButton ]) {
            [self addSubview:subview];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_iconWell.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_iconWell.topAnchor constraintEqualToAnchor:self.topAnchor constant:32.0],
            [_iconWell.widthAnchor constraintEqualToConstant:68.0],
            [_iconWell.heightAnchor constraintEqualToConstant:68.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconWell.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconWell.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:30.0],
            [_iconView.heightAnchor constraintEqualToConstant:30.0],

            [_spinner.centerXAnchor constraintEqualToAnchor:_iconWell.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:_iconWell.centerYAnchor],

            [_titleLabel.topAnchor constraintEqualToAnchor:_iconWell.bottomAnchor constant:16.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:32.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-32.0],

            [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],
            [_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

            [_actionButton.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:16.0],
            [_actionButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_actionButton.heightAnchor constraintEqualToConstant:36.0],
            [_actionButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-24.0],
        ]];

        [self applyTheme];
    }
    return self;
}

- (void)showSymbol:(id)arg1 title:(id)arg2 detail:(id)arg3 actionTitle:(id)arg4
{
    [_spinner stopAnimating];
    NSString *symbol = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"arrow.triangle.branch";
    _iconView.hidden = NO;
    _iconView.image = [UIImage systemImageNamed:symbol];
    _iconView.tintColor = UIColor.secondaryLabelColor;
    _titleLabel.text = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : @"";
    _detailLabel.text = [arg3 isKindOfClass:NSString.class] ? (NSString *)arg3 : @"";

    NSString *actionTitle = [arg4 isKindOfClass:NSString.class] ? (NSString *)arg4 : nil;
    _actionButton.hidden = (actionTitle.length == 0);
    [_actionButton setTitle:actionTitle forState:UIControlStateNormal];
    [self applyTheme];
}

- (void)showLoadingWithTitle:(id)arg1
{
    _iconView.hidden = YES;
    [_spinner startAnimating];
    _titleLabel.text = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"正在读取仓库…";
    _detailLabel.text = @"";
    _actionButton.hidden = YES;
}

- (void)applyTheme
{
    self.backgroundColor = UIColor.clearColor;
    _titleLabel.textColor = UIColor.labelColor;
    _detailLabel.textColor = UIColor.secondaryLabelColor;
    _iconWell.backgroundColor = UIColor.tertiarySystemFillColor;
    _actionButton.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.14];
    [_actionButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
}

- (void)actionTapped
{
    void (^handler)(void) = _onAction;
    if (handler) {
        handler();
    }
}

- (id)onAction { return _onAction; }
- (void)setOnAction:(id)arg1 { _onAction = arg1; }

@end
