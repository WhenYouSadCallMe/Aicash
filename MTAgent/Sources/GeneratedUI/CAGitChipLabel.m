//
//  CAGitChipLabel.m — Git 状态胶囊标签（「未跟踪」「已修改」「已暂存」这类）
//
//  实现要点（对齐原包 ivar 与截图观感）：
//    · _contentInsets 控制文字四周留白，胶囊圆角取高度一半
//    · configureWithText:color: 里用颜色派生浅底（同色 18% 透明度）+ 同色文字
//    · drawTextInRect: 在留白矩形内绘制；intrinsicContentSize 把留白算进去
//

#import "CAGitChipLabel.h"

@interface CAGitChipLabel ()
{
    UIEdgeInsets _contentInsets;
    UIColor *_chipTintColor;
}
@end

@implementation CAGitChipLabel

- (id)initWithFrame:(id)arg1
{
    // 头文件把 CGRect 占位成了 id：调用方传 NSValue，缺省退化成零矩形
    CGRect frame = CGRectZero;
    if ([arg1 isKindOfClass:NSValue.class]) {
        frame = [(NSValue *)arg1 CGRectValue];
    }
    if ((self = [super initWithFrame:frame])) {
        _contentInsets = UIEdgeInsetsMake(2.0, 7.0, 2.0, 7.0);
        _chipTintColor = UIColor.secondaryLabelColor;
        self.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        self.textAlignment = NSTextAlignmentCenter;
        self.numberOfLines = 1;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        [self applyChipColors];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _contentInsets = UIEdgeInsetsMake(2.0, 7.0, 2.0, 7.0);
        _chipTintColor = UIColor.secondaryLabelColor;
        self.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        self.textAlignment = NSTextAlignmentCenter;
        [self applyChipColors];
    }
    return self;
}

- (void)configureWithText:(id)arg1 color:(id)arg2
{
    self.text = (NSString *)arg1;
    _chipTintColor = (UIColor *)arg2 ?: UIColor.secondaryLabelColor;
    [self applyChipColors];
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (UIEdgeInsets)contentInsets
{
    return _contentInsets;
}

- (void)setContentInsets:(id)arg1
{
    NSValue *value = (NSValue *)arg1;
    if ([value respondsToSelector:@selector(UIEdgeInsetsValue)]) {
        _contentInsets = value.UIEdgeInsetsValue;
    } else {
        _contentInsets = (UIEdgeInsets){ 2.0, 7.0, 2.0, 7.0 };
    }
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (CGSize)intrinsicContentSize
{
    CGSize size = [super intrinsicContentSize];
    size.width += _contentInsets.left + _contentInsets.right;
    size.height += _contentInsets.top + _contentInsets.bottom;
    return size;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    CGSize fitted = [super sizeThatFits:size];
    fitted.width = ceil(fitted.width) + _contentInsets.left + _contentInsets.right;
    fitted.height = ceil(fitted.height) + _contentInsets.top + _contentInsets.bottom;
    return fitted;
}

- (void)drawTextInRect:(id)arg1
{
    NSValue *value = (NSValue *)arg1;
    CGRect rect = [value respondsToSelector:@selector(CGRectValue)] ? value.CGRectValue : self.bounds;
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, _contentInsets)];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    [self applyChipColors];
}

#pragma mark - 私有

/// 由文字色派生浅色底：保持胶囊在浅色/深色模式下都有可读对比
- (void)applyChipColors
{
    UIColor *tint = _chipTintColor ?: UIColor.secondaryLabelColor;
    self.textColor = tint;
    self.backgroundColor = [tint colorWithAlphaComponent:0.16];
}

@end
