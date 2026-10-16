//
//  CATextDetailViewController.m — 文本详情：查看 / 复制 / 分享（真实界面实现）
//
//  initWithTitle:text:      —— 只读查看（等宽、可选中）
//  initForTextSelection:    —— 启动即聚焦并全选，方便用户圈选
//  底部工具条：复制（UIPasteboard） / 分享（UIActivityViewController）
//
//  头文件的选择器参数类型统一是占位 id；实现逐字沿用该签名，函数体第一行局部强转后使用。
//

#import "CATextDetailViewController.h"
#import "CALogger.h"

#pragma mark - 文件内工具（静态函数：不为面板新增选择器）

/// 统一关闭入口：已 push 则 pop，模态则 dismiss
static void CATextDetailDismiss(UIViewController *controller)
{
    if (!controller) return;
    UINavigationController *navigation = controller.navigationController;
    if (navigation && navigation.viewControllers.count > 1) {
        [navigation popViewControllerAnimated:YES];
    } else if (controller.presentingViewController) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
}

/// 轻提示（贴在工具条上方，1.5s 后自动消失）
static void CATextDetailToast(UIView *hostView, NSString *message)
{
    if (!hostView || message.length == 0) return;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    container.layer.cornerRadius = 12.0;
    container.layer.masksToBounds = YES;
    [hostView addSubview:container];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
        [container.bottomAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.bottomAnchor constant:-96.0],
        [container.widthAnchor constraintLessThanOrEqualToAnchor:hostView.widthAnchor constant:-56.0],

        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14.0],
    ]];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [container removeFromSuperview];
    });
}

#pragma mark - 面板

@interface CATextDetailViewController ()
{
    id _shareItem;              // 当前分享载荷（文本）
    NSString *_text;            // 面板正文
    BOOL _textSelectionMode;    // YES：启动即聚焦并全选
    UITextView *_textView;

    NSString *_displayTitle;
    UIView *_card;
    UIView *_toolBar;
    UIButton *_copyButton;
    UIButton *_shareButton;
}

@end

@implementation CATextDetailViewController

#pragma mark - 访问器（头文件里声明的选择器）

- (void)close
{
    CATextDetailDismiss(self);
}

- (void)handleCopyText
{
    NSString *text = self.text ?: @"";
    if (text.length == 0) {
        CATextDetailToast(self.view, @"没有可复制的内容");
        return;
    }

    [UIPasteboard generalPasteboard].string = text;
    CATextDetailToast(self.view, [NSString stringWithFormat:@"已复制 %lu 字", (unsigned long)text.length]);
    CALog(CALogLevelDebug, @"GENERAL", @"text detail copied length=%lu", (unsigned long)text.length);
}

- (void)handleShareText
{
    NSString *text = self.text ?: @"";
    if (text.length == 0) {
        CATextDetailToast(self.view, @"没有可分享的内容");
        return;
    }

    // shareItem 保存当前分享载荷，供调用方或二次分享复用
    _shareItem = text;

    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ text ]
                                                                          applicationActivities:nil];
    UIPopoverPresentationController *popover = activity.popoverPresentationController;
    if (popover) {
        popover.sourceView = _toolBar ?: self.view;
        popover.sourceRect = _shareButton ? _shareButton.frame : (CGRect){ CGPointZero, CGSizeMake(1.0, 1.0) };
        popover.permittedArrowDirections = UIPopoverArrowDirectionDown;
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (id)initForTextSelection:(id)arg1
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    if ((self = [self initWithTitle:@"选择文本" text:text])) {
        _textSelectionMode = YES;
    }
    return self;
}

- (id)initWithTitle:(id)arg1 text:(id)arg2
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _displayTitle = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"文本";
        if ([arg2 isKindOfClass:NSString.class]) {
            _text = [(NSString *)arg2 copy];
        } else if ([arg2 isKindOfClass:NSArray.class]) {
            _text = [[(NSArray *)arg2 componentsJoinedByString:@"\n"] copy];
        } else {
            _text = arg2 ? [[arg2 description] copy] : @"";
        }
        _shareItem = _text;
        _textSelectionMode = NO;
    }
    return self;
}

- (void)setShareItem:(id)arg1
{
    if ([arg1 isKindOfClass:NSString.class]) {
        _shareItem = [(NSString *)arg1 copy];
    } else {
        _shareItem = arg1;
    }
}

- (void)setText:(id)arg1
{
    if ([arg1 isKindOfClass:NSString.class]) {
        _text = [(NSString *)arg1 copy];
    } else if ([arg1 isKindOfClass:NSArray.class]) {
        _text = [[(NSArray *)arg1 componentsJoinedByString:@"\n"] copy];
    } else {
        _text = arg1 ? [[arg1 description] copy] : @"";
    }
    _shareItem = _text;
    if (_textView) {
        _textView.text = self.text;
    }
}

