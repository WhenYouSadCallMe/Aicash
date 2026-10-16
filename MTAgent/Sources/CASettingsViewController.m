//
//  CASettingsViewController.m
//
//  分区：账号 / Provider / 运行时 / 日志与诊断 / 关于。
//  行为对齐原包：
//    · 默认键 CodexUseThirdPartyProvider / CodexThirdPartyProviderName / CodexAPIBaseURL /
//      CodexSelectedModel / CodexThirdPartyContextWindowTokens / CodexThirdPartyReasoningEffort
//    · 密钥保存走 CAProviderConfiguration -saveAPIKey:error:（文件落盘 + Keychain 旧项迁移由该层负责）
//    · 登录四种入口全部由 CACodexEngine 驱动的本地 codex CLI 承担
//

#import "CASettingsViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CACodexEngine.h"
#import "CAProviderConfiguration.h"
#import "CARemoteOperations.h"
#import "CARuntimeCatalog.h"
#import "CAStorageManager.h"
#import "CAMCPBridge.h"
#import "CALogViewerViewController.h"
#import "CADiagnosticsViewController.h"

static NSString * const kSettingsCellReuseIdentifier = @"CASettingsCell";
static NSString * const kSettingsFieldCellReuseIdentifier = @"CASettingsFieldCell";

/// 统一使用 UITableViewCellStyleValue1（左侧标题 + 右侧详情）
@interface CASettingsValueCell : UITableViewCell
@end

@implementation CASettingsValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}

@end

typedef NS_ENUM(NSInteger, CASettingsSection) {
    CASettingsSectionAccount = 0,
    CASettingsSectionProvider,
    CASettingsSectionRuntime,
    CASettingsSectionDiagnostics,
    CASettingsSectionAbout,
    CASettingsSectionCount,
};

typedef NS_ENUM(NSInteger, CASettingsAccountRow) {
    CASettingsAccountRowStatus = 0,
    CASettingsAccountRowLoginToggle,
    CASettingsAccountRowAPIKey,
    CASettingsAccountRowAccessToken,
    CASettingsAccountRowDeviceAuth,
    CASettingsAccountRowBrowserOAuth,
    CASettingsAccountRowLogout,
    CASettingsAccountRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsProviderRow) {
    CASettingsProviderRowUseThirdParty = 0,
    CASettingsProviderRowAppServerChat,
    CASettingsProviderRowName,
    CASettingsProviderRowBaseURL,
    CASettingsProviderRowModel,
    CASettingsProviderRowContext,
    CASettingsProviderRowReasoning,
    CASettingsProviderRowSecret,
    CASettingsProviderRowSave,
    CASettingsProviderRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsRuntimeRow) {
    CASettingsRuntimeRowManager = 0,
    CASettingsRuntimeRowRefresh,
    CASettingsRuntimeRowClearCache,
    CASettingsRuntimeRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsDiagnosticsRow) {
    CASettingsDiagnosticsRowLogs = 0,
    CASettingsDiagnosticsRowDiagnostics,
    CASettingsDiagnosticsRowPurgeCaches,
    CASettingsDiagnosticsRowCount,
};

@interface CASettingsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) UISwitch *thirdPartySourceSwitch;
@property (nonatomic, strong, nullable) UISwitch *appServerChatSwitch;
@property (nonatomic, copy, nullable) NSString *thirdPartySecretPlaceholder;

- (void)prepareThirdPartyDrafts;
- (NSString *)trimmedString:(NSString *)string;
- (void)finishLoginWithGeneration:(NSUInteger)generation ok:(BOOL)ok message:(nullable NSString *)message;
- (void)performLoginWithKind:(NSString *)kind secret:(NSString *)secret;
- (void)presentDeviceCode:(NSString *)code;
- (void)thirdPartyFieldDidEndEditing:(UITextField *)sender;
- (void)thirdPartySourceSwitchChanged:(UISwitch *)sender;
- (void)appServerChatSwitchChanged:(UISwitch *)sender;
- (void)refreshRuntimeCatalog;
- (void)showRuntimeToolEntry:(CARuntimeCatalogEntry *)entry installed:(BOOL)installed root:(nullable NSString *)root;
- (void)runtimeCatalogChanged:(NSNotification *)notification;
- (void)accountCredentialsDidChange;
- (void)showMessage:(NSString *)message title:(NSString *)title;
- (void)handleDone;

