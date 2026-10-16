//
//  MTSubagentModelBadge.m
//

#import "MTSubagentModelBadge.h"

@implementation MTSubagentModelBadge
{
    UILabel *_label;
    UIStackView *_stack;
    UIView *_dot;
}

- (instancetype)initWithSlug:(NSString *)slug
{
    if ((self = [super initWithFrame:CGRectMake(0, 0, 88, 22)])) {
        self.layer.cornerRadius = 11.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        _stack = [UIStackView new];
        _stack.axis = UILayoutConstraintAxisHorizontal;
        _stack.spacing = 5.0;
        _stack.alignment = UIStackViewAlignmentCenter;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];

        _dot = [UIView new];
        _dot.translatesAutoresizingMaskIntoConstraints = NO;
        _dot.layer.cornerRadius = 3.0;
        _dot.backgroundColor = [UIColor tertiaryLabelColor];
        [_dot.widthAnchor constraintEqualToConstant:6.0].active = YES;
        [_dot.heightAnchor constraintEqualToConstant:6.0].active = YES;
        [_stack addArrangedSubview:_dot];

        _label = [UILabel new];
        _label.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
        _label.textColor = [UIColor secondaryLabelColor];
        _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_stack addArrangedSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:3.0],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3.0],
        ]];

        self.style = @"default";
        self.modelSlug = slug;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setModelSlug:(NSString *)modelSlug
{
    _modelSlug = [modelSlug copy];
    NSString *text = _modelSlug.length ? _modelSlug : @"default";
    // 超长 slug 截中段
    if (text.length > 28) {
        text = [NSString stringWithFormat:@"%@…%@",
                [text substringToIndex:14], [text substringFromIndex:text.length - 10]];
    }
    _label.text = text;
}

- (void)setStyle:(NSString *)style
{
    _style = [style ?: @"default" copy];
    UIColor *background;
    UIColor *foreground;
    UIColor *dot;
    if ([_style isEqualToString:@"active"]) {
        background = [[UIColor systemBlueColor] colorWithAlphaComponent:0.14];
        foreground = [UIColor systemBlueColor];
        dot = [UIColor systemBlueColor];
    } else if ([_style isEqualToString:@"remote"]) {
        background = [[UIColor systemPurpleColor] colorWithAlphaComponent:0.14];
        foreground = [UIColor systemPurpleColor];
        dot = [UIColor systemPurpleColor];
    } else {
        background = [UIColor secondarySystemBackgroundColor];
        foreground = [UIColor secondaryLabelColor];
        dot = [UIColor tertiaryLabelColor];
    }
    self.backgroundColor = background;
    _label.textColor = foreground;
    _dot.backgroundColor = dot;
}

+ (CGSize)sizeForSlug:(NSString *)slug
{
    NSString *text = slug.length ? slug : @"default";
    if (text.length > 28) text = [text substringToIndex:14];
    NSDictionary *attributes = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium] };
    CGFloat width = [text sizeWithAttributes:attributes].width;
    return CGSizeMake(MAX(64.0, width + 34.0), 22.0);
}

- (void)tapped
{
    if (self.tapHandler) self.tapHandler(self);
}

@end
