//
//  CAUpdateViewController.m — 分阶段安装实现
//    1) 下载：CAManagedRuntimeDownload（→ CAUpdateDownload：GitHub 直连 + gh-proxy 候选）
//    2) 校验：CAUpdateManager cachedPackageAtPath:matchesSHA256:（清单缺失时回退 SHA256SUMS）
//    3) 解包：CAArchiveExtractor（tar.gz / deb）
//    4) 签名：CAUpdateManager signPaths:staging:error:（内部走 Helpers/codex-sign --adhoc-only）
//    5) 安装：写 <runtimeRoot>/manifest.json + 清理下载缓存
//

#import "CAUpdateViewController.h"
#import "CAUpdateDownload.h"
#import "CAManagedRuntimeDownload.h"
#import "CAUpdateManager.h"
#import "CAArchiveExtractor.h"
#import "CARuntimeCatalog.h"
#import "CARuntimePaths.h"
#import "CALogViewerViewController.h"
#import "CACommon.h"
#import "CALogger.h"

/// 阶段行（与 CAUpdateStage 1…5 一一对应）
static NSInteger const kCAUpdateStageRowCount = 5;

#pragma mark - 私有工具

/// 可用的签名 entitlements 模板（优先 runtime，其次 helper，最后 bundle 根目录）
static NSString *CAUpdateResolvedEntitlementsPath(void)
{
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSArray<NSString *> *candidates = @[
        [bundlePath stringByAppendingPathComponent:@"ResignEntitlements/runtime.entitlements.plist"],
        [bundlePath stringByAppendingPathComponent:@"ResignEntitlements/helper.entitlements.plist"],
        [bundlePath stringByAppendingPathComponent:@"runtime.entitlements.plist"],
        [bundlePath stringByAppendingPathComponent:@"helper.entitlements.plist"],
        [bundlePath stringByAppendingPathComponent:@"entitlements.plist"],
    ];
    for (NSString *candidate in candidates) {
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

/// CAUpdateManager -signPaths:staging:error: 固定使用 bundle 内 ResignEntitlements/helper.entitlements.plist；
/// 模板缺失时从可解析到的模板补齐（bundle 不可写时仅记录警告，后续报错仍是可诊断的）
static void CAUpdatePrepareSigningTemplate(void)
{
    NSString *expected = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ResignEntitlements/helper.entitlements.plist"];
    if (!expected.length) return;
    if ([NSFileManager.defaultManager fileExistsAtPath:expected]) return;

    NSString *source = CAUpdateResolvedEntitlementsPath();
    if (!source.length) {
        CALog(CALogLevelWarn, @"RUNTIME", @"signing template missing and no fallback found; expected=%@", expected);
        return;
    }

    NSError *error = nil;
    [CARuntimePaths ensureDirectory:expected.stringByDeletingLastPathComponent mode:0755 error:&error];
    if ([NSFileManager.defaultManager copyItemAtPath:source toPath:expected error:&error]) {
        CALog(CALogLevelInfo, @"RUNTIME", @"signing template materialized path=%@ source=%@", expected, source);
    } else {
        CALog(CALogLevelWarn, @"RUNTIME", @"signing template materialize failed error=%@ source=%@",
              error.localizedDescription ?: @"(unknown)", source);
    }
}

/// 同步取 SHA256SUMS 中该资产的值（仅清单未提供 archive_sha256 时使用）
static NSString *CAUpdateFetchSHA256Synchronously(NSString *asset, NSString *version, NSTimeInterval timeout)
{
    if (!asset.length) return nil;
    __block NSString *sha256 = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [[CAUpdateManager sharedManager] fetchOfficialSHA256ForAsset:asset
                                                        version:version.length ? version : @"latest"
                                                     completion:^(NSString *result, NSError *error) {
        sha256 = result;
        dispatch_semaphore_signal(semaphore);
    }];
    long waited = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(timeout, 5.0) * NSEC_PER_SEC)));
    if (waited != 0) {
        CALog(CALogLevelWarn, @"RUNTIME", @"SHA256SUMS lookup timed out asset=%@", asset);
        return nil;
    }
    return sha256;
}