@end

@implementation CASettingsViewController

#pragma mark - 生命周期

- (instancetype)init
{
    if ((self = [super init])) {
        _loginAttemptGeneration = 0;
        _loginOptionsExpanded = NO;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"设置";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:CASettingsValueCell.class forCellReuseIdentifier:kSettingsCellReuseIdentifier];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kSettingsFieldCellReuseIdentifier];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                          target:self
                                                                                          action:@selector(handleDone)];

    [self prepareThirdPartyDrafts];
    [self refreshLoginStatus];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeCatalogChanged:)
                                                 name:CARuntimeCatalogDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountCredentialsDidChange)
                                                 name:@"CAAccountCredentialsDidChangeNotification"
                                               object:nil];

    CALog(CALogLevelInfo, @"GENERAL", @"settings view loaded");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshLoginStatus];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.onSettingsChanged) self.onSettingsChanged();
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 草稿

- (void)prepareThirdPartyDrafts
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.thirdPartyExpanded = [defaults boolForKey:CADefaultsUseThirdPartyProvider];
    self.thirdPartyDraftName = [defaults stringForKey:CADefaultsThirdPartyProviderName] ?: @"Custom";
    self.thirdPartyDraftBaseURL = [defaults stringForKey:CADefaultsAPIBaseURL] ?: @"https://api.example.com/v1";
    self.thirdPartyDraftModel = [defaults stringForKey:CADefaultsSelectedModel] ?: [defaults stringForKey:CADefaultsThirdPartyModel] ?: @"";
    self.thirdPartyDraftKey = @"";

    BOOL hasKey = [[CACodexEngine sharedEngine] hasThirdPartyAPIKey];
    self.thirdPartySecretPlaceholder = hasKey ? @"已保存，重新输入以覆盖" : @"粘贴 provider 密钥";
}

- (NSString *)trimmedString:(NSString *)string
{
    return [(string ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

#pragma mark - 登录状态

- (void)refreshLoginStatus
{
    __weak typeof(self) weakSelf = self;
    [[CACodexEngine sharedEngine] checkLoginStatusWithCompletion:^(BOOL loggedIn, NSString *status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.isLoggedIn = loggedIn;
            strongSelf.loginStatusText = status.length > 0 ? status : (loggedIn ? @"已登录" : @"未登录");
            strongSelf.loginTask = [CACodexEngine sharedEngine].loginTask;
            [strongSelf.tableView reloadData];
        });
    }];
}

- (void)accountCredentialsDidChange
{
    [self refreshLoginStatus];
}

- (void)finishLoginWithGeneration:(NSUInteger)generation ok:(BOOL)ok message:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self.loginAttemptGeneration) {
            CALog(CALogLevelDebug, @"GENERAL", @"stale login result ignored generation=%lu", (unsigned long)generation);
            return;
        }
        self.isLoggedIn = ok;
        self.loginStatusText = message.length > 0 ? message : (ok ? @"已登录" : @"登录失败");
        self.loginTask = [CACodexEngine sharedEngine].loginTask;
        [self.tableView reloadData];
        [self showMessage:self.loginStatusText title:ok ? @"登录成功" : @"登录失败"];
        if (ok && self.onSettingsChanged) self.onSettingsChanged();
    });
}

- (void)handleAPIKeyLogin
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"API Key 登录"
                                                                  message:@"粘贴你的 API Key，仅写入本机 codex 配置"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"sk-…";
        textField.secureTextEntry = YES;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = [weakSelf trimmedString:alert.textFields.firstObject.text];
        [weakSelf performLoginWithKind:@"api-key" secret:key];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleAccessTokenLogin
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Access Token 登录"
                                                                  message:@"粘贴 codex 访问令牌"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"token";
        textField.secureTextEntry = YES;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"登录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *token = [weakSelf trimmedString:alert.textFields.firstObject.text];
        [weakSelf performLoginWithKind:@"access-token" secret:token];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleDeviceAuthLogin
{
    self.loginAttemptGeneration += 1;
    NSUInteger generation = self.loginAttemptGeneration;
    self.loginStatusText = @"等待设备码…";
    [self.tableView reloadData];

    CALog(CALogLevelInfo, @"GENERAL", @"device auth login started");
    __weak typeof(self) weakSelf = self;
    [[CACodexEngine sharedEngine] startDeviceLoginWithCodeHandler:^(NSString *code) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.loginStatusText = [NSString stringWithFormat:@"设备码 %@", code];
            [strongSelf.tableView reloadData];
            [strongSelf presentDeviceCode:code];
        });
    } completion:^(BOOL ok, NSString *message) {
        [weakSelf finishLoginWithGeneration:generation ok:ok message:message];
    }];
}

