//
//  CAAgentProfileViewController — Agent 身份面板
//
//  真实视图层级：顶部身份卡片（圆形首字头像 + 名称大字 + 副标题小字）+ 分组表格
//      · 分区 0「身份」：名称输入行（内嵌 nameField，回车即保存）
//      · 分区 1「说明」：只读说明行
//  真实数据来源：CAAgentIdentity（defaults 键 CAAgentDisplayName）/ CACommon 常量
//  交互：左上角 xmark 关闭、右上角 saveItem 保存（草稿与当前名不同才可点）
//
//  说明：头文件把原包选择器生成成了 id 占位参数，这里逐字沿用头文件签名，
//        函数体第一行再强转成真实类型使用，避免 -Wmismatched-parameter-types。
//

#import "CAAgentProfileViewController.h"
#import "CACommon.h"
#import "CAAgentIdentity.h"

static NSString *const kCAAgentProfileValueCellReuseIdentifier = @"CAAgentProfileValueCell";
/// 原包字面量：名称输入行复用标识
static NSString *const kCAAgentProfileNameCellReuseIdentifier = @"AgentNameCell";
/// 身份变更通知（原包字面量，与 CAAgentIdentity 一致）
static NSString *const kCAAgentProfileIdentityDidChangeNotification = @"CAAgentIdentityDidChangeNotification";

/// 名称长度约束（与 CAAgentIdentity 保存校验一致）
static const NSUInteger kCAAgentProfileMaxNameLength = 24;

typedef NS_ENUM(NSInteger, CAAgentProfileSection) {
    CAAgentProfileSectionIdentity = 0,
    CAAgentProfileSectionNotes,
    CAAgentProfileSectionCount,
};

typedef NS_ENUM(NSInteger, CAAgentProfileIdentityRow) {
    CAAgentProfileIdentityRowName = 0,
    CAAgentProfileIdentityRowCount,
};

typedef NS_ENUM(NSInteger, CAAgentProfileNotesRow) {
    CAAgentProfileNotesRowUsage = 0,
    CAAgentProfileNotesRowCount,
};

/// 统一使用 UITableViewCellStyleValue1（左侧标题 + 右侧详情）
@interface CAAgentProfileValueCell : UITableViewCell
@end

@implementation CAAgentProfileValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

/// 头文件把原包的 NSInteger 参数生成成了 id：同时兼容「原始整数位」与「NSNumber」两种调用
static NSInteger CAAgentProfileSignedArgument(id argument)
{
    uintptr_t bits = (uintptr_t)(__bridge void *)argument;
    if (bits < 0x1000) return (NSInteger)bits;
    if ([argument isKindOfClass:NSNumber.class]) return [(NSNumber *)argument integerValue];
    if ([argument isKindOfClass:NSString.class]) return [(NSString *)argument integerValue];
    return 0;
}

@interface CAAgentProfileViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
{
    UITableView *_tableView;
    UITextField *_nameField;
    __weak UITableViewCell *_nameFieldCell;
    UILabel *_profileName;
    UILabel *_profileSubtitle;
    UIBarButtonItem *_saveItem;

    UIView *_identityCardView;
    UIView *_avatarView;
    UILabel *_avatarInitial;
}

- (void)handleClose;
- (void)identityDidChange:(NSNotification *)notification;
- (NSString *)savedDisplayName;
- (NSString *)trimmedString:(NSString *)string;
- (void)refreshIdentityCard;
- (void)showMessage:(NSString *)message title:(NSString *)title;

@end