#pragma mark - 进度页

@interface CAUpdateViewController ()

- (NSString *)runtimeTitleText;
- (NSString *)versionDetailText;
- (void)refreshEnvironmentText:(NSString *)runtimeID;
- (void)handleRetry;
- (void)handleClose;
- (void)handleShowLogs;

@end

@implementation CAUpdateViewController {
    NSString *_runtimeID;
    NSString *_version;
    NSString *_versionLabelText;
    signed long long _activeStage;
    BOOL _finished;
    BOOL _success;
    BOOL _pythonRuntime;
    BOOL _theosRuntime;
    BOOL _reverseToolsRuntime;
    id _completionHandler;
    UIView *_card;
    UILabel *_titleLabel;
    UILabel *_statusLabel;
    UILabel *_detailLabel;
    UILabel *_countLabel;
    UILabel *_versionLabel;
    UILabel *_installLogLabel;
    UIProgressView *_progressBar;
    UIActivityIndicatorView *_spinner;
    UIButton *_closeButton;
    UIButton *_retryButton;
    UIButton *_logsButton;
    NSArray *_stageLabels;
    NSArray *_stageIcons;
}

#pragma mark - 构造

- (instancetype)initWithRuntimeID:(NSString *)runtimeID version:(NSString *)version
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _runtimeID = [runtimeID copy] ?: @"codex";
        _version = [version copy];
        _pythonRuntime = [runtimeID isEqualToString:@"python"];
        _theosRuntime = [runtimeID isEqualToString:@"theos"];
        _reverseToolsRuntime = [runtimeID isEqualToString:@"reverse-tools"];
    }
    return self;
}

- (id)initWithVersion:(NSString *)arg1
{
    return [self initWithRuntimeID:@"codex" version:arg1];
}

- (id)initWithPythonVersion:(NSString *)arg1
{
    return [self initWithRuntimeID:@"python" version:arg1];
}

- (id)initWithReverseToolsVersion:(NSString *)arg1
{
    return [self initWithRuntimeID:@"reverse-tools" version:arg1];
}

- (id)initWithTheosVersion:(NSString *)arg1
{
    return [self initWithRuntimeID:@"theos" version:arg1];
}

- (NSString *)runtimeID
{
    return _runtimeID.length ? _runtimeID : @"codex";
}

#pragma mark - 声明选择器（访问器）

- (signed long long)activeStage { return _activeStage; }

- (void)setActiveStage:(signed long long)arg1 { _activeStage = arg1; }

- (bool)finished { return _finished ? YES : NO; }

- (void)setFinished:(bool)arg1 { _finished = arg1 ? YES : NO; }

- (bool)success { return _success ? YES : NO; }

- (void)setSuccess:(bool)arg1 { _success = arg1 ? YES : NO; }

- (bool)pythonRuntime { return _pythonRuntime ? YES : NO; }

- (void)setPythonRuntime:(bool)arg1 { _pythonRuntime = arg1 ? YES : NO; }

- (bool)theosRuntime { return _theosRuntime ? YES : NO; }

- (void)setTheosRuntime:(bool)arg1 { _theosRuntime = arg1 ? YES : NO; }

- (bool)reverseToolsRuntime { return _reverseToolsRuntime ? YES : NO; }

- (void)setReverseToolsRuntime:(bool)arg1 { _reverseToolsRuntime = arg1 ? YES : NO; }

- (id)completionHandler { return _completionHandler; }

- (void)setCompletionHandler:(id)arg1 { _completionHandler = arg1; }

- (NSString *)version { return _version ?: @""; }

- (void)setVersion:(NSString *)arg1 { _version = [arg1 copy]; }

- (UIView *)card { return _card; }

- (void)setCard:(UIView *)arg1 { _card = arg1; }

