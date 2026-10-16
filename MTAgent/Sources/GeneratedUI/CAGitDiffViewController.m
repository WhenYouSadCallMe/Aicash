//
//  CAGitDiffViewController.m — 单个文件的 diff 查看页
//
//  版式：
//    导航栏：左「×」关闭、标题 = 文件名、右「分享」（把完整 diff 落盘后分享）
//    头部：状态图标井 + 状态胶囊（未跟踪 / 已修改 / 已暂存）+ 增删统计「+12 −3」
//           + 分段（工作区 / 已暂存）
//    正文：等宽 UITextView，按行着色（+ 绿 / - 红 / @@ 蓝 / 文件头灰）
//    截断或二进制时用 noticeLabel 提示
//

#import "CAGitDiffViewController.h"
#import "CAGitRepository.h"
#import "CAGitDiffResult.h"
#import "CAGitSnapshot.h"
#import "CAGitChipLabel.h"

@interface CAGitDiffViewController ()
{
    NSDictionary *_change;
    CAGitDiffResult *_diff;
    CAGitRepository *_git;
    NSDictionary *_stats;
    UISegmentedControl *_scopeControl;
    UITextView *_textView;
    UILabel *_countsLabel;
    UILabel *_noticeLabel;
    UIView *_tile;
    UIImageView *_symbolView;
    CAGitChipLabel *_statusChip;
    unsigned long long _generation;
    BOOL _prefersStaged;
}
@end

@implementation CAGitDiffViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self ca_buildNavigationItems];
    [self ca_buildViews];
    [self updateHeaderForStaged:@(_prefersStaged)];
    [self loadDiff];
}

#pragma mark - 构建

