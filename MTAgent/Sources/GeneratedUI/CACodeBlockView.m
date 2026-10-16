//
//  CACodeBlockView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：助手消息里的 ``` 代码块渲染（语言标签 + 等宽正文 + 复制按钮）。
//  由 CAMessageCell 在解析 markdown 代码围栏后创建并加入正文栈。
//

#import "CACodeBlockView.h"

@interface CACodeBlockView ()
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *langLabel;
@property (nonatomic, strong) UIButton *actionCopyButton;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, copy) NSString *codeText;
@property (nonatomic, copy) NSString *language;
@end

@implementation CACodeBlockView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.layer.cornerRadius = 8.0;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = UIColor.separatorColor.CGColor;

        _headerView = [[UIView alloc] init];
        _headerView.translatesAutoresizingMaskIntoConstraints = NO;
        _headerView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
        [self addSubview:_headerView];

        _langLabel = [[UILabel alloc] init];
        _langLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _langLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
        _langLabel.textColor = UIColor.secondaryLabelColor;
        _langLabel.text = @"code";
        [_headerView addSubview:_langLabel];

        _actionCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_actionCopyButton setTitle:@"复制" forState:UIControlStateNormal];
        _actionCopyButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        [_actionCopyButton addTarget:self action:@selector(handleCopy) forControlEvents:UIControlEventTouchUpInside];
        [_headerView addSubview:_actionCopyButton];

        _codeLabel = [[UILabel alloc] init];
        _codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _codeLabel.numberOfLines = 0;
        _codeLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
        _codeLabel.textColor = UIColor.labelColor;
        _codeLabel.lineBreakMode = NSLineBreakByCharWrapping;
        [self addSubview:_codeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_headerView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_headerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_headerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_headerView.heightAnchor constraintEqualToConstant:28.0],

            [_langLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:10.0],
            [_langLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

            [_actionCopyButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-10.0],
            [_actionCopyButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

            [_codeLabel.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor constant:8.0],
            [_codeLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10.0],
            [_codeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
            [_codeLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8.0],
        ]];
    }
    return self;
}

- (void)configureWithCode:(id)arg1 language:(id)arg2
{
    self.codeText = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    NSString *language = [arg2 isKindOfClass:NSString.class] ? arg2 : @"";
    self.language = language.length > 0 ? language : @"code";
    self.langLabel.text = self.language;
    self.codeLabel.text = self.codeText;
    self.actionCopyButton.hidden = self.codeText.length == 0;
}

- (void)handleCopy
{
    if (self.codeText.length == 0) return;
    UIPasteboard.generalPasteboard.string = self.codeText;
}

@end