@implementation CAAgentProfileViewController

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Agent 身份";

    _identityCardView = [[UIView alloc] initWithFrame:CGRectZero];
    _identityCardView.translatesAutoresizingMaskIntoConstraints = NO;
    _identityCardView.layer.cornerRadius = 14.0;
    _identityCardView.layer.masksToBounds = YES;

    _avatarView = [[UIView alloc] initWithFrame:CGRectZero];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.layer.cornerRadius = 28.0;
    _avatarView.layer.masksToBounds = YES;

    _avatarInitial = [[UILabel alloc] initWithFrame:CGRectZero];
    _avatarInitial.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarInitial.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    _avatarInitial.textAlignment = NSTextAlignmentCenter;
    [_avatarView addSubview:_avatarInitial];

    _profileName = [[UILabel alloc] initWithFrame:CGRectZero];
    _profileName.translatesAutoresizingMaskIntoConstraints = NO;
    _profileName.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightBold];
    _profileName.adjustsFontSizeToFitWidth = YES;
    _profileName.minimumScaleFactor = 0.6;

    _profileSubtitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _profileSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    _profileSubtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _profileSubtitle.numberOfLines = 2;

    [_identityCardView addSubview:_avatarView];
    [_identityCardView addSubview:_profileName];
    [_identityCardView addSubview:_profileSubtitle];

    UIView *cardContainer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.bounds.size.width, 152.0)];
    cardContainer.backgroundColor = UIColor.clearColor;
    [cardContainer addSubview:_identityCardView];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:_identityCardView.leadingAnchor constant:20.0],
        [_avatarView.centerYAnchor constraintEqualToAnchor:_identityCardView.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:56.0],
        [_avatarView.heightAnchor constraintEqualToConstant:56.0],
        [_avatarInitial.centerXAnchor constraintEqualToAnchor:_avatarView.centerXAnchor],
        [_avatarInitial.centerYAnchor constraintEqualToAnchor:_avatarView.centerYAnchor],
        [_profileName.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:16.0],
        [_profileName.trailingAnchor constraintLessThanOrEqualToAnchor:_identityCardView.trailingAnchor constant:-20.0],
        [_profileName.topAnchor constraintEqualToAnchor:_identityCardView.topAnchor constant:30.0],
        [_profileSubtitle.leadingAnchor constraintEqualToAnchor:_profileName.leadingAnchor],
        [_profileSubtitle.trailingAnchor constraintLessThanOrEqualToAnchor:_identityCardView.trailingAnchor constant:-20.0],
        [_profileSubtitle.topAnchor constraintEqualToAnchor:_profileName.bottomAnchor constant:6.0],
        [_identityCardView.leadingAnchor constraintEqualToAnchor:cardContainer.leadingAnchor constant:20.0],
        [_identityCardView.trailingAnchor constraintEqualToAnchor:cardContainer.trailingAnchor constant:-20.0],
        [_identityCardView.topAnchor constraintEqualToAnchor:cardContainer.topAnchor constant:8.0],
        [_identityCardView.bottomAnchor constraintEqualToAnchor:cardContainer.bottomAnchor constant:-8.0],
    ]];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 52.0;
    _tableView.tableHeaderView = cardContainer;
    [_tableView registerClass:CAAgentProfileValueCell.class forCellReuseIdentifier:kCAAgentProfileValueCellReuseIdentifier];
    [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kCAAgentProfileNameCellReuseIdentifier];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    _nameField = [[UITextField alloc] initWithFrame:CGRectZero];
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    _nameField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _nameField.placeholder = @"例如 MT";
    _nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameField.text = [self savedDisplayName];
    _nameField.delegate = self;
    [_nameField addTarget:self action:@selector(nameDidEdit) forControlEvents:UIControlEventEditingChanged];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(handleClose)];
    _saveItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                style:UIBarButtonItemStyleDone
                                               target:self
                                               action:@selector(saveName)];
    self.navigationItem.rightBarButtonItem = _saveItem;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityDidChange:)
                                                 name:kCAAgentProfileIdentityDidChangeNotification
                                               object:nil];

    [self refreshIdentityCard];
    [self applyTheme];
    [self nameDidEdit];

    CALog(CALogLevelInfo, @"GENERAL", @"agent profile view loaded name=%@", [self savedDisplayName]);
}

#pragma mark - 主题

- (void)applyTheme
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.separatorColor = UIColor.separatorColor;
    _identityCardView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _profileName.textColor = UIColor.labelColor;
    _profileSubtitle.textColor = UIColor.secondaryLabelColor;
    _avatarView.backgroundColor = self.view.tintColor ?: UIColor.systemBlueColor;
    _avatarInitial.textColor = UIColor.whiteColor;
    _nameField.textColor = UIColor.labelColor;
    _nameField.tintColor = self.view.tintColor;
    [_tableView reloadData];
}

#pragma mark - 数据

