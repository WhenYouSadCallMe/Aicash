//
//  CAGitPill.m — 分支 / 远程胶囊（仓库卡片里「主分支 · master ›」那颗蓝色胶囊）
//
//  观感对齐原版截图：浅蓝底、深蓝字、左侧 SF Symbol、可选右侧 chevron；
//  禁用态整体降为灰色（不可用时不响应点击，与截图里的置灰按钮一致）。
//

#import "CAGitPill.h"

@interface CAGitPill ()
{
    UILabel *_label;
    UIImageView *_iconView;
    UIImageView *_chevronView;
    BOOL _emphasized;
}
@end

@implementation CAGitPill

- (id)initWithFrame:(id)arg1
{
    // 头文件把 CGRect 占位成了 id：调用方传 NSValue，缺省退化成零矩形
    CGRect frame = CGRectZero;
    if ([arg1 isKindOfClass:NSValue.class]) {
        frame = [(NSValue *)arg1 CGRectValue];
    }
    if ((self = [super initWithFrame:frame])) {
        _emphasized = NO;

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;

        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        _label.numberOfLines = 1;

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.hidden = YES;

        for (UIView *subview in @[ _iconView, _label, _chevronView ]) {
            [self addSubview:subview];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
            [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:13.0],
            [_iconView.heightAnchor constraintEqualToConstant:13.0],

            [_label.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:5.0],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_chevronView.leadingAnchor constraintEqualToAnchor:_label.trailingAnchor constant:5.0],
            [_chevronView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
            [_chevronView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:11.0],
            [_chevronView.heightAnchor constraintEqualToConstant:11.0],
        ]];

        [self applyAppearance];
    }
    return self;
}

- (void)configureWithTitle:(id)arg1 symbol:(id)arg2 emphasized:(id)arg3 showsChevron:(id)arg4
{
    _label.text = (NSString *)arg1;
    _emphasized = [(NSNumber *)arg3 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg3 boolValue] : NO;

    NSString *symbol = (NSString *)arg2;
    _iconView.image = symbol.length > 0 ? [UIImage systemImageNamed:symbol] : nil;
    _iconView.hidden = (symbol.length == 0);

    BOOL showsChevron = [(NSNumber *)arg4 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg4 boolValue] : NO;
    _chevronView.hidden = !showsChevron;

    [self applyAppearance];
    [self invalidateIntrinsicContentSize];
}

- (void)setEnabled:(id)arg1
{
    BOOL enabled = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : YES;
    [super setEnabled:enabled];
    [self applyAppearance];
}

- (void)setHighlighted:(id)arg1
{
    BOOL highlighted = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO;
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.alpha = highlighted ? 0.6 : 1.0;
    }];
}

- (CGSize)intrinsicContentSize
{
    CGFloat width = 10.0;
    width += _iconView.hidden ? 0.0 : 13.0 + 5.0;
    width += [_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20.0)].width;
    width += _chevronView.hidden ? 0.0 : 5.0 + 11.0;
    width += 10.0;
    return CGSizeMake(ceil(width), 28.0);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    [self applyAppearance];
}

#pragma mark - 私有

- (void)applyAppearance
{
    BOOL active = self.enabled && _emphasized;
    UIColor *tint = self.enabled ? (_emphasized ? UIColor.systemBlueColor : UIColor.labelColor) : UIColor.tertiaryLabelColor;

    self.backgroundColor = active ? [UIColor.systemBlueColor colorWithAlphaComponent:0.14]
                                  : [UIColor.secondarySystemFillColor colorWithAlphaComponent:self.enabled ? 0.7 : 0.4];
    _label.textColor = tint;
    _iconView.tintColor = tint;
    _chevronView.tintColor = self.enabled ? UIColor.tertiaryLabelColor : UIColor.quaternaryLabelColor;
    self.userInteractionEnabled = self.enabled;
}

@end