- (void)handleBrowserOAuthLogin
{
    self.loginAttemptGeneration += 1;
    NSUInteger generation = self.loginAttemptGeneration;
    self.loginStatusText = @"等待浏览器授权…";
    [self.tableView reloadData];

    CALog(CALogLevelInfo, @"GENERAL", @"browser oauth login started");
    __weak typeof(self) weakSelf = self;
    [[CACodexEngine sharedEngine] startBrowserOAuthLoginWithUrlHandler:^(NSURL *url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                CALog(CALogLevelInfo, @"GENERAL", @"oauth url opened=%d", success);
            }];
        });
    } completion:^(BOOL ok, NSString *message) {
        [weakSelf finishLoginWithGeneration:generation ok:ok message:message];
    }];
}

- (void)performLoginWithKind:(NSString *)kind secret:(NSString *)secret
{
    if (secret.length == 0) {
        [self showMessage:@"请先填写凭据" title:@"无法登录"];
        return;
    }

    self.loginAttemptGeneration += 1;
    NSUInteger generation = self.loginAttemptGeneration;
    self.loginStatusText = @"登录中…";
    [self.tableView reloadData];

    CALog(CALogLevelInfo, @"GENERAL", @"login attempt kind=%@", kind);
    __weak typeof(self) weakSelf = self;
    if ([kind isEqualToString:@"api-key"]) {
        [[CACodexEngine sharedEngine] loginWithAPIKey:secret completion:^(BOOL ok, NSString *message) {
            [weakSelf finishLoginWithGeneration:generation ok:ok message:message];
        }];
    } else {
        [[CACodexEngine sharedEngine] loginWithAccessToken:secret completion:^(BOOL ok, NSString *message) {
            [weakSelf finishLoginWithGeneration:generation ok:ok message:message];
        }];
    }
}

- (void)presentDeviceCode:(NSString *)code
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设备码登录"
                                                                  message:[NSString stringWithFormat:@"在浏览器中输入设备码：\n\n%@", code]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制设备码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = code;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleLogout
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"退出登录"
                                                                  message:@"将清除本机 codex 登录态"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[CACodexEngine sharedEngine] logoutWithCompletion:^(BOOL ok) {
            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.isLoggedIn = !ok;
                strongSelf.loginStatusText = ok ? @"已退出登录" : @"退出失败";
                [strongSelf refreshLoginStatus];
                [strongSelf showMessage:strongSelf.loginStatusText title:@"账号"];
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.tableView;
    alert.popoverPresentationController.sourceRect = self.tableView.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Provider

- (void)secretFieldChanged:(UITextField *)sender
{
    self.thirdPartyDraftKey = sender.text ?: @"";
    CALog(CALogLevelDebug, @"GENERAL", @"provider secret draft length=%lu", (unsigned long)self.thirdPartyDraftKey.length);
}

- (void)thirdPartyFieldChanged:(UITextField *)sender
{
    switch ((CASettingsProviderRow)sender.tag) {
        case CASettingsProviderRowName:
            self.thirdPartyDraftName = sender.text ?: @"";
            break;
        case CASettingsProviderRowBaseURL:
            self.thirdPartyDraftBaseURL = sender.text ?: @"";
            break;
        case CASettingsProviderRowModel:
            self.thirdPartyDraftModel = sender.text ?: @"";
            break;
        case CASettingsProviderRowSecret:
            [self secretFieldChanged:sender];
            break;
        default:
            break;
    }
}

- (void)thirdPartyFieldDidEndEditing:(UITextField *)sender
{
    [self thirdPartyFieldChanged:sender];
}

- (void)thirdPartySourceSwitchChanged:(UISwitch *)sender
{
    self.thirdPartyExpanded = sender.isOn;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.isOn forKey:CADefaultsUseThirdPartyProvider];
    [self.tableView reloadData];
    CALog(CALogLevelInfo, @"GENERAL", @"third-party provider enabled=%d", sender.isOn);
}

