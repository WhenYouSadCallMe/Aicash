//
//  CAStreamingTextView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：流式助手文本视图。上层每次把「当前累计文本」交给
//  -updateStreamingText:（不是增量），视图内部用 CADisplayLink 逐单位揭示（reveal），
//  回合结束时由上层调用 -finishStreamingReveal 直接补齐。
//
//  注意（自动生成头文件的坑）：
//    · -initWithFrame: 的形参被占位成 id，禁止外部用 CGRect 调用（ABI 不匹配）；
//      一律 [[CAStreamingTextView alloc] init] 创建；
//    · 标量字段的 setter 形参也是 id，因此内部用 ivar，访问器按头文件签名逐字实现。
//

#import "CAStreamingTextView.h"
#import "CAStreamRevealTarget.h"
#import <QuartzCore/QuartzCore.h>

@interface CAStreamingTextView () {
    double _measuredWidth;
    double _cachedTextWidth;
    double _cachedTextHeight;
    bool _hasCachedTextSize;
    bool _textSizeDirty;
    bool _intrinsicInvalidationPending;
    bool _suppressSizeInvalidation;
    UIFont *_chatFont;
    UIColor *_chatTextColor;
}

@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, copy) NSString *targetText;
@property (nonatomic, strong) NSMutableString *revealedText;
@property (nonatomic, strong) CAStreamRevealTarget *revealTarget;
@property (nonatomic, strong) CADisplayLink *revealDisplayLink;
@property (nonatomic, strong) NSMutableArray *revealUnits;
@property (nonatomic, strong) NSParagraphStyle *streamingParagraph;
@end

@implementation CAStreamingTextView

#pragma mark - 生命周期

- (id)initWithFrame:(id)arg1
{
    // 头文件把形参占位成 id：忽略入参，永远从零尺寸起（见文件头说明）。
    if ((self = [super initWithFrame:CGRectZero])) {
        _textLabel = [[UILabel alloc] init];
        _textLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _textLabel.numberOfLines = 0;
        _textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _textLabel.textColor = UIColor.labelColor;
        [self addSubview:_textLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_textLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_textLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_textLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_textLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        ]];

        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.clearColor;
        _revealedText = [NSMutableString string];
        _revealUnits = [NSMutableArray array];
        _targetText = @"";
        _chatFont = _textLabel.font;
        _chatTextColor = _textLabel.textColor;
        _textSizeDirty = YES;
    }
    return self;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) {
        [self startRevealLinkIfNeeded];
    } else {
        [self stopRevealLink];
    }
}

#pragma mark - 标量访问器（形参与头文件一致：id）

- (double)measuredWidth { return _measuredWidth; }

- (void)setMeasuredWidth:(id)arg1
{
    _measuredWidth = [arg1 respondsToSelector:@selector(doubleValue)] ? [arg1 doubleValue] : 0;
    _hasCachedTextSize = NO;
}

- (double)cachedTextWidth { return _cachedTextWidth; }

- (void)setCachedTextWidth:(id)arg1
{
    _cachedTextWidth = [arg1 respondsToSelector:@selector(doubleValue)] ? [arg1 doubleValue] : 0;
}

- (double)cachedTextHeight { return _cachedTextHeight; }

- (void)setCachedTextHeight:(id)arg1
{
    _cachedTextHeight = [arg1 respondsToSelector:@selector(doubleValue)] ? [arg1 doubleValue] : 0;
}

- (bool)hasCachedTextSize { return _hasCachedTextSize; }

- (void)setHasCachedTextSize:(id)arg1
{
    _hasCachedTextSize = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)textSizeDirty { return _textSizeDirty; }

- (void)setTextSizeDirty:(id)arg1
{
    _textSizeDirty = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)intrinsicInvalidationPending { return _intrinsicInvalidationPending; }

- (void)setIntrinsicInvalidationPending:(id)arg1
{
    _intrinsicInvalidationPending = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)suppressSizeInvalidation { return _suppressSizeInvalidation; }