- (UILabel *)titleLabel { return _titleLabel; }

- (void)setTitleLabel:(UILabel *)arg1 { _titleLabel = arg1; }

- (UILabel *)statusLabel { return _statusLabel; }

- (void)setStatusLabel:(UILabel *)arg1 { _statusLabel = arg1; }

- (UILabel *)detailLabel { return _detailLabel; }

- (void)setDetailLabel:(UILabel *)arg1 { _detailLabel = arg1; }

- (UILabel *)countLabel { return _countLabel; }

- (void)setCountLabel:(UILabel *)arg1 { _countLabel = arg1; }

- (id)progressBar { return _progressBar; }

- (void)setProgressBar:(UIProgressView *)arg1 { _progressBar = arg1; }

- (id)spinner { return _spinner; }

- (void)setSpinner:(UIActivityIndicatorView *)arg1 { _spinner = arg1; }

- (NSArray *)stageIcons { return _stageIcons; }

- (void)setStageIcons:(id)arg1 { _stageIcons = [arg1 isKindOfClass:NSArray.class] ? arg1 : nil; }

- (NSArray *)stageLabels { return _stageLabels; }

- (void)setStageLabels:(id)arg1 { _stageLabels = [arg1 isKindOfClass:NSArray.class] ? arg1 : nil; }

- (UIButton *)closeButton { return _closeButton; }

- (void)setCloseButton:(UIButton *)arg1 { _closeButton = arg1; }

- (UIButton *)retryButton { return _retryButton; }

- (void)setRetryButton:(UIButton *)arg1 { _retryButton = arg1; }

- (id)labelWithSize:(double)arg1 weight:(double)arg2
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:(CGFloat)arg1 weight:(CGFloat)arg2];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    return label;
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"运行时更新";
    [self applyTheme];

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];
    [self setCard:card];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    UILabel *titleLabel = [self labelWithSize:17.0 weight:UIFontWeightSemibold];
    titleLabel.text = [self runtimeTitleText];
    [self setTitleLabel:titleLabel];
    [stack addArrangedSubview:titleLabel];

    UILabel *versionLabel = [self labelWithSize:13.0 weight:UIFontWeightRegular];
    versionLabel.textColor = UIColor.secondaryLabelColor;
    versionLabel.text = [self versionDetailText];
    _versionLabel = versionLabel;
    [stack addArrangedSubview:versionLabel];

    NSArray<NSString *> *stageTitles = @[ @"下载", @"校验", @"解包", @"签名", @"安装" ];
    NSMutableArray *stageIcons = [NSMutableArray arrayWithCapacity:stageTitles.count];
    NSMutableArray *stageLabels = [NSMutableArray arrayWithCapacity:stageTitles.count];
    for (NSString *stageTitle in stageTitles) {
        UILabel *icon = [self labelWithSize:15.0 weight:UIFontWeightSemibold];
        icon.text = @"○";
        icon.textColor = UIColor.tertiaryLabelColor;
        [icon.widthAnchor constraintEqualToConstant:18.0].active = YES;

        UILabel *label = [self labelWithSize:14.0 weight:UIFontWeightRegular];
        label.text = stageTitle;
        label.textColor = UIColor.secondaryLabelColor;

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, label ]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 8.0;
        [stack addArrangedSubview:row];

        [stageIcons addObject:icon];
        [stageLabels addObject:label];
    }
    [self setStageIcons:stageIcons];
    [self setStageLabels:stageLabels];

    UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.progress = 0.0;
    [self setProgressBar:bar];
    [stack addArrangedSubview:bar];

    UILabel *status = [self labelWithSize:15.0 weight:UIFontWeightMedium];
    status.text = @"准备中…";
    [self setStatusLabel:status];
    [stack addArrangedSubview:status];

    UILabel *detail = [self labelWithSize:12.0 weight:UIFontWeightRegular];
    detail.textColor = UIColor.secondaryLabelColor;
    [self setDetailLabel:detail];
    [stack addArrangedSubview:detail];

    UILabel *count = [self labelWithSize:12.0 weight:UIFontWeightRegular];
    count.textColor = UIColor.secondaryLabelColor;
    [self setCountLabel:count];
    [stack addArrangedSubview:count];

    UILabel *installLog = [self labelWithSize:12.0 weight:UIFontWeightRegular];
    installLog.textColor = UIColor.secondaryLabelColor;
    installLog.text = @"";
    _installLogLabel = installLog;
    [stack addArrangedSubview:installLog];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.hidesWhenStopped = YES;
    [spinner startAnimating];
    [self setSpinner:spinner];

    UIButton *logsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [logsButton setTitle:@"查看日志" forState:UIControlStateNormal];
    [logsButton addTarget:self action:@selector(handleShowLogs) forControlEvents:UIControlEventTouchUpInside];
    _logsButton = logsButton;

    UIButton *retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [retryButton setTitle:@"重试" forState:UIControlStateNormal];
    [retryButton addTarget:self action:@selector(handleRetry) forControlEvents:UIControlEventTouchUpInside];
    retryButton.hidden = YES;
    [self setRetryButton:retryButton];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [self setCloseButton:closeButton];

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[ spinner, logsButton, retryButton, closeButton ]];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.alignment = UIStackViewAlignmentCenter;
    buttons.spacing = 12.0;
    buttons.distribution = UIStackViewDistributionFillProportionally;
    [stack addArrangedSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [card.widthAnchor constraintLessThanOrEqualToConstant:460.0],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0],
    ]];

    CALog(CALogLevelInfo, @"RUNTIME", @"update sheet opened runtime=%@ version=%@", [self runtimeID], [self version]);
    [self startUpdate];
}

