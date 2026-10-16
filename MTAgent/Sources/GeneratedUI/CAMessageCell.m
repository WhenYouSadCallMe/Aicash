//
//  CAMessageCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：文本消息气泡（用户 / 助手 / 系统提示）。
//    · 正文用 UIStackView 承载「文本段落 + 代码块（CACodeBlockView）」；
//    · 助手消息处于流式状态时改用 CAStreamingTextView 逐块揭示；
//    · 长按可复制本条消息的纯文本。
//
//  注意（自动生成头文件的坑）：
//    · -initWithFrame: 形参被占位成 id → 内部只当“创建”用，忽略入参；
//    · 表视图经 dequeue 创建 cell 时不会走本类的 init 路径，因此界面在
//      -configureWithMessage: / -layoutSubviews 里惰性搭建（ensureChatUI）；
//    · 标量字段 setter 形参为 id → 内部用 ivar + 与头文件逐字一致的访问器。
//

#import "CAMessageCell.h"
#import "CAMessageItem.h"
#import "CAToolItem.h"
#import "CAStreamingTextView.h"
#import "CACodeBlockView.h"

static CGFloat const kCAMessageCellBubbleInset = 12.0;

@interface CAMessageCell () {
    bool _renderingStreaming;
    unsigned long long _streamingCommittedLength;
    unsigned long long _deferredBlockIndex;
    unsigned long long _deferredRenderGeneration;
    bool _configuredQueued;
}

@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UIStackView *bodyStack;
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *trailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *assistantWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bodyTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bodyBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bodyLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bodyTrailingConstraint;
@property (nonatomic, strong) CAStreamingTextView *streamingTextView;
@property (nonatomic, strong) id streamingTextLabel;
@property (nonatomic, copy) NSString *rawCopyText;
@property (nonatomic, strong) CAMessageItem *message;
@property (nonatomic, strong) NSDictionary *artifactLookup;
@property (nonatomic, strong) id attachmentPathResolver;
@property (nonatomic, strong) NSArray *deferredBlocks;
@property (nonatomic, strong) UIStackView *deferredBodyStack;
@property (nonatomic, copy) NSString *deferredMessageID;
@property (nonatomic, strong) id onDeferredRenderStep;
@property (nonatomic, strong) id onEditQueued;
@property (nonatomic, strong) id onOpenAttachmentPath;
@property (nonatomic, strong) id onOpenMarkdownLink;
@property (nonatomic, strong) id onSelectText;
@property (nonatomic, strong) id onSteerQueued;
@property (nonatomic, strong) id onWithdrawQueued;
@property (nonatomic, strong) id queuedBorderLayer;
@end

@implementation CAMessageCell

#pragma mark - 生命周期

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        [self setupChatBubble];
    }
    return self;
}

- (id)initWithFrame:(id)arg1
{
    if ((self = [super initWithFrame:CGRectZero])) {
        [self setupChatBubble];
    }
    return self;
}

- (void)ensureChatUI
{
    if (self.bodyStack) return;
    [self setupChatBubble];
}

