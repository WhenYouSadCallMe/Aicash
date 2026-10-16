//
//  CAConversationCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：会话侧栏的行（标题 / 时间与模型副标题 / 活跃指示条）。
//

#import "CAConversationCell.h"
#import "CAConversationStore.h"

@interface CAConversationCell ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *activeBar;
@property (nonatomic, strong) UIImageView *conversationIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation CAConversationCell

- (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2
{
    // 头文件把形参占位成 id（真实签名是 UITableViewCellStyle + NSString），故忽略 arg1。
    NSString *identifier = [arg2 isKindOfClass:NSString.class] ? arg2 : @"CAConversationCell";
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier])) {
        [self setupConversationRow];
    }
    return self;
}

- (void)ensureConversationRow
{
    if (self.titleLabel) return;
    [self setupConversationRow];
}

- (void)setupConversationRow
{
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _surfaceView = [[UIView alloc] init];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    _surfaceView.layer.cornerRadius = 10.0;
    _surfaceView.layer.masksToBounds = YES;
    [self.contentView addSubview:_surfaceView];

    _activeBar = [[UIView alloc] init];
    _activeBar.translatesAutoresizingMaskIntoConstraints = NO;
    _activeBar.backgroundColor = [UIColor colorWithRed:0.06 green:0.45 blue:0.98 alpha:1.0];
    _activeBar.layer.cornerRadius = 2.0;
    _activeBar.layer.masksToBounds = YES;
    _activeBar.hidden = YES;
    [self.contentView addSubview:_activeBar];

    _conversationIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bubble.left"]];
    _conversationIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _conversationIcon.tintColor = UIColor.secondaryLabelColor;
    _conversationIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.contentView addSubview:_conversationIcon];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    _subtitleLabel.textColor = UIColor.secondaryLabelColor;
    _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2.0],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2.0],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10.0],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],

        [_activeBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4.0],
        [_activeBar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_activeBar.widthAnchor constraintEqualToConstant:3.0],
        [_activeBar.heightAnchor constraintEqualToConstant:26.0],

        [_conversationIcon.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:10.0],
        [_conversationIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_conversationIcon.widthAnchor constraintEqualToConstant:15.0],
        [_conversationIcon.heightAnchor constraintEqualToConstant:15.0],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_conversationIcon.trailingAnchor constant:8.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-10.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:7.0],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1.0],
        [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-7.0],
    ]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
    self.activeBar.hidden = YES;
}

#pragma mark - 配置

- (void)configureWithRecord:(id)arg1 active:(id)arg2 running:(id)arg3
{
    [self ensureConversationRow];
    CAConversationRecord *record = [arg1 isKindOfClass:CAConversationRecord.class] ? arg1 : nil;
    BOOL isActive = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;
    BOOL isRunning = [arg3 respondsToSelector:@selector(boolValue)] ? [arg3 boolValue] : NO;

    NSString *title = record.title.length > 0 ? record.title : @"新会话";
    self.titleLabel.text = title;
    self.titleLabel.textColor = isActive ? UIColor.labelColor : UIColor.secondaryLabelColor;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (isRunning) [parts addObject:@"运行中"];
    if (record.updatedAt) [parts addObject:[self relativeTimeTextForDate:record.updatedAt]];
    if (record.modelSlug.length > 0) [parts addObject:record.modelSlug];
    [parts addObject:[NSString stringWithFormat:@"%lu 条消息", (unsigned long)record.messages.count]];
    self.subtitleLabel.text = [parts componentsJoinedByString:@" · "];

    self.activeBar.hidden = !isActive;
    self.surfaceView.backgroundColor = isActive ? UIColor.secondarySystemBackgroundColor : UIColor.tertiarySystemBackgroundColor;
    self.conversationIcon.tintColor = isRunning ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    self.conversationIcon.image = [UIImage systemImageNamed:isRunning ? @"ellipsis.bubble" : @"bubble.left"];
}

- (NSString *)relativeTimeTextForDate:(NSDate *)date
{
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:date];
    if (interval < 60) return @"刚刚";
    if (interval < 3600) return [NSString stringWithFormat:@"%.0f 分钟前", floor(interval / 60.0)];
    if (interval < 86400) return [NSString stringWithFormat:@"%.0f 小时前", floor(interval / 3600.0)];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

@end