- (void)appServerChatSwitchChanged:(UISwitch *)sender
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:sender.isOn forKey:CADefaultsUsePersistentAppServer];
    CALog(CALogLevelInfo, @"GENERAL", @"persistent app-server chat enabled=%d", sender.isOn);
}

- (void)saveThirdPartyConfiguration
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL useThirdParty = self.thirdPartySourceSwitch ? self.thirdPartySourceSwitch.isOn : [defaults boolForKey:CADefaultsUseThirdPartyProvider];
    BOOL useAppServer = self.appServerChatSwitch ? self.appServerChatSwitch.isOn : [defaults boolForKey:CADefaultsUsePersistentAppServer];

    NSString *name = [self trimmedString:self.thirdPartyDraftName];
    NSString *baseURL = [self trimmedString:self.thirdPartyDraftBaseURL];
    NSString *model = [self trimmedString:self.thirdPartyDraftModel];
    NSString *key = [self trimmedString:self.thirdPartyDraftKey];

    [defaults setBool:useThirdParty forKey:CADefaultsUseThirdPartyProvider];
    [defaults setBool:useAppServer forKey:CADefaultsUsePersistentAppServer];
    if (name.length > 0) [defaults setObject:name forKey:CADefaultsThirdPartyProviderName];
    if (baseURL.length > 0) [defaults setObject:[CAProviderConfiguration normalizedBaseURL:baseURL] forKey:CADefaultsAPIBaseURL];
    if (model.length > 0) {
        [defaults setObject:model forKey:CADefaultsSelectedModel];
        [defaults setObject:model forKey:CADefaultsThirdPartyModel];
    }

    if (key.length > 0) {
        NSError *error = nil;
        if (![[CAProviderConfiguration sharedConfiguration] saveAPIKey:key error:&error]) {
            CALog(CALogLevelWarn, @"GENERAL", @"provider key save failed: %@", error);
            [self showMessage:error.localizedDescription ?: @"密钥保存失败" title:@"Provider"];
            return;
        }
        NSError *engineError = nil;
        if (![[CACodexEngine sharedEngine] saveThirdPartyAPIKey:key error:&engineError]) {
            CALog(CALogLevelWarn, @"GENERAL", @"engine key save failed: %@", engineError);
        }
        self.thirdPartyDraftKey = @"";
        self.thirdPartySecretPlaceholder = @"已保存，重新输入以覆盖";
    }

    CACodexEngine *engine = [CACodexEngine sharedEngine];
    engine.useThirdPartyProvider = useThirdParty;
    engine.thirdPartyProviderName = name;
    engine.sandboxMode = [defaults stringForKey:CADefaultsSandboxMode] ?: @"danger-full-access";

    CALog(CALogLevelInfo, @"GENERAL", @"provider saved enabled=%d name=%@ base=%@ model=%@ hasKey=%d",
          useThirdParty, name ?: @"(default)", baseURL ?: @"(default)", model ?: @"(default)", key.length > 0 ? 1 : 0);

    [self.tableView reloadData];
    [self showMessage:@"配置已保存" title:@"Provider"];
    if (self.onSettingsChanged) self.onSettingsChanged();
}

#pragma mark - 子页面

- (void)showRuntimeManager
{
    CARuntimeCatalog *catalog = [CARuntimeCatalog sharedCatalog];
    NSArray<CARuntimeCatalogEntry *> *entries = catalog.entries;

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"清单：%@\n", catalog.cachePath ?: catalog.manifestURLString ?: @"(未缓存)"];
    [summary appendFormat:@"条目：%lu 项", (unsigned long)entries.count];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"运行时管理"
                                                                  message:summary
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    NSUInteger index = 0;
    for (CARuntimeCatalogEntry *entry in entries) {
        if (index >= 8) break;
        index += 1;
        NSString *root = entry.runtimeID.length > 0 ? [CARuntimePaths runtimeRootForID:entry.runtimeID] : nil;
        BOOL installed = root.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:root];
        NSString *title = [NSString stringWithFormat:@"%@%@ · %@",
                           installed ? @"✓ " : @"○ ",
                           entry.displayName ?: entry.runtimeID ?: @"?",
                           entry.version ?: @"?"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showRuntimeToolEntry:entry installed:installed root:root];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"刷新清单" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self refreshRuntimeCatalog];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = self.tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)refreshRuntimeCatalog
{
    [[CARuntimeCatalog sharedCatalog] refreshNowWithCompletion:^(BOOL ok, NSError *error) {
        CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"RUNTIME", @"manual runtime refresh ok=%d error=%@", ok, error);
    }];
}