- (void)setTextSelectionMode:(id)arg1
{
    BOOL mode = NO;
    if ([arg1 respondsToSelector:@selector(boolValue)]) {
        mode = [(NSNumber *)arg1 boolValue];
    } else {
        mode = (arg1 != nil);
    }
    _textSelectionMode = mode;
}

- (void)setTextView:(id)arg1
{
    _textView = [arg1 isKindOfClass:UITextView.class] ? (UITextView *)arg1 : nil;
}

- (id)shareItem
{
    return _shareItem;
}

- (NSString *)text
{
    return _text ?: @"";
}

- (bool)textSelectionMode
{
    return _textSelectionMode ? YES : NO;
}

- (UITextView *)textView
{
    return _textView;
}

- (void)themeDidChange
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _toolBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _textView.backgroundColor = UIColor.clearColor;
    _textView.textColor = UIColor.labelColor;
    [_copyButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    [_shareButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = _displayTitle.length > 0 ? _displayTitle : @"文本";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(close)];
    close.accessibilityLabel = @"关闭";
    self.navigationItem.leftBarButtonItem = close;

    _card = [[UIView alloc] initWithFrame:CGRectZero];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _card.layer.cornerRadius = 16.0;
    _card.layer.masksToBounds = YES;
    [self.view addSubview:_card];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.backgroundColor = UIColor.clearColor;
    _textView.font = [UIFont monospacedSystemFontOfSize:13.5 weight:UIFontWeightRegular];
    _textView.textColor = UIColor.labelColor;
    _textView.text = self.text;
    _textView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    _textView.alwaysBounceVertical = YES;
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_card addSubview:_textView];

    _toolBar = [[UIView alloc] initWithFrame:CGRectZero];
    _toolBar.translatesAutoresizingMaskIntoConstraints = NO;
    _toolBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:_toolBar];

    UIView *separator = [[UIView alloc] initWithFrame:CGRectZero];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;
    [_toolBar addSubview:separator];

    UIView *divider = [[UIView alloc] initWithFrame:CGRectZero];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = UIColor.separatorColor;
    [_toolBar addSubview:divider];

    _copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_copyButton setTitle:@"复制" forState:UIControlStateNormal];
    [_copyButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    _copyButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [_copyButton addTarget:self action:@selector(handleCopyText) forControlEvents:UIControlEventTouchUpInside];
    [_toolBar addSubview:_copyButton];

    _shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_shareButton setTitle:@"分享" forState:UIControlStateNormal];
    [_shareButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    _shareButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [_shareButton addTarget:self action:@selector(handleShareText) forControlEvents:UIControlEventTouchUpInside];
    [_toolBar addSubview:_shareButton];

    [NSLayoutConstraint activateConstraints:@[
        [_card.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [_card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_card.bottomAnchor constraintEqualToAnchor:_toolBar.topAnchor constant:-12.0],

        [_textView.topAnchor constraintEqualToAnchor:_card.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],

        [_toolBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_toolBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_toolBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_toolBar.heightAnchor constraintEqualToConstant:52.0],

        [separator.topAnchor constraintEqualToAnchor:_toolBar.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:_toolBar.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:_toolBar.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],

        [divider.centerXAnchor constraintEqualToAnchor:_toolBar.centerXAnchor],
        [divider.topAnchor constraintEqualToAnchor:_toolBar.topAnchor constant:8.0],
        [divider.bottomAnchor constraintEqualToAnchor:_toolBar.bottomAnchor constant:-8.0],
        [divider.widthAnchor constraintEqualToConstant:0.5],

        [_copyButton.topAnchor constraintEqualToAnchor:_toolBar.topAnchor],
        [_copyButton.leadingAnchor constraintEqualToAnchor:_toolBar.leadingAnchor],
        [_copyButton.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor],
        [_copyButton.bottomAnchor constraintEqualToAnchor:_toolBar.bottomAnchor],

        [_shareButton.topAnchor constraintEqualToAnchor:_toolBar.topAnchor],
        [_shareButton.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
        [_shareButton.trailingAnchor constraintEqualToAnchor:_toolBar.trailingAnchor],
        [_shareButton.bottomAnchor constraintEqualToAnchor:_toolBar.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:@"CAThemeDidChangeNotification"
                                               object:nil];

    if (_textSelectionMode) {
        // 启动即聚焦并全选，方便用户直接圈选
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf->_textView becomeFirstResponder];
            [strongSelf->_textView selectAll:nil];
        });
    }

    CALog(CALogLevelDebug, @"GENERAL", @"text detail loaded length=%lu selectionMode=%d",
          (unsigned long)self.text.length, _textSelectionMode ? 1 : 0);
}

@end