- (NSString *)trimmedString:(NSString *)string
{
    return [(string ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)savedDisplayName
{
    // 真实来源：CAAgentIdentity 读 defaults 键 CAAgentDisplayName（空值回退 MT）
    id value = [[[CAAgentIdentity alloc] init] displayName];
    NSString *name = [value isKindOfClass:NSString.class] ? (NSString *)value : @"MT";
    return name.length ? name : @"MT";
}

- (id)draftName
{
    NSString *text = [_nameField isKindOfClass:UITextField.class] ? _nameField.text : nil;
    return [self trimmedString:text];
}

- (void)nameDidEdit
{
    NSString *draft = [self trimmedString:[self draftName]];
    NSString *saved = [self savedDisplayName];
    if ([_saveItem isKindOfClass:UIBarButtonItem.class]) {
        _saveItem.enabled = draft.length > 0 && ![draft isEqualToString:saved];
    }
}

- (void)refreshIdentityCard
{
    NSString *name = [self savedDisplayName];
    if ([_profileName isKindOfClass:UILabel.class]) {
        _profileName.text = name;
    }
    if ([_profileSubtitle isKindOfClass:UILabel.class]) {
        _profileSubtitle.text = [NSString stringWithFormat:@"%@ · 运行在本机", CABundleDisplayName];
    }
    if ([_avatarInitial isKindOfClass:UILabel.class]) {
        // 取首个「组合字符」而不是裸 substringToIndex:，避免 emoji / 代理对裂开
        NSString *initial = @"M";
        if (name.length > 0) {
            NSRange range = [name rangeOfComposedCharacterSequenceAtIndex:0];
            initial = [[name substringWithRange:range] uppercaseString] ?: @"M";
        }
        _avatarInitial.text = initial;
    }
}

#pragma mark - 保存

- (void)saveName
{
    NSString *draft = [self trimmedString:[self draftName]];
    NSString *saved = [self savedDisplayName];

    if (draft.length == 0) {
        [self showMessage:@"名称不能为空" title:@"无法保存"];
        return;
    }
    if (draft.length > kCAAgentProfileMaxNameLength) {
        [self showMessage:[NSString stringWithFormat:@"名称最多 %lu 个字符", (unsigned long)kCAAgentProfileMaxNameLength]
                    title:@"无法保存"];
        return;
    }
    if ([draft isEqualToString:saved]) {
        [self nameDidEdit];
        return;
    }

    // 真实落盘：CAAgentIdentity saveDisplayName:（去首尾空白 + 1..24 校验 + 通知）
    bool ok = [[[CAAgentIdentity alloc] init] saveDisplayName:draft];
    if (!ok) {
        CALog(CALogLevelWarn, @"GENERAL", @"agent profile save failed length=%lu", (unsigned long)draft.length);
        [self showMessage:@"名称保存失败，请检查长度（1–24 个字符）" title:@"保存失败"];
        return;
    }

    _nameField.text = draft;
    [self refreshIdentityCard];
    [self nameDidEdit];
    [_tableView reloadData];
    [self showMessage:[NSString stringWithFormat:@"身份已更新为「%@」", draft] title:@"已保存"];
}

#pragma mark - 交互

- (void)handleClose
{
    [_nameField resignFirstResponder];
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)identityDidChange:(NSNotification *)notification
{
    // 其他面板改了身份：卡片与输入框同步，草稿未动就不覆盖用户输入
    NSString *name = [self savedDisplayName];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self->_nameField isFirstResponder]) {
            self->_nameField.text = name;
        }
        [self refreshIdentityCard];
        [self nameDidEdit];
        [self->_tableView reloadData];
    });
}

- (void)showMessage:(NSString *)message title:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 属性（头文件声明的 getter/setter，逐字沿用签名）

- (UITextField *)nameField
{
    return _nameField;
}

- (void)setNameField:(id)arg1
{
    _nameField = [arg1 isKindOfClass:UITextField.class] ? (UITextField *)arg1 : nil;
}

- (UITableViewCell *)nameFieldCell
{
    return _nameFieldCell;
}

- (void)setNameFieldCell:(id)arg1
{
    _nameFieldCell = [arg1 isKindOfClass:UITableViewCell.class] ? (UITableViewCell *)arg1 : nil;
}

- (UILabel *)profileName
{
    return _profileName;
}

