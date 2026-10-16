//
//  CAGitChangeCell.m — 变更列表行
//
//  版式对齐原版截图（06）：行距 60.3pt、行内从左到右依次是
//    空心圆勾选控件 → 绿色（新增）/橙色（修改）/红色（删除）小方块图标 → 文件名（17pt 粗体）
//    → 相对路径副标题（13pt 灰） → 右侧浅绿圆角胶囊「未跟踪」
//

#import "CAGitChangeCell.h"
#import "CAGitChipLabel.h"
#import "CAGitSnapshot.h"

@interface CAGitChangeCell ()
{
    UIButton *_toggleButton;
    UIView *_tile;
    UIImageView *_symbolView;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    CAGitChipLabel *_statusLabel;
    UILabel *_countsLabel;
    NSDictionary *_row;
    BOOL _staged;
    id _onToggle;
}
@end

@implementation CAGitChangeCell

- (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2
{
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if ([arg1 isKindOfClass:NSNumber.class]) {
        style = (UITableViewCellStyle)[(NSNumber *)arg1 integerValue];
    }
    if ((self = [super initWithStyle:style reuseIdentifier:(NSString *)arg2])) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        _toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
        _toggleButton.tintColor = UIColor.tertiaryLabelColor;
        [_toggleButton addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
        [_toggleButton setImage:[UIImage systemImageNamed:@"circle"] forState:UIControlStateNormal];
        _toggleButton.accessibilityLabel = @"暂存开关";

        _tile = [[UIView alloc] init];
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        _tile.layer.cornerRadius = 8.0;
        _tile.layer.cornerCurve = kCACornerCurveContinuous;

        _symbolView = [[UIImageView alloc] init];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeScaleAspectFit;
        [_tile addSubview:_symbolView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _titleLabel.numberOfLines = 1;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:13.0];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _subtitleLabel.numberOfLines = 1;

        _statusLabel = [[CAGitChipLabel alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.hidden = YES;

        _countsLabel = [[UILabel alloc] init];
        _countsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
        _countsLabel.textColor = UIColor.tertiaryLabelColor;

        for (UIView *subview in @[ _toggleButton, _tile, _titleLabel, _subtitleLabel, _statusLabel, _countsLabel ]) {
            [self.contentView addSubview:subview];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_toggleButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_toggleButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggleButton.widthAnchor constraintEqualToConstant:26.0],
            [_toggleButton.heightAnchor constraintEqualToConstant:26.0],

            [_tile.leadingAnchor constraintEqualToAnchor:_toggleButton.trailingAnchor constant:12.0],
            [_tile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_tile.widthAnchor constraintEqualToConstant:28.0],
            [_tile.heightAnchor constraintEqualToConstant:28.0],

            [_symbolView.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
            [_symbolView.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
            [_symbolView.widthAnchor constraintEqualToConstant:15.0],
            [_symbolView.heightAnchor constraintEqualToConstant:15.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-11.0],

            [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8.0],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_statusLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [_countsLabel.trailingAnchor constraintEqualToAnchor:_statusLabel.leadingAnchor constant:-8.0],
            [_countsLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithChange:(id)arg1 side:(id)arg2 stats:(id)arg3 enabled:(id)arg4
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : @{};
    _row = change;
    _staged = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    BOOL enabled = [(NSNumber *)arg4 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg4 boolValue] : YES;

    NSString *path = change[kCAGitChangePathKey] ?: @"";
    _titleLabel.text = path.lastPathComponent.length > 0 ? path.lastPathComponent : path;
    _subtitleLabel.text = change[kCAGitChangeSubtitleKey] ?: @"";

    UIColor *tint = change[kCAGitChangeTintKey] ?: UIColor.systemOrangeColor;
    _tile.backgroundColor = [tint colorWithAlphaComponent:0.16];
    _symbolView.image = [UIImage systemImageNamed:change[kCAGitChangeSymbolKey] ?: @"pencil"];
    _symbolView.tintColor = tint;

    _statusLabel.hidden = NO;
    [_statusLabel configureWithText:change[kCAGitChangeLabelKey] ?: @"已修改" color:tint];

    // 已暂存的行：勾选控件变成实心对勾
    [_toggleButton setImage:[UIImage systemImageNamed:(_staged ? @"checkmark.circle.fill" : @"circle")]
                   forState:UIControlStateNormal];
    _toggleButton.tintColor = _staged ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor;
    _toggleButton.enabled = enabled;

    // 增删行数（git diff --numstat）
    NSDictionary *rowStats = [arg3 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg3 objectForKey:path] : nil;
    if ([rowStats isKindOfClass:NSDictionary.class]) {
        NSInteger add = [rowStats[@"add"] integerValue];
        NSInteger del = [rowStats[@"del"] integerValue];
        _countsLabel.text = (add == 0 && del == 0) ? @"" : [NSString stringWithFormat:@"+%ld −%ld", (long)add, (long)del];
        _countsLabel.textColor = del > add ? UIColor.systemRedColor : UIColor.systemGreenColor;
    } else {
        _countsLabel.text = @"";
    }

    self.alpha = enabled ? 1.0 : 0.5;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    _titleLabel.text = nil;
    _subtitleLabel.text = nil;
    _statusLabel.text = nil;
    _statusLabel.hidden = YES;
    _countsLabel.text = nil;
    _onToggle = nil;
    _row = nil;
    self.alpha = 1.0;
}

- (void)toggleTapped
{
    void (^handler)(NSDictionary *, BOOL) = _onToggle;
    if (handler && _row) {
        handler(_row, _staged);
    }
}

- (id)onToggle { return _onToggle; }
- (void)setOnToggle:(id)arg1 { _onToggle = arg1; }

@end