- (void)setupChatBubble
{
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _bubbleView = [[UIView alloc] init];
    _bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
    _bubbleView.layer.cornerRadius = 14.0;
    _bubbleView.layer.masksToBounds = YES;
    [self.contentView addSubview:_bubbleView];

    _bodyStack = [[UIStackView alloc] init];
    _bodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    _bodyStack.axis = UILayoutConstraintAxisVertical;
    _bodyStack.alignment = UIStackViewAlignmentFill;
    _bodyStack.spacing = 8.0;
    [_bubbleView addSubview:_bodyStack];

    _leadingConstraint  = [_bubbleView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor];
    _trailingConstraint = [_bubbleView.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor];
    _assistantWidthConstraint = [_bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.86];

    _bodyTopConstraint      = [_bodyStack.topAnchor constraintEqualToAnchor:_bubbleView.topAnchor constant:kCAMessageCellBubbleInset];
    _bodyBottomConstraint   = [_bodyStack.bottomAnchor constraintEqualToAnchor:_bubbleView.bottomAnchor constant:-kCAMessageCellBubbleInset];
    _bodyLeadingConstraint  = [_bodyStack.leadingAnchor constraintEqualToAnchor:_bubbleView.leadingAnchor constant:kCAMessageCellBubbleInset];
    _bodyTrailingConstraint = [_bodyStack.trailingAnchor constraintEqualToAnchor:_bubbleView.trailingAnchor constant:-kCAMessageCellBubbleInset];

    [NSLayoutConstraint activateConstraints:@[
        [_bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3.0],
        [_bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3.0],
        _assistantWidthConstraint,
        _bodyTopConstraint,
        _bodyBottomConstraint,
        _bodyLeadingConstraint,
        _bodyTrailingConstraint,
    ]];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressCopy:)];
    longPress.minimumPressDuration = 0.5;
    [self.contentView addGestureRecognizer:longPress];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self resetStreamingViews];
    for (UIView *view in [self.bodyStack.arrangedSubviews copy]) {
        [self.bodyStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    self.rawCopyText = nil;
    self.message = nil;
    self.deferredBlocks = nil;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (self.streamingTextView) {
        CGFloat width = self.bubbleView.bounds.size.width - 2 * kCAMessageCellBubbleInset;
        if (width > 0) [self.streamingTextView setMeasuredWidth:@(width)];
    }
}

- (id)preferredLayoutAttributesFittingAttributes:(id)arg1
{
    // UITableViewCell 不是 collection view cell：这里直接回传入参（原包同选择器）。
    return arg1;
}

#pragma mark - 标量访问器（形参与头文件一致：id）

- (bool)renderingStreaming { return _renderingStreaming; }

- (void)setRenderingStreaming:(id)arg1
{
    _renderingStreaming = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (unsigned long long)streamingCommittedLength { return _streamingCommittedLength; }

- (void)setStreamingCommittedLength:(id)arg1
{
    _streamingCommittedLength = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (unsigned long long)deferredBlockIndex { return _deferredBlockIndex; }

- (void)setDeferredBlockIndex:(id)arg1
{
    _deferredBlockIndex = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (unsigned long long)deferredRenderGeneration { return _deferredRenderGeneration; }

- (void)setDeferredRenderGeneration:(id)arg1
{
    _deferredRenderGeneration = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (bool)configuredQueued { return _configuredQueued; }

- (void)setConfiguredQueued:(id)arg1
{
    _configuredQueued = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

#pragma mark - 配置

- (void)configureWithMessage:(id)arg1
{
    [self ensureChatUI];
    CAMessageItem *item = [arg1 isKindOfClass:CAMessageItem.class] ? arg1 : nil;
    self.message = item;
    [self resetStreamingViews];

    for (UIView *view in [self.bodyStack.arrangedSubviews copy]) {
        [self.bodyStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    CAMessageRole role = (CAMessageRole)(item ? item.role : CAMessageRoleAssistant);
    NSString *text = item.text ?: @"";
    self.rawCopyText = text;

    BOOL userSide = (role == CAMessageRoleUser);
    BOOL notice = (item != nil && item.activityKind == CAMessageActivityKindNotice);
    self.bubbleView.backgroundColor = userSide ? [UIColor colorWithRed:0.06 green:0.45 blue:0.98 alpha:1.0]
                                              : UIColor.secondarySystemBackgroundColor;
    self.leadingConstraint.active = !userSide;
    self.trailingConstraint.active = userSide;
    self.assistantWidthConstraint.active = YES;

    if (item.streaming) {
        CAStreamingTextView *stream = [[CAStreamingTextView alloc] init];
        [stream setTextColor:UIColor.labelColor];
        [self.bodyStack addArrangedSubview:stream];
        self.streamingTextView = stream;
        self.streamingTextLabel = stream;
        _renderingStreaming = true;
        [stream updateStreamingText:text];
    } else if (text.length > 0) {
        NSArray<NSDictionary *> *blocks = nil;
        if ([item.parsedBlocksCache isKindOfClass:NSArray.class]) blocks = item.parsedBlocksCache;
        if (blocks.count == 0) blocks = [self parseMarkdownBlocks:text];
        item.parsedBlocksCache = blocks ?: @[];
        for (NSDictionary *block in blocks) {
            [self appendMarkdownBlock:block toStack:self.bodyStack isUser:@(userSide)];
        }
    } else {
        UILabel *empty = [[UILabel alloc] init];
        empty.numberOfLines = 0;
        empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        empty.textColor = notice ? UIColor.systemOrangeColor : (userSide ? UIColor.whiteColor : UIColor.tertiaryLabelColor);
        empty.text = notice ? @" " : @"（空消息）";
        [self.bodyStack addArrangedSubview:empty];
    }
}

#pragma mark - 流式

- (void)updateStreamingText:(id)arg1
{
    [self ensureChatUI];
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    self.rawCopyText = text;
    _renderingStreaming = true;
    if (!self.streamingTextView) {
        CAStreamingTextView *stream = [[CAStreamingTextView alloc] init];
        [self.bodyStack addArrangedSubview:stream];
        self.streamingTextView = stream;
        self.streamingTextLabel = stream;
    }
    [self.streamingTextView updateStreamingText:text];
    _streamingCommittedLength = (unsigned long long)(text ? text.length : 0);
}

- (void)resetStreamingViews
{
    if (!self.streamingTextView) return;
    [self.streamingTextView finishStreamingReveal];
    [self.bodyStack removeArrangedSubview:self.streamingTextView];
    [self.streamingTextView removeFromSuperview];
    self.streamingTextView = nil;
    self.streamingTextLabel = nil;
    _renderingStreaming = false;
}

- (id)plainStreamingLabel
{
    return self.streamingTextView;
}

#pragma mark - Markdown（文本段落 + ``` 代码块）

- (id)parseMarkdownBlocks:(id)arg1
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    NSMutableArray<NSDictionary *> *blocks = [NSMutableArray array];
    if (text.length == 0) return blocks;

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableString *paragraph = [NSMutableString string];
    NSMutableString *code = nil;
    NSString *codeLanguage = @"";

    for (NSString *line in lines) {
        if ([line hasPrefix:@"```"]) {
            if (code != nil) {
                [blocks addObject:@{ @"type": @"code",
                                     @"text": [code copy] ?: @"",
                                     @"language": codeLanguage ?: @"" }];
                code = nil;
                codeLanguage = @"";
            } else {
                NSString *trimmed = [paragraph stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (trimmed.length > 0) [blocks addObject:@{ @"type": @"text", @"text": trimmed }];
                [paragraph setString:@""];
                code = [NSMutableString string];
                codeLanguage = [line length] > 3 ? [line substringFromIndex:3] : @"";
            }
            continue;
        }
        if (code != nil) {
            if (code.length > 0) [code appendString:@"\n"];
            [code appendString:line];
        } else {
            if (paragraph.length > 0) [paragraph appendString:@"\n"];
            [paragraph appendString:line];
        }
    }
    if (code != nil) {
        [blocks addObject:@{ @"type": @"code", @"text": [code copy] ?: @"", @"language": codeLanguage ?: @"" }];
    }
    NSString *tail = [paragraph stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (tail.length > 0) [blocks addObject:@{ @"type": @"text", @"text": tail }];
    return blocks;
}

- (void)appendMarkdownBlock:(id)arg1 toStack:(id)arg2 isUser:(id)arg3
{
    NSDictionary *block = [arg1 isKindOfClass:NSDictionary.class] ? arg1 : nil;
    UIStackView *stack = [arg2 isKindOfClass:UIStackView.class] ? arg2 : self.bodyStack;
    if (!block || !stack) return;
    BOOL userSide = [arg3 respondsToSelector:@selector(boolValue)] ? [arg3 boolValue] : NO;

    if ([block[@"type"] isEqualToString:@"code"]) {
        CACodeBlockView *codeView = [[CACodeBlockView alloc] init];
        [codeView configureWithCode:block[@"text"] ?: @"" language:block[@"language"] ?: @""];
        [stack addArrangedSubview:codeView];
        return;
    }

    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = userSide ? UIColor.whiteColor : UIColor.labelColor;
    label.textAlignment = userSide ? NSTextAlignmentRight : NSTextAlignmentLeft;
    label.attributedText = [self attributedStringForText:block[@"text"] ?: @"" isUser:@(userSide)];
    [stack addArrangedSubview:label];
}

- (id)attributedStringForText:(id)arg1 isUser:(id)arg2
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    BOOL userSide = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;
    UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIColor *color = userSide ? UIColor.whiteColor : UIColor.labelColor;

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = userSide ? NSTextAlignmentRight : NSTextAlignmentLeft;
    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: color,
                                  NSParagraphStyleAttributeName: paragraph };
    // 行内 `code` 用等宽字体呈现；粗体 / 链接留给后续 parity 迭代。
    NSString *source = text ?: @"";
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:source attributes:attributes];
    NSUInteger cursor = 0;
    while (cursor < source.length) {
        NSRange search = NSMakeRange(cursor, source.length - cursor);
        NSRange open = [source rangeOfString:@"`" options:0 range:search];
        if (open.location == NSNotFound) break;
        NSUInteger afterOpen = open.location + open.length;
        if (afterOpen >= source.length) break;
        NSRange close = [source rangeOfString:@"`" options:0 range:NSMakeRange(afterOpen, source.length - afterOpen)];
        if (close.location == NSNotFound) break;
        NSRange codeRange = NSMakeRange(open.location, close.location - open.location + close.length);
        [attributed addAttribute:NSFontAttributeName
                           value:[UIFont monospacedSystemFontOfSize:font.pointSize - 0.5 weight:UIFontWeightRegular]
                           range:codeRange];
        cursor = codeRange.location + codeRange.length;
    }
    return attributed;
}

- (id)artifactForMarkdownTarget:(id)arg1
{
    // TODO(parity): 产物引用解析（非聊天主流程必需）
    return nil;
}

- (id)markdownImageFallbackForBlock:(id)arg1
{
    // TODO(parity): 图片块占位渲染（非聊天主流程必需）
    return nil;
}

- (NSString *)rawCopyText
{
    if (_rawCopyText.length > 0) return _rawCopyText;
    return self.message.text ?: @"";
}

#pragma mark - 交互

- (void)handleLongPressCopy:(UIGestureRecognizer *)recognizer
{
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    NSString *text = [self rawCopyText];
    if (text.length == 0) return;
    UIPasteboard.generalPasteboard.string = text;
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];

    UIWindow *window = self.window;
    if (!window) return;
    UILabel *toast = [[UILabel alloc] init];
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.text = @"已复制";
    toast.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    toast.textColor = UIColor.whiteColor;
    toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10.0;
    toast.layer.masksToBounds = YES;
    [window addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-80.0],
        [toast.widthAnchor constraintEqualToConstant:72.0],
        [toast.heightAnchor constraintEqualToConstant:28.0],
    ]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

- (void)handleSteerQueuedButton
{
    // TODO(parity): 队列消息的引导发送（非聊天主流程必需）
}

- (void)loadThumbnailAtPath:(id)arg1 pixelSize:(id)arg2 intoButton:(id)arg3
{
    // TODO(parity): 附件缩略图（非聊天主流程必需）
}

- (void)preparseMarkdownForMessage:(id)arg1 completion:(id)arg2
{
    void (^completion)(void) = [arg2 isKindOfClass:NSClassFromString(@"NSBlock")] ? arg2 : nil;
    id blocks = [self parseMarkdownBlocks:arg1];
    if ([arg1 isKindOfClass:CAMessageItem.class]) ((CAMessageItem *)arg1).parsedBlocksCache = blocks;
    if (completion) completion();
}

- (void)prewarmRichPreviewsForMessage:(id)arg1 completion:(id)arg2
{
    void (^completion)(void) = [arg2 isKindOfClass:NSClassFromString(@"NSBlock")] ? arg2 : nil;
    if (completion) completion();
}

#pragma mark - 延迟渲染 / 上下文菜单（原包选择器保留）

- (void)renderDeferredMarkdownBatchForGeneration:(id)arg1 isUser:(id)arg2
{
    // TODO(parity): 分批渲染（当前消息量下不需要）
}

- (void)commitPreparedBodyStack
{
    // TODO(parity): 双栈提交（当前消息量下不需要）
}

- (id)contextMenuInteraction:(id)arg1 configurationForMenuAtLocation:(id)arg2
{
    // 上下文菜单改由长按手势实现（见 handleLongPressCopy:）
    return nil;
}

- (id)messageContextMenu
{
    return nil;
}

- (id)queuedGuideViewWithTheme:(id)arg1
{
    return nil;
}

- (id)attachmentGridForMessage:(id)arg1
{
    return nil;
}

@end