- (void)setProfileName:(id)arg1
{
    UILabel *label = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
    _profileName = label;
}

- (UILabel *)profileSubtitle
{
    return _profileSubtitle;
}

- (void)setProfileSubtitle:(id)arg1
{
    UILabel *label = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
    _profileSubtitle = label;
}

- (id)saveItem
{
    return _saveItem;
}

- (void)setSaveItem:(id)arg1
{
    _saveItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil;
}

#pragma mark - UITableViewDataSource

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)CAAgentProfileSectionCount;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = CAAgentProfileSignedArgument(arg2);

    switch ((CAAgentProfileSection)section) {
        case CAAgentProfileSectionIdentity:
            return (signed long long)CAAgentProfileIdentityRowCount;
        case CAAgentProfileSectionNotes:
            return (signed long long)CAAgentProfileNotesRowCount;
        default:
            return 0;
    }
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;

    if (!tableView) {
        return [[CAAgentProfileValueCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    }
    if (!indexPath) {
        return [[CAAgentProfileValueCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    }

    if ((CAAgentProfileSection)indexPath.section == CAAgentProfileSectionIdentity) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAAgentProfileNameCellReuseIdentifier
                                                               forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.text = @"名称";
        cell.detailTextLabel.text = @"";
        if ([_nameField isKindOfClass:UITextField.class]) {
            if (_nameField.superview != cell.contentView) {
                [_nameField removeFromSuperview];
                [cell.contentView addSubview:_nameField];
                // 上下留白 + 输入框自身高度即可撑出行高（自适应行高不下塌）
                [NSLayoutConstraint activateConstraints:@[
                    [_nameField.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor constant:52.0],
                    [_nameField.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                    [_nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],
                    [_nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
                ]];
            }
        }
        self.nameFieldCell = cell;
        return cell;
    }

    CAAgentProfileValueCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAAgentProfileValueCellReuseIdentifier
                                                                  forIndexPath:indexPath];
    cell.textLabel.text = @"";
    cell.detailTextLabel.text = @"";
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if ((CAAgentProfileSection)indexPath.section == CAAgentProfileSectionNotes) {
        switch ((CAAgentProfileNotesRow)indexPath.row) {
            case CAAgentProfileNotesRowUsage:
                cell.textLabel.text = @"身份用途";
                cell.detailTextLabel.text = @"会话标题、子代理徽章等处";
                cell.imageView.image = [UIImage systemImageNamed:@"sparkles"];
                cell.imageView.tintColor = UIColor.secondaryLabelColor;
                break;
            default:
                break;
        }
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    NSInteger section = CAAgentProfileSignedArgument(arg2);

    switch ((CAAgentProfileSection)section) {
        case CAAgentProfileSectionIdentity:
            return @"身份";
        case CAAgentProfileSectionNotes:
            return @"说明";
        default:
            return @"";
    }
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = CAAgentProfileSignedArgument(arg2);

    switch ((CAAgentProfileSection)section) {
        case CAAgentProfileSectionIdentity:
            return @"名称写入本机设置，修改后立即生效。";
        case CAAgentProfileSectionNotes:
            return @"身份会出现在会话标题、子代理徽章等处；去首尾空白后需为 1–24 个字符。";
        default:
            return @"";
    }
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    NSInteger section = CAAgentProfileSignedArgument(arg2);
    return (CAAgentProfileSection)section == CAAgentProfileSectionNotes ? 46.0 : UITableViewAutomaticDimension;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return;

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ((CAAgentProfileSection)indexPath.section == CAAgentProfileSectionIdentity) {
        [_nameField becomeFirstResponder];
        return;
    }
    if ((CAAgentProfileSection)indexPath.section == CAAgentProfileSectionNotes) {
        [self showMessage:[NSString stringWithFormat:@"当前身份：%@\n\n该名称会出现在会话标题、子代理徽章等处，修改后立即生效。",
                           [self savedDisplayName]]
                    title:@"Agent 身份"];
    }
}

#pragma mark - UITextFieldDelegate

- (bool)textFieldShouldReturn:(id)arg1
{
    UITextField *field = [arg1 isKindOfClass:UITextField.class] ? (UITextField *)arg1 : nil;
    [field resignFirstResponder];
    [self saveName];
    return YES;
}

@end
