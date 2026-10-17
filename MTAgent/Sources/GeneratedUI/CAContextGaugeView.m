//
//  CAContextGaugeView — 上下文用量环形指示器。
//

#import "CAContextGaugeView.h"

@interface CAContextGaugeView ()
@property (nonatomic, copy) NSString *centerTextValue;
@property (nonatomic, assign) NSInteger percentValue;
@end

@implementation CAContextGaugeView

- (NSString *)centerText
{
    return self.centerTextValue ?: @"";
}

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    if (side <= 0.0) return;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MAX(1.0, side * 0.36);
    CGFloat lineWidth = MAX(3.0, side * 0.09);
    CGFloat start = (CGFloat)(-M_PI_2);
    CGFloat end = start + (CGFloat)(M_PI * 2.0 * ((double)self.percentValue / 100.0));

    UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:center radius:radius
                                                         startAngle:0.0 endAngle:(CGFloat)(M_PI * 2.0)
                                                        clockwise:YES];
    track.lineWidth = lineWidth;
    track.lineCapStyle = kCGLineCapRound;
    [UIColor.tertiarySystemFillColor setStroke];
    [track stroke];

    if (self.percentValue > 0) {
        UIBezierPath *value = [UIBezierPath bezierPathWithArcCenter:center radius:radius
                                                            startAngle:start endAngle:end clockwise:YES];
        value.lineWidth = lineWidth;
        value.lineCapStyle = kCGLineCapRound;
        [UIColor.systemBlueColor setStroke];
        [value stroke];
    }

    NSString *text = self.centerTextValue ?: [NSString stringWithFormat:@"%ld%%", (long)self.percentValue];
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
        NSForegroundColorAttributeName: UIColor.labelColor
    };
    CGSize textSize = [text sizeWithAttributes:attributes];
    [text drawAtPoint:CGPointMake(center.x - textSize.width * 0.5, center.y - textSize.height * 0.5)
       withAttributes:attributes];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _percentValue = 0;
        _centerTextValue = @"0%";
        self.backgroundColor = UIColor.clearColor;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"上下文用量";
    }
    return self;
}

- (signed long long)percent
{
    return self.percentValue;
}

- (void)setCenterText:(id)arg1
{
    self.centerTextValue = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : [arg1 description];
    [self setNeedsDisplay];
}

- (void)setPercent:(id)arg1
{
    NSInteger value = [arg1 respondsToSelector:@selector(integerValue)] ? [arg1 integerValue] : 0;
    self.percentValue = MAX(0, MIN(100, value));
    if (self.centerTextValue.length == 0 || [self.centerTextValue hasSuffix:@"%"])
        self.centerTextValue = [NSString stringWithFormat:@"%ld%%", (long)self.percentValue];
    self.accessibilityValue = [NSString stringWithFormat:@"%ld%%", (long)self.percentValue];
    [self setNeedsDisplay];
}

- (void)themeDidChange
{
    [self setNeedsDisplay];
}

@end