- (void)setSuppressSizeInvalidation:(id)arg1
{
    _suppressSizeInvalidation = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

#pragma mark - 字体 / 颜色 / 段落

- (void)setFont:(id)arg1
{
    _chatFont = [arg1 isKindOfClass:UIFont.class] ? arg1 : nil;
    self.textLabel.font = _chatFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [self textGeometryDidChange];
}

- (void)setTextColor:(id)arg1
{
    _chatTextColor = [arg1 isKindOfClass:UIColor.class] ? arg1 : nil;
    self.textLabel.textColor = _chatTextColor ?: UIColor.labelColor;
}

- (void)setStreamingParagraph:(id)arg1
{
    _streamingParagraph = [arg1 isKindOfClass:NSParagraphStyle.class] ? arg1 : nil;
    [self textGeometryDidChange];
}

#pragma mark - 文本

- (void)updateStreamingText:(id)arg1
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    text = text ?: @"";

    // 内容回退 / 换消息：直接重置已揭示部分。
    if (![text hasPrefix:self.revealedText]) {
        [self.revealedText setString:@""];
    }
    self.targetText = text;

    NSUInteger revealed = self.revealedText.length;
    if (text.length > revealed) {
        [self.revealUnits removeAllObjects];
        for (NSUInteger index = revealed; index < text.length; index++) {
            [self.revealUnits addObject:[text substringWithRange:NSMakeRange(index, 1)]];
        }
        [self startRevealLinkIfNeeded];
    } else {
        [self.revealUnits removeAllObjects];
        self.textLabel.text = text;
    }
    [self textGeometryDidChange];
}

- (void)appendRevealedChunk:(NSString *)chunk
{
    if (chunk.length == 0) return;
    [self.revealedText appendString:chunk];
    self.textLabel.text = self.revealedText;
    [self requestIntrinsicSizeInvalidation];
}

#pragma mark - 揭示（reveal）

- (void)startRevealLinkIfNeeded
{
    if (self.revealDisplayLink || self.revealUnits.count == 0 || !self.window) return;
    CAStreamRevealTarget *target = [[CAStreamRevealTarget alloc] init];
    target.view = self;
    self.revealTarget = target;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    link.preferredFramesPerSecond = 60;
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    self.revealDisplayLink = link;
}

- (void)stopRevealLink
{
    [self.revealDisplayLink invalidate];
    self.revealDisplayLink = nil;
    self.revealTarget = nil;
}

- (void)advanceReveal:(id)arg1
{
    if (self.revealUnits.count == 0) {
        [self stopRevealLink];
        return;
    }
    NSUInteger backlog = self.revealUnits.count;
    NSUInteger step = MAX((NSUInteger)3, backlog / 6);
    step = MIN(step, backlog);

    NSMutableString *chunk = [NSMutableString stringWithCapacity:step];
    for (NSUInteger index = 0; index < step; index++) {
        id unit = self.revealUnits[index];
        if ([unit isKindOfClass:NSString.class]) [chunk appendString:unit];
    }
    [self.revealUnits removeObjectsInRange:NSMakeRange(0, step)];
    [self appendRevealedChunk:chunk];

    if (self.revealUnits.count == 0) [self stopRevealLink];
}

- (void)finishStreamingReveal
{
    [self.revealUnits removeAllObjects];
    [self stopRevealLink];
    NSString *finalText = self.targetText ?: @"";
    [self.revealedText setString:finalText];
    self.textLabel.text = finalText;
    [self textGeometryDidChange];
}

#pragma mark - 尺寸

- (void)textGeometryDidChange
{
    _hasCachedTextSize = NO;
    _textSizeDirty = YES;
    [self requestIntrinsicSizeInvalidation];
}

- (double)textHeightForWidth:(id)arg1
{
    CGFloat width = [arg1 respondsToSelector:@selector(doubleValue)] ? (CGFloat)[arg1 doubleValue] : self.bounds.size.width;
    if (width <= 0) return 0;
    NSString *text = self.targetText.length > 0 ? self.targetText : (self.textLabel.text ?: @"");
    if (text.length == 0) return 0;
    if (_hasCachedTextSize && fabs(_cachedTextWidth - width) < 0.5) return _cachedTextHeight;

    UIFont *font = self.textLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    CGRect bounding = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                      attributes:@{ NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraph }
                                         context:nil];
    CGFloat height = ceil(CGRectGetHeight(bounding));
    _cachedTextWidth = width;
    _cachedTextHeight = height;
    _hasCachedTextSize = YES;
    return height;
}

- (void)requestIntrinsicSizeInvalidation
{
    if (_suppressSizeInvalidation || _intrinsicInvalidationPending) return;
    _intrinsicInvalidationPending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_intrinsicInvalidationPending = NO;
        [strongSelf setNeedsLayout];
        [super invalidateIntrinsicContentSize];
    });
}

- (void)invalidateIntrinsicContentSize
{
    [self textGeometryDidChange];
}

- (CGSize)intrinsicContentSize
{
    CGFloat width = _measuredWidth > 0 ? (CGFloat)_measuredWidth : self.bounds.size.width;
    if (width <= 0) width = UIScreen.mainScreen.bounds.size.width - 48.0;
    CGFloat height = (CGFloat)[self textHeightForWidth:@(width)];
    return CGSizeMake(UIViewNoIntrinsicMetric, MAX(height, 1.0));
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    if (width > 0 && fabs((CGFloat)_measuredWidth - width) > 0.5) {
        _measuredWidth = width;
        _hasCachedTextSize = NO;
    }
}

@end
