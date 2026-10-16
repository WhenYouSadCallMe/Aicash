//
//  CARootViewController.m — 外壳容器实现（顶部标题栏 + 三个入口 + 内容子控制器）
//

#import "CARootViewController.h"
#import "CAChatViewController.h"
#import "CASettingsViewController.h"
#import "CADiagnosticsViewController.h"
#import "CACommon.h"
#import "CALogger.h"

@interface CARootViewController ()

- (void)buildTopBar;
- (void)installContentViewController;
- (void)uninstallContentViewController;
- (UIButton *)entryButtonWithTitle:(NSString *)title action:(SEL)action;
- (void)presentController:(UIViewController *)controller;
- (void)handleOpenChat;
- (void)handleOpenSettings;
- (void)handleOpenDiagnostics;

@end

@implementation CARootViewController {
    UIViewController *_contentViewController;
    UIView *_topBar;
    UILabel *_titleLabel;
    UIView *_contentContainer;
}

#pragma mark - 构造

- (id)initWithContentViewController:(id)arg1
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _contentViewController = [arg1 isKindOfClass:UIViewController.class] ? (UIViewController *)arg1 : nil;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithContentViewController:nil];
}

+ (instancetype)launcherRootViewController
{
    return [[CARootViewController alloc] initWithContentViewController:[[CAChatViewController alloc] init]];
}

#pragma mark - 声明选择器

- (UIViewController *)contentViewController { return _contentViewController; }

- (void)setContentViewController:(id)arg1
{
    UIViewController *controller = [arg1 isKindOfClass:UIViewController.class] ? (UIViewController *)arg1 : nil;
    if (controller == _contentViewController) return;
    [self uninstallContentViewController];
    _contentViewController = controller;
    if (self.isViewLoaded) [self installContentViewController];
}

- (id)childViewControllerForStatusBarStyle { return _contentViewController; }

- (id)childViewControllerForStatusBarHidden { return _contentViewController; }

- (id)childViewControllerForHomeIndicatorAutoHidden { return _contentViewController; }

- (bool)shouldAutorotate { return YES; }

- (unsigned long long)supportedInterfaceOrientations
{
    if ([UIDevice.currentDevice userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return UIInterfaceOrientationMaskAll;
    }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self buildTopBar];

    _contentContainer = [[UIView alloc] initWithFrame:CGRectZero];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_contentContainer];
    [NSLayoutConstraint activateConstraints:@[
        [_contentContainer.topAnchor constraintEqualToAnchor:_topBar.bottomAnchor],
        [_contentContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self installContentViewController];
    CALog(CALogLevelInfo, @"GENERAL", @"root shell loaded content=%@",
          _contentViewController ? NSStringFromClass(_contentViewController.class) : @"(none)");
}

- (void)dealloc
{
    [self uninstallContentViewController];
}

#pragma mark - 顶部栏

- (void)buildTopBar
{
    _topBar = [[UIView alloc] initWithFrame:CGRectZero];
    _topBar.translatesAutoresizingMaskIntoConstraints = NO;
    _topBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:_topBar];
    [NSLayoutConstraint activateConstraints:@[
        [_topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_topBar.heightAnchor constraintEqualToConstant:44.0],
    ]];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.text = CABundleDisplayName;
    [_topBar addSubview:_titleLabel];

    UIButton *chatButton = [self entryButtonWithTitle:@"会话" action:@selector(handleOpenChat)];
    UIButton *settingsButton = [self entryButtonWithTitle:@"设置" action:@selector(handleOpenSettings)];
    UIButton *diagnosticsButton = [self entryButtonWithTitle:@"诊断" action:@selector(handleOpenDiagnostics)];

    UIStackView *entries = [[UIStackView alloc] initWithArrangedSubviews:@[ chatButton, settingsButton, diagnosticsButton ]];
    entries.axis = UILayoutConstraintAxisHorizontal;
    entries.alignment = UIStackViewAlignmentCenter;
    entries.spacing = 12.0;
    entries.translatesAutoresizingMaskIntoConstraints = NO;
    [_topBar addSubview:entries];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_topBar.layoutMarginsGuide.leadingAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
        [entries.trailingAnchor constraintEqualToAnchor:_topBar.layoutMarginsGuide.trailingAnchor],
        [entries.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
        [entries.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8.0],
    ]];
}

- (UIButton *)entryButtonWithTitle:(NSString *)title action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.contentEdgeInsets = UIEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
    button.layer.cornerRadius = 8.0;
    button.backgroundColor = UIColor.tertiarySystemFillColor;
    return button;
}

#pragma mark - 内容子控制器

- (void)installContentViewController
{
    if (!_contentViewController || !_contentContainer) return;
    UIViewController *controller = _contentViewController;
    [self addChildViewController:controller];
    controller.view.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentContainer addSubview:controller.view];
    [NSLayoutConstraint activateConstraints:@[
        [controller.view.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor],
        [controller.view.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
        [controller.view.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],
        [controller.view.bottomAnchor constraintEqualToAnchor:_contentContainer.bottomAnchor],
    ]];
    [controller didMoveToParentViewController:self];
}

- (void)uninstallContentViewController
{
    if (!_contentViewController) return;
    UIViewController *controller = _contentViewController;
    [controller willMoveToParentViewController:nil];
    [controller.view removeFromSuperview];
    [controller removeFromParentViewController];
}

#pragma mark - 入口

- (void)handleOpenChat
{
    if ([_contentViewController isKindOfClass:CAChatViewController.class]) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CAChatViewController alloc] init]];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)handleOpenSettings
{
    [self presentSettings];
}

- (void)handleOpenDiagnostics
{
    [self presentDiagnostics];
}

- (void)presentSettings
{
    [self presentController:[[CASettingsViewController alloc] init]];
}

- (void)presentDiagnostics
{
    [self presentController:[[CADiagnosticsViewController alloc] init]];
}

- (void)presentController:(UIViewController *)controller
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
    CALog(CALogLevelDebug, @"GENERAL", @"root shell presented %@", NSStringFromClass(controller.class));
}

@end