- (void)applyTheme
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    if (_card) {
        _card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    }
    _titleLabel.textColor = UIColor.labelColor;
    _statusLabel.textColor = UIColor.labelColor;
    _detailLabel.textColor = UIColor.secondaryLabelColor;
    _countLabel.textColor = UIColor.secondaryLabelColor;
    [self updateStageIcons];
}

- (void)dealloc
{
    CALog(CALogLevelDebug, @"RUNTIME", @"update sheet closed runtime=%@ finished=%d success=%d",
          _runtimeID ?: @"?", _finished, _success);
}

#pragma mark - 文案

- (NSString *)runtimeTitleText
{
    if (_pythonRuntime) return @"安装 Python 运行时";
    if (_theosRuntime) return @"安装 Theos 运行时";
    if (_reverseToolsRuntime) return @"安装逆向工具运行时";
    return @"安装 / 修复 codex 运行时";
}

- (NSString *)versionDetailText
{
    if (_version.length) return [NSString stringWithFormat:@"目标版本 %@", _version];
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:[self runtimeID]];
    NSString *installed = [CAUpdateViewController installedVersionForRuntimeID:[self runtimeID]];
    return [NSString stringWithFormat:@"清单版本 %@ · 本机版本 %@",
            entry.version ?: @"(未知)", installed ?: @"(未安装)"];
}

#pragma mark - 更新流程

- (void)startUpdate
{
    NSString *runtimeID = [self runtimeID];
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];

    [self setFinished:NO];
    [self setSuccess:NO];
    [self setActiveStage:CAUpdateStageDownload];
    _progressBar.progress = 0.0;
    _retryButton.hidden = YES;
    _statusLabel.text = @"准备安装…";
    _detailLabel.text = @"";
    _countLabel.text = @"";
    _installLogLabel.text = @"";
    [_spinner startAnimating];
    [self updateStageIcons];

    if (!entry || !entry.archiveURL.length) {
        [self finishUpdate:NO message:[NSString stringWithFormat:@"运行时清单缺少 %@（请先在设置页刷新运行时清单）", runtimeID]];
        return;
    }

    CALog(CALogLevelInfo, @"RUNTIME", @"install start runtime=%@ version=%@ revision=%ld",
          runtimeID, entry.version ?: @"?", (long)entry.revision);

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = [CAUpdateViewController installRuntimeEntry:entry progress:^(CAUpdateProgress *progress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf renderProgress:progress];
            });
        } error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (ok) {
                NSString *version = [CAUpdateViewController installedVersionForRuntimeID:runtimeID];
                [strongSelf finishUpdate:YES message:[NSString stringWithFormat:@"%@ 安装完成（%@）", runtimeID, version ?: @"已就绪"]];
            } else {
                [strongSelf finishUpdate:NO message:error.localizedDescription ?: @"安装失败"];
            }
        });
    });
}

