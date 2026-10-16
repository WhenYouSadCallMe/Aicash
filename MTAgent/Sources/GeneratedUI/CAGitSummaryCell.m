//
//  CAGitSummaryCell.m — 仓库摘要卡（Git 面板第一个分区）
//
//  版式对齐截图 06/07：
//    蓝色文件夹图标井 + 仓库名（17pt semibold）+ 副标题（13pt 灰，「未设置上游 · 尚无提交」）
//    → 两个胶囊：分支（浅蓝底，「master」）+ 远程（灰底，「添加远程」）
//    → 三个并排按钮：获取 / 拉取 / 推送（无远程时整组置灰）
//    → 底部提示文案（灰，可换行）
//
//  原包 ivar：_card / _iconTile / _iconView / _titleLabel / _detailLabel /
//            _branchPill / _remotePill / _fetchButton / _pullButton / _pushButton / _hintLabel / _spinner
//

#import "CAGitSummaryCell.h"
#import "CAGitPill.h"
#import "CAGitSummaryModel.h"

@interface CAGitSummaryCell ()
{
    UIView *_card;
    UIView *_iconTile;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_detailLabel;
    CAGitPill *_branchPill;
    CAGitPill *_remotePill;
    UIButton *_fetchButton;
    UIButton *_pullButton;
    UIButton *_pushButton;
    UILabel *_hintLabel;
    UIActivityIndicatorView *_spinner;
    id _onBranch;
    id _onRemote;
    id _onFetch;
    id _onPull;
    id _onPush;
}
@end

@implementation CAGitSummaryCell

