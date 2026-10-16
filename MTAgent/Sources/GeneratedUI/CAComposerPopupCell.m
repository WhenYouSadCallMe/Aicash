//
//  CAComposerPopupCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：输入框 “/” 面板的行（图标 + 标题 + 副标题 + 徽标 + 键盘高亮）。
//  注意：-setHighlighted:animated: 在头文件里被占位成 (id, id)，而真实签名是 (BOOL, BOOL)，
//  直接覆写会把 0/1 当指针用（崩溃）。因此这里保留 no-op 覆写，高亮改由 UIControl 的
//  selected/highlighted 状态 + selectionStyle 呈现。
//

#import "CAComposerPopupCell.h"
#import "CAComposerPopupItem.h"

@interface CAComposerPopupCell () {
    bool _keyboardHighlighted;
}

@property (nonatomic, strong) UIView *highlightView;
@property (nonatomic, strong) UIView *iconTile;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@end

@implementation CAComposerPopupCell

- (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2
{
    // 头文件把形参占位成 id（真实签名是 UITableViewCellStyle + NSString），故忽略 arg1。
    NSString *identifier = [arg2 isKindOfClass:NSString.class] ? arg2 : @"CAComposerPopupCell";
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier])) {
        [self setupPopupRow];
    }
    return self;
}

- (id)initWithFrame:(id)arg1
{
    if ((self = [super initWithFrame:CGRectZero])) {
        [self setupPopupRow];
    }
    return self;
}

- (void)ensurePopupRow
{
    if (self.titleLabel) return;
    [self setupPopupRow];
}

- (void)setupPopupRow
{
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _highlightView = [[UIView alloc] init];
    _highlightView.translatesAutoresizingMaskIntoConstraints = NO;
    _highlightView.backgroundColor = UIColor.tertiarySystemFillColor;
    _highlightView.layer.cornerRadius = 8.0;
    _highlightView.layer.masksToBounds = YES;
    _highlightView.hidden = YES;
    [self.contentView addSubview:_highlightView];

    _iconTile = [[UIView alloc] init];
    _iconTile.translatesAutoresizingMaskIntoConstraints = NO;
    _iconTile.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _iconTile.layer.cornerRadius = 7.0;
    _iconTile.layer.masksToBounds = YES;
    [self.contentView addSubview:_iconTile];

    _iconView = [[UIImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = UIColor.secondaryLabelColor;
    [_iconTile addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _titleLabel.textColor = UIColor.labelColor;
    [self.contentView addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    _subtitleLabel.textColor = UIColor.secondaryLabelColor;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_subtitleLabel];

    _badgeLabel = [[UILabel alloc] init];
    _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _badgeLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
    _badgeLabel.textColor = UIColor.secondaryLabelColor;
    _badgeLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_badgeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_highlightView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:1.0],
        [_highlightView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-1.0],
        [_highlightView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6.0],
        [_highlightView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-6.0],

        [_iconTile.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
        [_iconTile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_iconTile.widthAnchor constraintEqualToConstant:30.0],
        [_iconTile.heightAnchor constraintEqualToConstant:30.0],

        [_iconView.centerXAnchor constraintEqualToAnchor:_iconTile.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconTile.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:17.0],
        [_iconView.heightAnchor constraintEqualToConstant:17.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor constant:10.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7.0],

        [_badgeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:6.0],
        [_badgeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        [_badgeLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1.0],
        [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
    ]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
    self.badgeLabel.text = @"";
    _keyboardHighlighted = false;
    self.highlightView.hidden = YES;
}

#pragma mark - 键盘高亮（标量字段：ivar + 与头文件一致访问器）

- (bool)keyboardHighlighted { return _keyboardHighlighted; }

- (void)setKeyboardHighlighted:(id)arg1
{
    _keyboardHighlighted = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
    self.highlightView.hidden = !_keyboardHighlighted;
}

- (void)setHighlighted:(id)arg1 animated:(id)arg2
{
    // 占位签名 (id, id)，真实签名 (BOOL, BOOL)：不触碰入参，避免把 0/1 当指针（见文件头说明）。
}

#pragma mark - 配置

- (void)configureWithItem:(id)arg1
{
    [self ensurePopupRow];
    CAComposerPopupItem *item = [arg1 isKindOfClass:CAComposerPopupItem.class] ? arg1 : nil;
    NSString *title = item.title.length > 0 ? item.title : (item.identifier ?: @"");
    self.titleLabel.text = title;
    self.subtitleLabel.text = item.subtitle ?: @"";
    self.subtitleLabel.hidden = (self.subtitleLabel.text.length == 0);
    self.badgeLabel.text = item.badge ?: @"";
    self.badgeLabel.hidden = (self.badgeLabel.text.length == 0);

    UIImage *image = nil;
    if (item.symbol.length > 0) image = [UIImage systemImageNamed:item.symbol];
    if (!image) image = [UIImage systemImageNamed:@"circle"];
    self.iconView.image = image;
    self.iconView.tintColor = item.tint ?: UIColor.secondaryLabelColor;

    BOOL enabled = item.enabled;
    self.titleLabel.textColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    self.alpha = enabled ? 1.0 : 0.6;
    self.userInteractionEnabled = enabled;
}

@end