- (void)ca_buildNavigationItems
{
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(ca_close)];
    close.tintColor = UIColor.tertiaryLabelColor;
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(shareDiff)];
    self.navigationItem.leftBarButtonItem = close;
    self.navigationItem.rightBarButtonItem = share;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (void)ca_buildViews
{
    _tile = [[UIView alloc] init];
    _tile.translatesAutoresizingMaskIntoConstraints = NO;
    _tile.backgroundColor = UIColor.tertiarySystemFillColor;
    _tile.layer.cornerRadius = 9.0;
    _tile.layer.cornerCurve = kCACornerCurveContinuous;

    _symbolView = [[UIImageView alloc] init];
    _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    [_tile addSubview:_symbolView];

    _statusChip = [[CAGitChipLabel alloc] initWithFrame:[NSValue valueWithCGRect:CGRectZero]];
    _statusChip.translatesAutoresizingMaskIntoConstraints = NO;

    _countsLabel = [[UILabel alloc] init];
    _countsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    _countsLabel.textColor = UIColor.secondaryLabelColor;

    _scopeControl = [[UISegmentedControl alloc] initWithItems:@[ @"工作区", @"已暂存" ]];
    _scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
    _scopeControl.selectedSegmentIndex = 0;
    [_scopeControl addTarget:self action:@selector(ca_scopeChanged) forControlEvents:UIControlEventValueChanged];

    _noticeLabel = [[UILabel alloc] init];
    _noticeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _noticeLabel.font = [UIFont systemFontOfSize:13.0];
    _noticeLabel.textColor = UIColor.systemOrangeColor;
    _noticeLabel.numberOfLines = 0;
    _noticeLabel.hidden = YES;

    _textView = [[UITextView alloc] init];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.alwaysBounceVertical = YES;
    _textView.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    _textView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 24.0, 12.0);
    _textView.layer.cornerRadius = 10.0;
    _textView.layer.cornerCurve = kCACornerCurveContinuous;
    _textView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    for (UIView *subview in @[ _tile, _statusChip, _countsLabel, _scopeControl, _noticeLabel, _textView ]) {
        [self.view addSubview:subview];
    }

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_tile.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [_tile.topAnchor constraintEqualToAnchor:guide.topAnchor constant:12.0],
        [_tile.widthAnchor constraintEqualToConstant:30.0],
        [_tile.heightAnchor constraintEqualToConstant:30.0],

        [_symbolView.centerXAnchor constraintEqualToAnchor:_tile.centerXAnchor],
        [_symbolView.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
        [_symbolView.widthAnchor constraintEqualToConstant:16.0],
        [_symbolView.heightAnchor constraintEqualToConstant:16.0],

        [_statusChip.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:10.0],
        [_statusChip.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],
        [_statusChip.heightAnchor constraintGreaterThanOrEqualToConstant:20.0],

        [_countsLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_statusChip.trailingAnchor constant:8.0],
        [_countsLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [_countsLabel.centerYAnchor constraintEqualToAnchor:_tile.centerYAnchor],

        [_scopeControl.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [_scopeControl.topAnchor constraintEqualToAnchor:_tile.bottomAnchor constant:12.0],
        [_scopeControl.widthAnchor constraintGreaterThanOrEqualToConstant:150.0],

        [_noticeLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [_noticeLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [_noticeLabel.topAnchor constraintEqualToAnchor:_tile.bottomAnchor constant:12.0],

        [_textView.topAnchor constraintEqualToAnchor:_scopeControl.bottomAnchor constant:12.0],
        [_textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [_textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [_textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-12.0],
    ]];
}

#pragma mark - 数据

- (void)loadDiff
{
    _generation += 1;
    unsigned long long generation = _generation;
    NSString *path = _change[kCAGitChangePathKey] ?: @"";

    self.title = path.lastPathComponent.length > 0 ? path.lastPathComponent : @"差异";
    _textView.attributedText = [self ca_attributedStringForDiff:@"正在读取差异…"];
    _noticeLabel.hidden = YES;

    __weak typeof(self) weakSelf = self;
    [_git readDiffForChange:_change staged:@(_prefersStaged) completion:^(CAGitDiffResult *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil || generation != self->_generation) {
            return;
        }
        self->_diff = result ?: [[CAGitDiffResult alloc] init];
        if (result == nil || result.preview.length == 0) {
            self->_textView.text = @"（没有可显示的差异）";
            return;
        }
        self->_textView.attributedText = [self ca_attributedStringForDiff:result.preview];
        if (result.truncated) {
            self->_noticeLabel.hidden = NO;
            self->_noticeLabel.text = @"差异过大，仅显示前 400 KB；分享可拿到完整文件。";
        }
        [self ca_updateCounts];
    }];
}

- (void)ca_updateCounts
{
    NSString *path = _change[kCAGitChangePathKey] ?: @"";
    NSDictionary *rowStats = [_stats isKindOfClass:NSDictionary.class] ? _stats[path] : nil;
    if (![rowStats isKindOfClass:NSDictionary.class]) {
        _countsLabel.text = @"";
        return;
    }
    NSInteger add = [rowStats[@"add"] integerValue];
    NSInteger del = [rowStats[@"del"] integerValue];
    _countsLabel.text = [NSString stringWithFormat:@"+%ld −%ld", (long)add, (long)del];
    _countsLabel.textColor = del > add ? UIColor.systemRedColor : UIColor.systemGreenColor;
}

/// 逐行着色：+ 绿 / - 红 / @@ 蓝 / diff --git 等文件头灰
- (NSAttributedString *)ca_attributedStringForDiff:(NSString *)text
{
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] init];
    UIFont *font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    NSDictionary *base = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.labelColor };

    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSDictionary *attributes = base;
        if ([line hasPrefix:@"+++"] || [line hasPrefix:@"---"] || [line hasPrefix:@"diff --git"] ||
            [line hasPrefix:@"index "] || [line hasPrefix:@"new file"] || [line hasPrefix:@"deleted file"]) {
            attributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.secondaryLabelColor };
        } else if ([line hasPrefix:@"@@"]) {
            attributes = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.systemBlueColor };
        } else if ([line hasPrefix:@"+"]) {
            attributes = @{ NSFontAttributeName: font,
                            NSForegroundColorAttributeName: UIColor.systemGreenColor,
                            NSBackgroundColorAttributeName: [UIColor.systemGreenColor colorWithAlphaComponent:0.08] };
        } else if ([line hasPrefix:@"-"]) {
            attributes = @{ NSFontAttributeName: font,
                            NSForegroundColorAttributeName: UIColor.systemRedColor,
                            NSBackgroundColorAttributeName: [UIColor.systemRedColor colorWithAlphaComponent:0.08] };
        }
        [attributed appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:attributes]];
        [attributed appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:base]];
    }
    return attributed;
}