- (void)showRuntimeToolEntry:(CARuntimeCatalogEntry *)entry installed:(BOOL)installed root:(NSString *)root
{
    NSString *message = [NSString stringWithFormat:@"ID：%@\n版本：%@\n状态：%@\n大小：%@\n安装根：%@\n摘要：%@",
                         entry.runtimeID ?: @"?",
                         entry.version ?: @"?",
                         installed ? @"已安装" : @"未安装",
                         [NSByteCountFormatter stringFromByteCount:(long long)entry.expandedSize countStyle:NSByteCountFormatterCountStyleFile],
                         root ?: @"(未知)",
                         entry.summary ?: @"(无)"];
    [self showMessage:message title:entry.displayName ?: entry.runtimeID ?: @"运行时"];
}

- (void)showLogViewer
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CALogViewerViewController alloc] init]];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)showDiagnostics
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CADiagnosticsViewController alloc] init]];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)runtimeCatalogChanged:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)handleDone
{
    if (self.onSettingsChanged) self.onSettingsChanged();
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 提示

- (void)showMessage:(NSString *)message title:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return CASettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ((CASettingsSection)section) {
        case CASettingsSectionAccount:
            return self.loginOptionsExpanded ? CASettingsAccountRowCount : 2;
        case CASettingsSectionProvider:
            // 外壳实现保留整组 provider 字段（原包在关闭第三方时折叠为开关行）
            return CASettingsProviderRowCount;
        case CASettingsSectionRuntime:
            return CASettingsRuntimeRowCount;
        case CASettingsSectionDiagnostics:
            return CASettingsDiagnosticsRowCount;
        case CASettingsSectionAbout:
        default:
            return 4;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    switch ((CASettingsSection)indexPath.section) {
        case CASettingsSectionAccount: {
            if (indexPath.row == CASettingsAccountRowStatus) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.textLabel.text = self.isLoggedIn ? @"已登录" : @"未登录";
                cell.detailTextLabel.text = self.loginStatusText ?: @"未检查";
                cell.imageView.image = [UIImage systemImageNamed:self.isLoggedIn ? @"checkmark.seal.fill" : @"person.crop.circle"];
                cell.imageView.tintColor = self.isLoggedIn ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
            if (indexPath.row == CASettingsAccountRowLoginToggle) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.textLabel.text = self.loginOptionsExpanded ? @"收起登录方式" : @"更多登录方式";
                cell.detailTextLabel.text = self.loginOptionsExpanded ? @"" : @"API Key / Token / 设备码 / 浏览器";
                cell.accessoryType = self.loginOptionsExpanded ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }

            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.imageView.image = nil;
            switch ((CASettingsAccountRow)indexPath.row) {
                case CASettingsAccountRowAPIKey:
                    cell.textLabel.text = @"API Key 登录";
                    break;
                case CASettingsAccountRowAccessToken:
                    cell.textLabel.text = @"Access Token 登录";
                    break;
                case CASettingsAccountRowDeviceAuth:
                    cell.textLabel.text = @"设备码登录";
                    break;
                case CASettingsAccountRowBrowserOAuth:
                    cell.textLabel.text = @"浏览器 OAuth 登录";
                    break;
                case CASettingsAccountRowLogout:
                    cell.textLabel.text = @"退出登录";
                    cell.textLabel.textColor = UIColor.systemRedColor;
                    break;
                default:
                    cell.textLabel.text = @"";
                    break;
            }
            cell.detailTextLabel.text = @"";
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }

        case CASettingsSectionProvider: {
            if (indexPath.row == CASettingsProviderRowUseThirdParty) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.imageView.image = nil;
                cell.textLabel.text = @"使用第三方 Provider";
                UISwitch *toggle = [[UISwitch alloc] init];
                toggle.on = [defaults boolForKey:CADefaultsUseThirdPartyProvider];
                [toggle addTarget:self action:@selector(thirdPartySourceSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                self.thirdPartySourceSwitch = toggle;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
            if (indexPath.row == CASettingsProviderRowAppServerChat) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.imageView.image = nil;
                cell.textLabel.text = @"常驻 app-server 会话";
                UISwitch *toggle = [[UISwitch alloc] init];
                toggle.on = [defaults boolForKey:CADefaultsUsePersistentAppServer];
                [toggle addTarget:self action:@selector(appServerChatSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                self.appServerChatSwitch = toggle;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
            if (indexPath.row == CASettingsProviderRowSave) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.imageView.image = nil;
                cell.textLabel.text = @"保存 Provider 配置";
                cell.textLabel.textColor = self.view.tintColor;
                cell.detailTextLabel.text = @"";
                cell.accessoryView = nil;
                return cell;
            }

            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsFieldCellReuseIdentifier forIndexPath:indexPath];
            for (UIView *subview in cell.contentView.subviews) {
                if ([subview isKindOfClass:UITextField.class]) [subview removeFromSuperview];
            }
            cell.accessoryView = nil;
            cell.imageView.image = nil;
            cell.textLabel.text = @"";

            UITextField *field = [[UITextField alloc] initWithFrame:cell.contentView.bounds];
            field.translatesAutoresizingMaskIntoConstraints = NO;
            field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.tag = indexPath.row;
            field.delegate = self;
            [field addTarget:self action:@selector(thirdPartyFieldChanged:) forControlEvents:UIControlEventEditingChanged];
            [field addTarget:self action:@selector(thirdPartyFieldDidEndEditing:) forControlEvents:UIControlEventEditingDidEnd];

            switch ((CASettingsProviderRow)indexPath.row) {
                case CASettingsProviderRowName:
                    field.placeholder = @"provider 名称";
                    field.text = self.thirdPartyDraftName;
                    break;
                case CASettingsProviderRowBaseURL:
                    field.placeholder = @"Base URL（如 https://api.example.com/v1）";
                    field.keyboardType = UIKeyboardTypeURL;
                    field.text = self.thirdPartyDraftBaseURL;
                    break;
                case CASettingsProviderRowModel:
                    field.placeholder = @"模型（如 gpt-5-codex）";
                    field.text = self.thirdPartyDraftModel;
                    break;
                case CASettingsProviderRowContext:
                    field.placeholder = [NSString stringWithFormat:@"上下文窗口（当前 %@）",
                                         [defaults objectForKey:CADefaultsThirdPartyContextWindow] ?: @272000];
                    field.keyboardType = UIKeyboardTypeNumberPad;
                    field.text = @"";
                    break;
                case CASettingsProviderRowReasoning:
                    field.placeholder = [NSString stringWithFormat:@"推理强度（当前 %@）",
                                         [defaults stringForKey:CADefaultsThirdPartyReasoning] ?: @"medium"];
                    field.text = @"";
                    break;
                case CASettingsProviderRowSecret:
                    field.placeholder = self.thirdPartySecretPlaceholder;
                    field.secureTextEntry = YES;
                    field.text = @"";
                    break;
                default:
                    field.placeholder = @"";
                    break;
            }

            [cell.contentView addSubview:field];
            [NSLayoutConstraint activateConstraints:@[
                [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            ]];
            return cell;
        }

        case CASettingsSectionRuntime: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.imageView.image = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            switch ((CASettingsRuntimeRow)indexPath.row) {
                case CASettingsRuntimeRowManager: {
                    cell.textLabel.text = @"运行时管理";
                    NSUInteger total = [CARuntimeCatalog sharedCatalog].entries.count;
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 项", (unsigned long)total];
                    break;
                }
                case CASettingsRuntimeRowRefresh:
                    cell.textLabel.text = @"刷新运行时清单";
                    cell.detailTextLabel.text = @"runtime-manifest.json";
                    break;
                case CASettingsRuntimeRowClearCache:
                default:
                    cell.textLabel.text = @"清理运行时下载缓存";
                    cell.detailTextLabel.text = @"";
                    break;
            }
            return cell;
        }

        case CASettingsSectionDiagnostics: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.imageView.image = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            switch ((CASettingsDiagnosticsRow)indexPath.row) {
                case CASettingsDiagnosticsRowLogs:
                    cell.textLabel.text = @"日志";
                    cell.detailTextLabel.text = [[CALogger sharedLogger] logFilePath].lastPathComponent ?: @"";
                    break;
                case CASettingsDiagnosticsRowDiagnostics:
                    cell.textLabel.text = @"诊断";
                    cell.detailTextLabel.text = @"网络 / 运行时 / 环境 / MCP";
                    break;
                case CASettingsDiagnosticsRowPurgeCaches:
                default:
                    cell.textLabel.text = @"清理缓存";
                    cell.detailTextLabel.text = @"logs / diagnostics / tmp";
                    break;
            }
            return cell;
        }

        case CASettingsSectionAbout:
        default: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.imageView.image = nil;
            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = @"版本";
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", CABundleShortVersion, CABundleVersion];
                    break;
                case 1:
                    cell.textLabel.text = @"Bundle ID";
                    cell.detailTextLabel.text = CABundleIdentifier;
                    break;
                case 2:
                    cell.textLabel.text = @"内部 MCP 桥";
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                                 CAInternalMCPURLString,
                                                 [CAMCPBridge sharedBridge].running ? @"运行中" : @"未运行"];
                    break;
                default:
                    cell.textLabel.text = @"远端心跳";
                    cell.detailTextLabel.text = [CARemoteOperations sharedOperations].heartbeatHealthy ? @"正常" : @"异常";
                    break;
            }
            return cell;
        }
    }
}