- (void)restartUpdate
{
    if (_finished && _success) {
        [self closeSheet];
        return;
    }
    [self startUpdate];
}

- (void)renderProgress:(id)arg1
{
    CAUpdateProgress *progress = [arg1 isKindOfClass:CAUpdateProgress.class] ? (CAUpdateProgress *)arg1 : nil;
    if (!progress) return;

    [self setActiveStage:progress.stage];
    double fraction = MAX(0.0, MIN(1.0, progress.fraction));
    [_progressBar setProgress:(float)fraction animated:YES];
    _statusLabel.text = [NSString stringWithFormat:@"%@ · %@", [progress stageTitle], progress.status ?: @""];
    _detailLabel.text = progress.status ?: @"";
    _countLabel.text = [progress byteCountText];
    [self updateStageIcons];

    if (_installLogLabel && progress.status.length) {
        _installLogLabel.text = [NSString stringWithFormat:@"%@", progress.status];
    }
}

- (void)updateStageIcons
{
    NSArray *icons = [self stageIcons];
    NSArray *labels = [self stageLabels];
    signed long long active = [self activeStage];

    for (NSUInteger index = 0; index < icons.count; index++) {
        id element = icons[index];
        if (![element isKindOfClass:UILabel.class]) continue;
        UILabel *icon = (UILabel *)element;
        signed long long stage = (signed long long)(index + 1);

        if (_finished) {
            if (_success) {
                icon.text = @"✓";
                icon.textColor = UIColor.systemGreenColor;
            } else if (stage <= MAX(active, (signed long long)1)) {
                icon.text = stage == MAX(active, (signed long long)1) ? @"✗" : @"✓";
                icon.textColor = stage == MAX(active, (signed long long)1) ? UIColor.systemRedColor : UIColor.systemGreenColor;
            } else {
                icon.text = @"○";
                icon.textColor = UIColor.tertiaryLabelColor;
            }
            continue;
        }

        if (stage < active) {
            icon.text = @"✓";
            icon.textColor = UIColor.systemGreenColor;
        } else if (stage == active) {
            icon.text = @"●";
            icon.textColor = self.view.tintColor;
        } else {
            icon.text = @"○";
            icon.textColor = UIColor.tertiaryLabelColor;
        }
    }

    for (NSUInteger index = 0; index < labels.count; index++) {
        id element = labels[index];
        if (![element isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)element;
        signed long long stage = (signed long long)(index + 1);
        label.textColor = (!_finished && stage == active) ? UIColor.labelColor : UIColor.secondaryLabelColor;
    }
}

- (void)finishUpdate:(bool)arg1 message:(NSString *)arg2
{
    [self setFinished:YES];
    [self setSuccess:arg1];
    [_spinner stopAnimating];

    if (arg1) {
        [self setActiveStage:CAUpdateStageFinished];
        _progressBar.progress = 1.0;
        _statusLabel.text = @"安装完成";
        _detailLabel.text = arg2 ?: @"";
        _installLogLabel.text = [NSString stringWithFormat:@"运行时根目录：%@", [CARuntimePaths runtimeRootForID:[self runtimeID]]];
        _retryButton.hidden = YES;
    } else {
        _statusLabel.text = @"安装失败";
        _detailLabel.text = arg2 ?: @"未知错误";
        _installLogLabel.text = @"可点“查看日志”查看 CALogger 最近记录";
        _retryButton.hidden = NO;
    }
    [self updateStageIcons];

    id stored = [self completionHandler];
    if (stored) {
        CAUpdateFinishHandler handler = (CAUpdateFinishHandler)stored;
        handler((BOOL)arg1, arg2);
    }
    if (self.finishHandler) self.finishHandler((BOOL)arg1, arg2);

    [[NSNotificationCenter defaultCenter] postNotificationName:@"CARuntimeInstallDidFinish"
                                                        object:self
                                                      userInfo:@{ @"runtime": [self runtimeID],
                                                                  @"success": @(arg1 ? YES : NO) }];
}

#pragma mark - 按钮

- (void)handleRetry
{
    [self restartUpdate];
}

- (void)handleClose
{
    [self closeSheet];
}

- (void)handleShowLogs
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CALogViewerViewController alloc] init]];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)closeSheet
{
    UIViewController *presenter = self.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    if (self.navigationController.presentingViewController) {
        [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 环境变更通知（外壳补全：刷新目标版本文案）

- (void)pythonEnvironmentChanged { [self refreshEnvironmentText:@"python"]; }

- (void)theosEnvironmentChanged { [self refreshEnvironmentText:@"theos"]; }

- (void)reverseToolsEnvironmentChanged { [self refreshEnvironmentText:@"reverse-tools"]; }

- (void)refreshEnvironmentText:(NSString *)runtimeID
{
    NSString *installed = [CAUpdateViewController installedVersionForRuntimeID:runtimeID];
    if (_versionLabel) {
        _versionLabel.text = [NSString stringWithFormat:@"%@ 本机版本 %@", runtimeID, installed ?: @"(未安装)"];
    }
    CALog(CALogLevelDebug, @"RUNTIME", @"environment changed runtime=%@ installed=%@", runtimeID, installed ?: @"(none)");
}

#pragma mark - 安装实现（供设置页 / 诊断页复用）

+ (BOOL)installRuntimeEntry:(CARuntimeCatalogEntry *)entry
                   progress:(void (^)(CAUpdateProgress *))progress
                      error:(NSError **)error
{
    if (!entry.runtimeID.length || !entry.archiveURL.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"CodexApp.Runtime" code:400
                                     userInfo:@{ NSLocalizedDescriptionKey: @"运行时清单条目缺少 runtime_id / archive_url" }];
        }
        return NO;
    }

    NSString *runtimeID = entry.runtimeID;
    NSString *runtimeRoot = [CARuntimePaths runtimeRootForID:runtimeID];
    CAUpdateProgress *progressObject = [CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:0.0 status:@"准备下载归档"];

    void (^emit)(CAUpdateStage, double, signed long long, signed long long, NSString *) =
        ^(CAUpdateStage stage, double fraction, signed long long completed, signed long long total, NSString *status) {
            [progressObject applyStage:stage fraction:fraction completedBytes:completed totalBytes:total status:status];
            if (progress) progress(progressObject);
        };

    NSError *stepError = nil;

    // 1) 下载
    emit(CAUpdateStageDownload, 0.0, 0, 0, @"开始下载归档");
    CAManagedRuntimeDownload *download = [[CAManagedRuntimeDownload alloc] initWithEntry:entry];
    BOOL ok = [download downloadWithProgress:^(CAUpdateProgress *downloadProgress) {
        emit(CAUpdateStageDownload,
             downloadProgress.fraction,
             downloadProgress.completedBytes,
             downloadProgress.totalBytes,
             downloadProgress.status.length ? downloadProgress.status : @"下载中");
    } error:&stepError];
    if (!ok) {
        if (error) *error = stepError ?: [NSError errorWithDomain:@"CodexApp.Runtime" code:500
                                                         userInfo:@{ NSLocalizedDescriptionKey: @"运行时归档下载失败" }];
        return NO;
    }

    NSString *packagePath = [download destination];
    if (!packagePath.length || ![NSFileManager.defaultManager fileExistsAtPath:packagePath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CodexApp.Runtime" code:404
                                     userInfo:@{ NSLocalizedDescriptionKey: @"下载完成但归档文件缺失" }];
        }
        return NO;
    }
    emit(CAUpdateStageDownload, 1.0, 0, 0, @"下载完成");

    // 2) 校验
    emit(CAUpdateStageVerify, 0.2, 0, 0, @"校验 SHA256");
    NSData *archiveData = [NSData dataWithContentsOfFile:packagePath options:NSDataReadingMappedIfSafe error:NULL];
    signed long long archiveBytes = (signed long long)archiveData.length;
    NSString *expectedSHA = entry.archiveSHA256;
    if (!expectedSHA.length) {
        emit(CAUpdateStageVerify, 0.5, archiveBytes, archiveBytes, @"清单未提供 SHA256，查询 SHA256SUMS");
        expectedSHA = CAUpdateFetchSHA256Synchronously(packagePath.lastPathComponent, entry.version, 20.0);
    }
    if (expectedSHA.length) {
        if (![[CAUpdateManager sharedManager] cachedPackageAtPath:packagePath matchesSHA256:expectedSHA]) {
            if (error) {
                *error = [NSError errorWithDomain:@"CodexApp.Runtime" code:422
                                         userInfo:@{ NSLocalizedDescriptionKey: @"SHA256 校验失败，归档已丢弃（请重试）" }];
            }
            CALog(CALogLevelError, @"RUNTIME", @"%@ sha256 mismatch path=%@", runtimeID, packagePath);
            [NSFileManager.defaultManager removeItemAtPath:packagePath error:NULL];
            return NO;
        }
        emit(CAUpdateStageVerify, 1.0, archiveBytes, archiveBytes, @"SHA256 校验通过");
    } else {
        CALog(CALogLevelWarn, @"RUNTIME", @"%@ sha256 unavailable; 跳过完整性校验", runtimeID);
        emit(CAUpdateStageVerify, 1.0, archiveBytes, archiveBytes, @"未取得 SHA256，已跳过校验");
    }

    // 3) 解包（归档类型以清单 URL 为准：缓存文件名统一是 .tar.gz，不能据此判断）
    emit(CAUpdateStageExtract, 0.0, 0, 0, @"解包归档");
    if (![CARuntimePaths ensureDirectory:runtimeRoot mode:0755 error:&stepError]) {
        if (error) *error = stepError;
        return NO;
    }
    CAArchiveProgressHandler extractProgress = ^(double fraction, NSString *stage) {
        emit(CAUpdateStageExtract, fraction, 0, 0, stage.length ? stage : @"解包中");
    };
    BOOL isDeb = [entry.archiveURL.pathExtension.lowercaseString isEqualToString:@"deb"];
    BOOL extracted = isDeb
        ? [CAArchiveExtractor extractRuntimeFromDeb:packagePath toDirectory:runtimeRoot progress:extractProgress error:&stepError]
        : [CAArchiveExtractor extractTarGzip:packagePath
                                 toDirectory:runtimeRoot
                        expectedExpandedSize:entry.expandedSize
                                    progress:extractProgress
                                       error:&stepError];
    if (!extracted) {
        if (error) *error = stepError ?: [NSError errorWithDomain:@"CodexApp.Runtime" code:500
                                                        userInfo:@{ NSLocalizedDescriptionKey: @"归档解包失败" }];
        return NO;
    }
    emit(CAUpdateStageExtract, 1.0, 0, 0, @"解包完成");

    // 4) 签名（codex-sign；CAUpdateManager 内部走 bundle 内 entitlements 模板）
    emit(CAUpdateStageSign, 0.2, 0, 0, @"codex-sign 重签名");
    CAUpdatePrepareSigningTemplate();
    NSString *codexPath = nil;
    NSString *hostPath = nil;
    NSArray<NSString *> *binaries = [[CAUpdateManager sharedManager] findExtractedBinariesIn:runtimeRoot
                                                                                  codexPath:&codexPath
                                                                                   hostPath:&hostPath];
    if (binaries.count > 0) {
        if (![[CAUpdateManager sharedManager] signPaths:binaries staging:nil error:&stepError]) {
            if (error) {
                *error = stepError ?: [NSError errorWithDomain:@"CodexApp.Runtime" code:500
                                                      userInfo:@{ NSLocalizedDescriptionKey: @"运行时签名失败" }];
            }
            CALog(CALogLevelError, @"RUNTIME", @"%@ sign failed binaries=%lu error=%@",
                  runtimeID, (unsigned long)binaries.count, stepError.localizedDescription ?: @"(unknown)");
            return NO;
        }
        emit(CAUpdateStageSign, 1.0, 0, 0, [NSString stringWithFormat:@"已签名 %lu 个可执行文件", (unsigned long)binaries.count]);
    } else {
        CALog(CALogLevelWarn, @"RUNTIME", @"%@ no executable found after extraction root=%@", runtimeID, runtimeRoot);
        emit(CAUpdateStageSign, 1.0, 0, 0, @"归档未包含可执行文件，跳过签名");
    }

    // 5) 安装（写安装记录 + 清理下载缓存）
    emit(CAUpdateStageInstall, 0.5, 0, 0, @"写入安装记录");
    NSDictionary *manifest = @{
        @"runtime_id": runtimeID,
        @"revision": @(entry.revision),
        @"version": entry.version ?: @"",
        @"installed_at": @(NSDate.date.timeIntervalSince1970),
        @"archive_sha256": expectedSHA ?: @"",
        @"codex_path": codexPath ?: @"",
        @"host_path": hostPath ?: @"",
    };
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:NULL];
    if (![CARuntimePaths writeFileAtomically:[CARuntimePaths installedManifestPathForRuntimeID:runtimeID]
                                    contents:manifestData ?: [NSData data]
                                        mode:0644
                                       error:&stepError]) {
        if (error) *error = stepError ?: [NSError errorWithDomain:@"CodexApp.Runtime" code:500
                                                        userInfo:@{ NSLocalizedDescriptionKey: @"写入安装记录失败" }];
        return NO;
    }
    [[CAUpdateManager sharedManager] pruneRuntimeDownloadCacheExceptVersion:entry.version];
    emit(CAUpdateStageInstall, 1.0, 0, 0, @"安装完成");
    emit(CAUpdateStageFinished, 1.0, 0, 0, @"安装完成");

    CALog(CALogLevelInfo, @"RUNTIME", @"%@ install completed version=%@ revision=%ld root=%@",
          runtimeID, entry.version ?: @"?", (long)entry.revision, runtimeRoot);
    return YES;
}

+ (BOOL)isRuntimeInstalled:(NSString *)runtimeID
{
    if (!runtimeID.length) return NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:[CARuntimePaths installedManifestPathForRuntimeID:runtimeID]]) return YES;

    NSString *root = [CARuntimePaths runtimeRootForID:runtimeID];
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) return NO;
    NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL];
    return contents.count > 0;
}

+ (NSString *)installedVersionForRuntimeID:(NSString *)runtimeID
{
    if (!runtimeID.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:[CARuntimePaths installedManifestPathForRuntimeID:runtimeID]
                                          options:0
                                            error:NULL];
    if (!data.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) return nil;

    NSDictionary *manifest = (NSDictionary *)json;
    id version = manifest[@"version"];
    if ([version isKindOfClass:NSString.class] && [(NSString *)version length] > 0) return version;
    id revision = manifest[@"revision"];
    return [revision isKindOfClass:NSNumber.class] ? [(NSNumber *)revision stringValue] : nil;
}

@end