#pragma mark - 头部

- (void)updateHeaderForStaged:(id)arg1
{
    BOOL staged = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO;
    _prefersStaged = staged;

    NSString *label = _change[kCAGitChangeLabelKey] ?: (staged ? @"已暂存" : @"已修改");
    UIColor *tint = _change[kCAGitChangeTintKey] ?: UIColor.systemOrangeColor;
    [_statusChip configureWithText:staged ? @"已暂存" : label color:staged ? UIColor.systemBlueColor : tint];

    NSString *symbol = _change[kCAGitChangeSymbolKey] ?: @"pencil";
    _symbolView.image = [UIImage systemImageNamed:symbol];
    _symbolView.tintColor = _symbolView.image ? (staged ? UIColor.systemBlueColor : tint) : UIColor.systemGrayColor;

    if (_scopeControl.numberOfSegments > 1) {
        _scopeControl.selectedSegmentIndex = staged ? 1 : 0;
        [_scopeControl setEnabled:![_change[kCAGitChangeUntrackedKey] boolValue] forSegmentAtIndex:1];
    }
    [self ca_updateCounts];
}

#pragma mark - 动作

- (void)ca_scopeChanged
{
    BOOL staged = (_scopeControl.selectedSegmentIndex == 1);
    if (staged == _prefersStaged) {
        return;
    }
    [self updateHeaderForStaged:@(staged)];
    [self loadDiff];
}

- (void)copyDiff
{
    UIPasteboard.generalPasteboard.string = _textView.text ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                  message:@"差异内容已复制到剪贴板。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shareDiff
{
    NSMutableArray *items = [NSMutableArray array];
    if (_diff.fileURL) {
        [items addObject:_diff.fileURL];
    } else if (_textView.text.length > 0) {
        [items addObject:_textView.text];
    }
    if (items.count == 0) {
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)ca_close
{
    if (self.navigationController.presentingViewController != nil) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - 访问器

- (NSDictionary *)change { return _change; }
- (void)setChange:(id)arg1 { _change = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : @{}; }

- (id)diff { return _diff; }
- (void)setDiff:(id)arg1 { _diff = [arg1 isKindOfClass:CAGitDiffResult.class] ? (CAGitDiffResult *)arg1 : nil; }

- (id)git { return _git; }
- (void)setGit:(id)arg1 { _git = [arg1 isKindOfClass:CAGitRepository.class] ? (CAGitRepository *)arg1 : nil; }

- (NSDictionary *)stats { return _stats; }
- (void)setStats:(id)arg1 { _stats = [arg1 isKindOfClass:NSDictionary.class] ? [(NSDictionary *)arg1 copy] : @{}; }

- (bool)prefersStaged { return _prefersStaged; }
- (void)setPrefersStaged:(id)arg1 { _prefersStaged = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (unsigned long long)generation { return _generation; }
- (void)setGeneration:(id)arg1 { _generation = [(NSNumber *)arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [(NSNumber *)arg1 unsignedLongLongValue] : 0; }

- (UILabel *)countsLabel { return _countsLabel; }
- (void)setCountsLabel:(id)arg1 { _countsLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil; }

- (UILabel *)noticeLabel { return _noticeLabel; }
- (void)setNoticeLabel:(id)arg1 { _noticeLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil; }

- (id)scopeControl { return _scopeControl; }
- (void)setScopeControl:(id)arg1 { _scopeControl = [arg1 isKindOfClass:UISegmentedControl.class] ? (UISegmentedControl *)arg1 : nil; }

- (UITextView *)textView { return _textView; }
- (void)setTextView:(id)arg1 { _textView = [arg1 isKindOfClass:UITextView.class] ? (UITextView *)arg1 : nil; }

- (UIView *)tile { return _tile; }
- (void)setTile:(id)arg1 { _tile = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil; }

- (UIImageView *)symbolView { return _symbolView; }
- (void)setSymbolView:(id)arg1 { _symbolView = [arg1 isKindOfClass:UIImageView.class] ? (UIImageView *)arg1 : nil; }

- (id)statusChip { return _statusChip; }
- (void)setStatusChip:(id)arg1 { _statusChip = [arg1 isKindOfClass:CAGitChipLabel.class] ? (CAGitChipLabel *)arg1 : nil; }

@end