#pragma mark - UITableViewDelegate

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch ((CASettingsSection)section) {
        case CASettingsSectionAccount:     return @"账号";
        case CASettingsSectionProvider:    return @"Provider";
        case CASettingsSectionRuntime:     return @"Codex Runtime";
        case CASettingsSectionDiagnostics: return @"日志与诊断";
        case CASettingsSectionAbout:
        default:                           return @"关于";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ((CASettingsSection)section == CASettingsSectionProvider) {
        return [NSString stringWithFormat:@"密钥写入 %@；provider 配置随 codex CLI 启动参数下发。",
                [CAProviderConfiguration sharedConfiguration].keyPath.lastPathComponent ?: @"api-key"];
    }
    if ((CASettingsSection)section == CASettingsSectionAccount) {
        return self.loginStatusText ?: @"";
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch ((CASettingsSection)indexPath.section) {
        case CASettingsSectionAccount: {
            if (indexPath.row == CASettingsAccountRowLoginToggle) {
                self.loginOptionsExpanded = !self.loginOptionsExpanded;
                [tableView reloadSections:[NSIndexSet indexSetWithIndex:CASettingsSectionAccount]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
                return;
            }
            switch ((CASettingsAccountRow)indexPath.row) {
                case CASettingsAccountRowAPIKey:       [self handleAPIKeyLogin]; break;
                case CASettingsAccountRowAccessToken:  [self handleAccessTokenLogin]; break;
                case CASettingsAccountRowDeviceAuth:   [self handleDeviceAuthLogin]; break;
                case CASettingsAccountRowBrowserOAuth: [self handleBrowserOAuthLogin]; break;
                case CASettingsAccountRowLogout:       [self handleLogout]; break;
                default: break;
            }
            return;
        }

        case CASettingsSectionProvider: {
            if (indexPath.row == CASettingsProviderRowSave) {
                [self saveThirdPartyConfiguration];
            }
            return;
        }

        case CASettingsSectionRuntime: {
            switch ((CASettingsRuntimeRow)indexPath.row) {
                case CASettingsRuntimeRowManager:    [self showRuntimeManager]; break;
                case CASettingsRuntimeRowRefresh:    [self refreshRuntimeCatalog]; break;
                case CASettingsRuntimeRowClearCache:
                    [[CAStorageManager sharedManager] clearRuntimeDownloadCaches];
                    [self showMessage:@"下载缓存已清理" title:@"运行时"];
                    break;
            }
            return;
        }

        case CASettingsSectionDiagnostics: {
            switch ((CASettingsDiagnosticsRow)indexPath.row) {
                case CASettingsDiagnosticsRowLogs:        [self showLogViewer]; break;
                case CASettingsDiagnosticsRowDiagnostics: [self showDiagnostics]; break;
                case CASettingsDiagnosticsRowPurgeCaches:
                    [[CAStorageManager sharedManager] purgeCachesWithCompletion:^(NSError *error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self showMessage:error ? error.localizedDescription : @"缓存已清理" title:@"清理缓存"];
                        });
                    }];
                    break;
            }
            return;
        }

        default:
            return;
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

@end
