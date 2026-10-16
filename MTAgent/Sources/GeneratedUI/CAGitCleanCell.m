//
//  CAGitCleanCell.m — 空分区占位行（「没有未暂存的更改」这类）
//
//  原包 ivar：_detailLabel / _iconView / _titleLabel / _well。
//  外观：浅灰圆角图标井 + 标题 + 灰色说明，整行不可点（selectionStyle = none）。
//

#import "CAGitCleanCell.h"

@interface CAGitCleanCell ()
{
    UIView *_well;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_detailLabel;
}
@end

@implementation CAGitCleanCell

- (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2
{
    UITableViewCellStyle style = UITableViewCellStyleDefault;
    if ([arg1 isKindOfClass:NSNumber.class]) {
        style = (UITableViewCellStyle)[(NSNumber *)arg1 integerValue];
    }
    if ((self = [super initWithStyle:style reuseIdentifier:(NSString *)arg2])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

        _well = [[UIView alloc] init];
        _well.translatesAutoresizingMaskIntoConstraints = NO;
        _well.backgroundColor = UIColor.tertiarySystemFillColor;
        _well.layer.cornerRadius = 8.0;
        _well.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = UIColor.systemGreenColor;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_well addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        _titleLabel.textColor = UIColor.labelColor;

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [UIFont systemFontOfSize:13.0];
        _detailLabel.textColor = UIColor.secondaryLabelColor;
        _detailLabel.numberOfLines = 2;

        for (UIView *subview in @[ _well, _titleLabel, _detailLabel ]) {
            [self.contentView addSubview:subview];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_well.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_well.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [_well.widthAnchor constraintEqualToConstant:28.0],
            [_well.heightAnchor constraintEqualToConstant:28.0],
            [_well.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_well.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_well.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:14.0],
            [_iconView.heightAnchor constraintEqualToConstant:14.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_well.trailingAnchor constant:12.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],

            [_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
            [_detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(id)arg1 detail:(id)arg2
{
    _titleLabel.text = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    _detailLabel.text = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : @"";
    _detailLabel.hidden = (_detailLabel.text.length == 0);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous
{
    [super traitCollectionDidChange:previous];
    _well.backgroundColor = UIColor.tertiarySystemFillColor;
}

@end