- (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2
{
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if ([arg1 isKindOfClass:NSNumber.class]) {
        style = (UITableViewCellStyle)[(NSNumber *)arg1 integerValue];
    }
    if ((self = [super initWithStyle:style reuseIdentifier:(NSString *)arg2])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.systemGroupedBackgroundColor;
        self.contentView.backgroundColor = UIColor.systemGroupedBackgroundColor;

        _card = [[UIView alloc] init];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        _card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        _card.layer.cornerRadius = 10.0;
        _card.layer.cornerCurve = kCACornerCurveContinuous;

        _iconTile = [[UIView alloc] init];
        _iconTile.translatesAutoresizingMaskIntoConstraints = NO;
        _iconTile.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.12];
        _iconTile.layer.cornerRadius = 9.0;
        _iconTile.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder.fill"]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = UIColor.systemBlueColor;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconTile addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [UIFont systemFontOfSize:13.0];
        _detailLabel.textColor = UIColor.secondaryLabelColor;
        _detailLabel.numberOfLines = 2;

        _branchPill = [[CAGitPill alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
        _branchPill.translatesAutoresizingMaskIntoConstraints = NO;
        [_branchPill addTarget:self action:@selector(branchTapped) forControlEvents:UIControlEventTouchUpInside];

        _remotePill = [[CAGitPill alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
        _remotePill.translatesAutoresizingMaskIntoConstraints = NO;
        [_remotePill addTarget:self action:@selector(remoteTapped) forControlEvents:UIControlEventTouchUpInside];

        _fetchButton = [self ca_actionButtonWithTitle:@"获取" symbol:@"arrow.clockwise" action:@selector(fetchTapped)];
        _pullButton = [self ca_actionButtonWithTitle:@"拉取" symbol:@"arrow.down" action:@selector(pullTapped)];
        _pushButton = [self ca_actionButtonWithTitle:@"推送" symbol:@"arrow.up" action:@selector(pushTapped)];

        _hintLabel = [[UILabel alloc] init];
        _hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _hintLabel.font = [UIFont systemFontOfSize:13.0];
        _hintLabel.textColor = UIColor.secondaryLabelColor;
        _hintLabel.numberOfLines = 0;

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;

        [self.contentView addSubview:_card];
        for (UIView *subview in @[ _iconTile, _titleLabel, _detailLabel, _branchPill, _remotePill,
                                   _fetchButton, _pullButton, _pushButton, _hintLabel, _spinner ]) {
            [_card addSubview:subview];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0.0],
            [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:0.0],

            [_iconTile.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14.0],
            [_iconTile.topAnchor constraintEqualToAnchor:_card.topAnchor constant:14.0],
            [_iconTile.widthAnchor constraintEqualToConstant:34.0],
            [_iconTile.heightAnchor constraintEqualToConstant:34.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconTile.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconTile.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18.0],
            [_iconView.heightAnchor constraintEqualToConstant:18.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor constant:10.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconTile.topAnchor constant:1.0],

            [_spinner.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14.0],
            [_spinner.centerYAnchor constraintEqualToAnchor:_iconTile.centerYAnchor],

            [_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_spinner.leadingAnchor constant:-8.0],
            [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],

            [_branchPill.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14.0],
            [_branchPill.topAnchor constraintEqualToAnchor:_iconTile.bottomAnchor constant:12.0],
            [_branchPill.heightAnchor constraintEqualToConstant:28.0],

            [_remotePill.leadingAnchor constraintEqualToAnchor:_branchPill.trailingAnchor constant:8.0],
            [_remotePill.centerYAnchor constraintEqualToAnchor:_branchPill.centerYAnchor],
            [_remotePill.heightAnchor constraintEqualToConstant:28.0],
            [_remotePill.trailingAnchor constraintLessThanOrEqualToAnchor:_card.trailingAnchor constant:-14.0],
        ]];

        // 三个并排按钮：等宽、等高、间距 8
        NSArray<UIButton *> *buttons = @[ _fetchButton, _pullButton, _pushButton ];
        for (UIButton *button in buttons) {
            [NSLayoutConstraint activateConstraints:@[
                [button.topAnchor constraintEqualToAnchor:_branchPill.bottomAnchor constant:12.0],
                [button.heightAnchor constraintEqualToConstant:36.0],
            ]];
        }
        [NSLayoutConstraint activateConstraints:@[
            [_fetchButton.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14.0],
            [_pullButton.leadingAnchor constraintEqualToAnchor:_fetchButton.trailingAnchor constant:8.0],
            [_pushButton.leadingAnchor constraintEqualToAnchor:_pullButton.trailingAnchor constant:8.0],
            [_pushButton.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14.0],
            [_pullButton.widthAnchor constraintEqualToAnchor:_fetchButton.widthAnchor],
            [_pushButton.widthAnchor constraintEqualToAnchor:_fetchButton.widthAnchor],

            [_hintLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14.0],
            [_hintLabel.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14.0],
            [_hintLabel.topAnchor constraintEqualToAnchor:_fetchButton.bottomAnchor constant:10.0],
            [_hintLabel.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)applyModel:(id)arg1
{
    CAGitSummaryModel *model = [arg1 isKindOfClass:CAGitSummaryModel.class] ? (CAGitSummaryModel *)arg1 : nil;

    _titleLabel.text = model.title;
    _detailLabel.text = model.detail;
    _iconView.tintColor = UIColor.systemBlueColor;

    [_branchPill configureWithTitle:model.branchTitle symbol:@"arrow.triangle.branch" emphasized:@YES showsChevron:@YES];
    [_branchPill setEnabled:@(model.branchEnabled)];

    NSString *remoteTitle = model.remoteConfigured ? model.remoteTitle : @"添加远程";
    NSString *remoteSymbol = model.remoteConfigured ? @"cloud.fill" : @"plus";
    [_remotePill configureWithTitle:remoteTitle symbol:remoteSymbol emphasized:@(model.remoteConfigured) showsChevron:@YES];
    [_remotePill setEnabled:@(model.remoteEnabled)];

    [_fetchButton setEnabled:model.fetchEnabled];
    [_pullButton setEnabled:model.pullEnabled];
    [_pushButton setEnabled:model.pushEnabled];
    [self ca_styleButton:_fetchButton enabled:model.fetchEnabled prominent:NO];
    [self ca_styleButton:_pullButton enabled:model.pullEnabled prominent:NO];
    [self ca_styleButton:_pushButton enabled:model.pushEnabled prominent:model.pushProminent];

    _hintLabel.text = model.hint;
    _hintLabel.hidden = (model.hint.length == 0);

    if (model.busy || model.detailIsActivity) {
        [_spinner startAnimating];
        _detailLabel.textColor = UIColor.systemBlueColor;
    } else {
        [_spinner stopAnimating];
        _detailLabel.textColor = UIColor.secondaryLabelColor;
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_spinner stopAnimating];
    _onBranch = nil;
    _onRemote = nil;
    _onFetch = nil;
    _onPull = nil;
    _onPush = nil;
}

#pragma mark - 交互

- (void)branchTapped
{
    void (^handler)(void) = _onBranch;
    if (handler) {
        handler();
    }
}

- (void)remoteTapped
{
    void (^handler)(void) = _onRemote;
    if (handler) {
        handler();
    }
}

- (void)fetchTapped
{
    void (^handler)(void) = _onFetch;
    if (handler) {
        handler();
    }
}

- (void)pullTapped
{
    void (^handler)(void) = _onPull;
    if (handler) {
        handler();
    }
}

- (void)pushTapped
{
    void (^handler)(void) = _onPush;
    if (handler) {
        handler();
    }
}

#pragma mark - 私有

- (UIButton *)ca_actionButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 9.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.imageEdgeInsets = UIEdgeInsetsMake(0.0, -4.0, 0.0, 4.0);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)ca_styleButton:(UIButton *)button enabled:(BOOL)enabled prominent:(BOOL)prominent
{
    if (!enabled) {
        button.backgroundColor = UIColor.tertiarySystemFillColor;
        [button setTitleColor:UIColor.tertiaryLabelColor forState:UIControlStateNormal];
        button.tintColor = UIColor.tertiaryLabelColor;
        return;
    }
    UIColor *tint = prominent ? UIColor.systemBlueColor : UIColor.labelColor;
    button.backgroundColor = prominent ? [UIColor.systemBlueColor colorWithAlphaComponent:0.14]
                                       : UIColor.secondarySystemFillColor;
    [button setTitleColor:tint forState:UIControlStateNormal];
    button.tintColor = tint;
}

#pragma mark - 回调访问器

- (id)onBranch { return _onBranch; }
- (void)setOnBranch:(id)arg1 { _onBranch = arg1; }

- (id)onFetch { return _onFetch; }
- (void)setOnFetch:(id)arg1 { _onFetch = arg1; }

- (id)onPull { return _onPull; }
- (void)setOnPull:(id)arg1 { _onPull = arg1; }

- (id)onPush { return _onPush; }
- (void)setOnPush:(id)arg1 { _onPush = arg1; }

- (id)onRemote { return _onRemote; }
- (void)setOnRemote:(id)arg1 { _onRemote = arg1; }

- (id)branchPill { return _branchPill; }
- (id)remotePill { return _remotePill; }

@end
