//
//  CASettingsViewController.m
//
//  分区：账号 / Provider / 模型 / Codex Runtime / MCP / 日志与诊断 / 环境 / 关于。
//  行为对齐原包：
//    · 默认键 CodexUseThirdPartyProvider / CodexThirdPartyProviderName / CodexAPIBaseURL /
//      CodexSelectedModel / CodexThirdPartyContextWindowTokens / CodexThirdPartyReasoningEffort
//    · 密钥保存走 CAProviderConfiguration -saveAPIKey:error:（文件落盘 + Keychain 旧项迁移由该层负责）
//    · 模型目录走 CAModelPricingManager / CAThirdPartyModelCatalog（写 codex model_catalog_json）
//    · 运行时安装走 CARuntimeCatalog + CARuntimePaths + CAUpdateViewController（→ CAUpdateManager）
//    · MCP 开关走 CAMCPBridge 启停 + CAComposerCatalog 改写 config.toml 的 [mcp_servers.<name>]
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
#import "CAModelPricingManager.h"
#import "CAComposerCatalog.h"
#import "CAExecutionEnvironment.h"
#import "CAUpdateViewController.h"
#import "CALogViewerViewController.h"
#import "CADiagnosticsViewController.h"

static NSString * const kSettingsCellReuseIdentifier = @"CASettingsCell";
static NSString * const kSettingsFieldCellReuseIdentifier = @"CASettingsFieldCell";

/// 本机内部 MCP 桥在 config.toml 里的服务名（CAComposerCatalog +isInternalMCPName: 认可的名字）
static NSString * const kSettingsInternalMCPName = @"codexapp";

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
    CASettingsSectionModel,
    CASettingsSectionRuntime,
    CASettingsSectionMCP,
    CASettingsSectionDiagnostics,
    CASettingsSectionEnvironment,
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
    CASettingsProviderRowTest,
    CASettingsProviderRowClear,
    CASettingsProviderRowSave,
    CASettingsProviderRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsModelRow) {
    CASettingsModelRowCurrent = 0,
    CASettingsModelRowSelect,
    CASettingsModelRowReasoning,
    CASettingsModelRowCatalog,
    CASettingsModelRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsRuntimeRow) {
    CASettingsRuntimeRowVersion = 0,
    CASettingsRuntimeRowCheckUpdate,
    CASettingsRuntimeRowInstall,
    CASettingsRuntimeRowManager,
    CASettingsRuntimeRowRefresh,
    CASettingsRuntimeRowClearCache,
    CASettingsRuntimeRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsMCPRow) {
    CASettingsMCPRowToggle = 0,
    CASettingsMCPRowStatus,
    CASettingsMCPRowConfig,
    CASettingsMCPRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsDiagnosticsRow) {
    CASettingsDiagnosticsRowLogs = 0,
    CASettingsDiagnosticsRowDiagnostics,
    CASettingsDiagnosticsRowPurgeCaches,
    CASettingsDiagnosticsRowCount,
};

typedef NS_ENUM(NSInteger, CASettingsEnvironmentRow) {
    CASettingsEnvironmentRowSummary = 0,
    CASettingsEnvironmentRowRootMode,
    CASettingsEnvironmentRowLauncher,
    CASettingsEnvironmentRowPaths,
    CASettingsEnvironmentRowPython,
    CASettingsEnvironmentRowTheos,
    CASettingsEnvironmentRowCount,
};

@interface CASettingsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) UISwitch *thirdPartySourceSwitch;
@property (nonatomic, strong, nullable) UISwitch *appServerChatSwitch;
@property (nonatomic, strong, nullable) UISwitch *mcpSwitch;
@property (nonatomic, copy, nullable) NSString *thirdPartySecretPlaceholder;

/// 运行时状态缓存（设置页展示用）
@property (nonatomic, assign) BOOL runtimeInstalled;
@property (nonatomic, copy, nullable) NSString *runtimeInstalledVersion;
@property (nonatomic, copy, nullable) NSString *runtimeCatalogVersion;
@property (nonatomic, copy, nullable) NSString *runtimeUpdateText;
@property (nonatomic, assign) BOOL runtimeInstalling;
@property (nonatomic, assign) double runtimeInstallFraction;

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

#pragma mark - 模型
- (NSString *)currentModelSlug;
- (NSArray<NSString *> *)catalogModelSlugs;
- (void)promptForCustomModel;
- (void)refreshModelCatalog;
- (void)modelCatalogDidChange:(NSNotification *)notification;
- (void)performClearThirdPartyConfiguration;

#pragma mark - 运行时
- (void)refreshRuntimeStatus;
- (void)checkRuntimeUpdate;
- (void)installOrRepairRuntime;
- (void)presentUpdateSheetForRuntimeID:(NSString *)runtimeID;
- (void)runtimeInstallDidFinish:(NSNotification *)notification;

#pragma mark - MCP
- (void)mcpSwitchChanged:(UISwitch *)sender;
- (BOOL)ensureInternalMCPSectionEnabled:(BOOL)enabled error:(NSError **)error;

#pragma mark - 环境
- (void)showEnvironmentDetails;
- (void)showKeyPaths;
- (void)showStandaloneEnvironmentForRuntime:(NSString *)runtimeID;

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
    [self refreshRuntimeStatus];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeCatalogChanged:)
                                                 name:CARuntimeCatalogDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountCredentialsDidChange)
                                                 name:@"CAAccountCredentialsDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(modelCatalogDidChange:)
                                                 name:CAModelPricingDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeInstallDidFinish:)
                                                 name:@"CARuntimeInstallDidFinish"
                                               object:nil];

    CALog(CALogLevelInfo, @"GENERAL", @"settings view loaded");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshLoginStatus];
    [self refreshRuntimeStatus];
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

- (id)effectiveThirdPartyKeyDraft
{
    NSString *draft = [self trimmedString:self.thirdPartyDraftKey];
    if (draft.length) return draft;
    return [[CAProviderConfiguration sharedConfiguration] readAPIKeyWithError:NULL] ?: @"";
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
    [self showMessage:[NSString stringWithFormat:@"配置已保存\nbase_url: %@\nmodel: %@\n密钥：%@",
                       [defaults stringForKey:CADefaultsAPIBaseURL] ?: @"(未设置)",
                       model.length ? model : @"(未变更)",
                       [[CACodexEngine sharedEngine] hasThirdPartyAPIKey] ? @"已保存" : @"未保存"]
                title:@"Provider"];
    if (self.onSettingsChanged) self.onSettingsChanged();
}

- (void)testThirdPartyConnection
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *base = [self trimmedString:self.thirdPartyDraftBaseURL];
    if (!base.length) base = [defaults stringForKey:CADefaultsAPIBaseURL];
    NSString *modelsURL = [CAProviderConfiguration modelsURLForBaseURL:base];
    if (!modelsURL.length) {
        [self showMessage:@"请先填写 Base URL（例如 https://api.example.com/v1）" title:@"连接测试"];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:modelsURL]];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 15.0;
    [request setValue:CAUserAgent forHTTPHeaderField:@"User-Agent"];
    NSString *key = [self effectiveThirdPartyKeyDraft];
    if (key.length) [request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];

    CALog(CALogLevelInfo, @"GENERAL", @"provider connection test url=%@ hasKey=%d", modelsURL, key.length > 0 ? 1 : 0);
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = http ? http.statusCode : 0;
        NSString *message = nil;
        if (error) {
            message = [NSString stringWithFormat:@"请求失败：%@", error.localizedDescription ?: @"网络错误"];
        } else if (status >= 200 && status < 300) {
            message = [NSString stringWithFormat:@"HTTP %ld · 连接可用\n%@", (long)status, modelsURL];
        } else if (status == 401 || status == 403) {
            message = [NSString stringWithFormat:@"HTTP %ld · 鉴权失败（检查 api_key）\n%@", (long)status, modelsURL];
        } else {
            message = [NSString stringWithFormat:@"HTTP %ld · 路径可能不正确（期望 <base>/models）\n%@", (long)status, modelsURL];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf showMessage:message title:@"连接测试"];
        });
    }];
    [task resume];
}

- (void)clearThirdPartyConfiguration
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清除 provider 配置"
                                                                  message:@"将删除本机保存的 provider 密钥，并清空 base_url / model 草稿"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf performClearThirdPartyConfiguration];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performClearThirdPartyConfiguration
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    CAProviderConfiguration *configuration = [CAProviderConfiguration sharedConfiguration];

    NSError *engineError = nil;
    if (![[CACodexEngine sharedEngine] saveThirdPartyAPIKey:@"" error:&engineError]) {
        CALog(CALogLevelWarn, @"GENERAL", @"clear provider key failed: %@", engineError);
    }
    NSError *removeError = nil;
    if (configuration.keyPath.length && [NSFileManager.defaultManager fileExistsAtPath:configuration.keyPath]) {
        [NSFileManager.defaultManager removeItemAtPath:configuration.keyPath error:&removeError];
    }
    [CAProviderConfiguration removeLegacyKeychainCredential];

    [defaults removeObjectForKey:CADefaultsThirdPartyProviderName];
    [defaults removeObjectForKey:CADefaultsAPIBaseURL];
    [defaults removeObjectForKey:CADefaultsSelectedModel];
    [defaults removeObjectForKey:CADefaultsThirdPartyModel];
    [defaults removeObjectForKey:CADefaultsThirdPartyAvailable];
    [defaults setBool:NO forKey:CADefaultsUseThirdPartyProvider];

    self.thirdPartyDraftKey = @"";
    self.thirdPartyDraftModel = @"";
    self.thirdPartyDraftName = @"Custom";
    self.thirdPartyDraftBaseURL = @"";
    self.thirdPartySecretPlaceholder = @"已清除，重新输入以保存";
    self.thirdPartySourceSwitch.on = NO;

    [self.tableView reloadData];
    [self showMessage:removeError ? [NSString stringWithFormat:@"密钥文件删除失败：%@", removeError.localizedDescription]
                                  : @"provider 配置与密钥已清除"
                title:@"Provider"];
    CALog(CALogLevelInfo, @"GENERAL", @"provider configuration cleared");
    if (self.onSettingsChanged) self.onSettingsChanged();
}

#pragma mark - 模型

- (NSString *)currentModelSlug
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *slug = [defaults stringForKey:CADefaultsSelectedModel];
    if (!slug.length) slug = [defaults stringForKey:CADefaultsThirdPartyModel];
    if (!slug.length) slug = [self trimmedString:self.thirdPartyDraftModel];
    if (!slug.length) slug = [defaults stringForKey:CADefaultsActiveModelSlug];
    return slug ?: @"";
}

- (NSArray<NSString *> *)catalogModelSlugs
{
    NSMutableOrderedSet<NSString *> *slugs = [NSMutableOrderedSet orderedSet];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    id available = [defaults objectForKey:CADefaultsThirdPartyAvailable];
    if ([available isKindOfClass:NSArray.class]) {
        for (id slug in (NSArray *)available) {
            if ([slug isKindOfClass:NSString.class] && [(NSString *)slug length] > 0) [slugs addObject:slug];
        }
    }
    for (NSString *slug in [CACodexEngine sharedEngine].thirdPartyAvailableModels) {
        if ([slug isKindOfClass:NSString.class] && slug.length > 0) [slugs addObject:slug];
    }
    NSDictionary<NSString *, NSDictionary *> *prices = [CAModelPricingManager sharedManager].prices;
    for (NSString *slug in prices.allKeys) {
        if (slug.length > 0) [slugs addObject:slug];
    }
    NSString *current = [self currentModelSlug];
    if (current.length) [slugs addObject:current];
    if ([defaults stringForKey:CADefaultsThirdPartyModel].length) [slugs addObject:[defaults stringForKey:CADefaultsThirdPartyModel]];

    return [slugs.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (bool)applyThirdPartyModelSelection:(id)arg1
{
    NSString *slug = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : [arg1 description];
    slug = [self trimmedString:slug];
    if (!slug.length) {
        [self showMessage:@"模型名不能为空" title:@"模型"];
        return NO;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSInteger storedContext = [defaults integerForKey:CADefaultsThirdPartyContextWindow];
    NSUInteger contextWindow = storedContext > 0 ? (NSUInteger)storedContext : (NSUInteger)272000;

    [defaults setObject:slug forKey:CADefaultsSelectedModel];
    [defaults setObject:slug forKey:CADefaultsThirdPartyModel];
    [defaults setObject:slug forKey:CADefaultsActiveModelSlug];
    self.thirdPartyDraftModel = slug;

    NSDictionary *info = [CAThirdPartyModelCatalog modelInfoForSlug:slug
                                                       instructions:[CAThirdPartyModelCatalog fallbackInstructions]
                                                      contextWindow:contextWindow
                                                           priority:0
                                                           enhanced:NO];
    NSError *catalogError = nil;
    BOOL wroteCatalog = [CAThirdPartyModelCatalog writeCatalogForModels:info ? @[ info ] : @[]
                                                           selectedModel:slug
                                                           contextWindow:contextWindow
                                                                   error:&catalogError];
    [CACodexEngine sharedEngine].thirdPartyModel = slug;
    if (!wroteCatalog) {
        CALog(CALogLevelWarn, @"GENERAL", @"model catalog write failed: %@", catalogError.localizedDescription ?: @"(unknown)");
    }

    CALog(CALogLevelInfo, @"GENERAL", @"model switched slug=%@ catalog=%d", slug, wroteCatalog);
    [self.tableView reloadData];
    [self showMessage:wroteCatalog
                        ? [NSString stringWithFormat:@"已切换模型：%@\n上下文窗口：%lu tokens", slug, (unsigned long)contextWindow]
                        : [NSString stringWithFormat:@"已切换到 %@，但 model_catalog_json 写入失败：%@", slug, catalogError.localizedDescription ?: @"未知错误"]
                title:@"模型"];
    if (self.onSettingsChanged) self.onSettingsChanged();
    return wroteCatalog ? YES : NO;
}

- (void)presentThirdPartyModelPicker:(id)arg1
{
    NSArray<NSString *> *slugs = [self catalogModelSlugs];
    NSString *current = [self currentModelSlug];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择模型"
                                                                  message:[NSString stringWithFormat:@"候选 %lu 个 · 当前 %@",
                                                                           (unsigned long)slugs.count,
                                                                           current.length ? current : @"(未设置)"]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    NSUInteger limit = 20;
    NSUInteger shown = 0;
    for (NSString *slug in slugs) {
        if (shown >= limit) break;
        shown += 1;
        NSString *title = [slug isEqualToString:current] ? [NSString stringWithFormat:@"✓ %@", slug] : slug;
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf applyThirdPartyModelSelection:slug];
        }]];
    }
    if (slugs.count > limit) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"其余 %lu 个请在模型输入框填写", (unsigned long)(slugs.count - limit)]
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [self promptForCustomModel];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动输入模型名…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptForCustomModel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"刷新模型目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self refreshModelCatalog];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = self.tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForCustomModel
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"输入模型名"
                                                                  message:@"例如 gpt-5-codex / claude-sonnet-4"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"model slug";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.text = self.thirdPartyDraftModel;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf applyThirdPartyModelSelection:alert.textFields.firstObject.text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshModelCatalog
{
    __weak typeof(self) weakSelf = self;
    [[CAModelPricingManager sharedManager] refreshCatalogWithCompletion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.tableView reloadData];
            NSString *message = error
                ? [NSString stringWithFormat:@"模型目录刷新失败：%@", error.localizedDescription ?: @"网络错误"]
                : [NSString stringWithFormat:@"模型目录已刷新：%lu 个模型", (unsigned long)[CAModelPricingManager sharedManager].modelCount];
            [strongSelf showMessage:message title:@"模型目录"];
        });
    }];
}

- (void)handleSelectReasoningEffort
{
    NSArray<NSString *> *levels = [CAThirdPartyModelCatalog reasoningLevels];
    if (!levels.count) levels = @[ @"minimal", @"low", @"medium", @"high" ];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *current = [defaults stringForKey:CADefaultsThirdPartyReasoning] ?: @"medium";

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"推理强度"
                                                                  message:[NSString stringWithFormat:@"当前：%@", current]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *level in levels) {
        NSString *title = [CAThirdPartyModelCatalog reasoningLevelTitle:level];
        if (title.length && ![title isEqualToString:level]) {
            title = [NSString stringWithFormat:@"%@（%@）", title, level];
        }
        if ([level isEqualToString:current]) title = [NSString stringWithFormat:@"✓ %@", title ?: level];
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title ?: level style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSUserDefaults *inner = NSUserDefaults.standardUserDefaults;
            [inner setObject:level forKey:CADefaultsThirdPartyReasoning];
            [inner setObject:level forKey:CADefaultsReasoningEffort];
            [inner setObject:level forKey:CADefaultsActiveEffort];
            [CACodexEngine sharedEngine].reasoningEffort = level;
            CALog(CALogLevelInfo, @"GENERAL", @"reasoning effort switched level=%@", level);
            [strongSelf.tableView reloadData];
            [strongSelf showMessage:[NSString stringWithFormat:@"推理强度：%@", level] title:@"模型"];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = self.tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)modelCatalogDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - 运行时

- (void)refreshRuntimeStatus
{
    CARuntimeCatalog *catalog = [CARuntimeCatalog sharedCatalog];
    CARuntimeCatalogEntry *entry = [catalog entryForID:@"codex"];
    self.runtimeInstalled = [CAUpdateViewController isRuntimeInstalled:@"codex"];
    self.runtimeInstalledVersion = [CAUpdateViewController installedVersionForRuntimeID:@"codex"];
    self.runtimeCatalogVersion = entry.version;

    if (!self.runtimeInstalled) {
        self.runtimeUpdateText = self.runtimeCatalogVersion.length
            ? [NSString stringWithFormat:@"未安装，可安装 v%@", self.runtimeCatalogVersion]
            : @"未安装（清单尚未刷新）";
    } else if (self.runtimeCatalogVersion.length &&
               ![self.runtimeCatalogVersion isEqualToString:self.runtimeInstalledVersion ?: @""]) {
        self.runtimeUpdateText = [NSString stringWithFormat:@"可更新：%@ → %@",
                                  self.runtimeInstalledVersion ?: @"?", self.runtimeCatalogVersion];
    } else {
        self.runtimeUpdateText = @"已是最新";
    }
}

- (void)checkRuntimeUpdate
{
    __weak typeof(self) weakSelf = self;
    [[CARuntimeCatalog sharedCatalog] refreshNowWithCompletion:^(BOOL ok, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf refreshRuntimeStatus];
            [strongSelf.tableView reloadData];
            NSString *message = ok
                ? [NSString stringWithFormat:@"清单条目 %lu 项\n清单版本：%@\n%@",
                   (unsigned long)[CARuntimeCatalog sharedCatalog].entries.count,
                   strongSelf.runtimeCatalogVersion ?: @"(未获取)",
                   strongSelf.runtimeUpdateText ?: @""]
                : [NSString stringWithFormat:@"清单刷新失败：%@", error.localizedDescription ?: @"网络错误"];
            [strongSelf showMessage:message title:@"检查更新"];
        });
    }];
}

- (void)installOrRepairRuntime
{
    [self presentUpdateSheetForRuntimeID:@"codex"];
}

- (void)presentUpdateSheetForRuntimeID:(NSString *)runtimeID
{
    if (!runtimeID.length) return;
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];
    if (!entry || !entry.archiveURL.length) {
        [self showMessage:[NSString stringWithFormat:@"运行时清单里没有 %@（请先“检查更新”刷新清单）", runtimeID] title:@"运行时"];
        return;
    }

    CAUpdateViewController *controller = [[CAUpdateViewController alloc] initWithRuntimeID:runtimeID version:entry.version];
    __weak typeof(self) weakSelf = self;
    controller.finishHandler = ^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf refreshRuntimeStatus];
            [strongSelf.tableView reloadData];
            CALog(success ? CALogLevelInfo : CALogLevelWarn, @"RUNTIME",
                  @"settings runtime install finished runtime=%@ success=%d message=%@",
                  runtimeID, success, message ?: @"");
        });
    };

    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)runtimeInstallDidFinish:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshRuntimeStatus];
        [self.tableView reloadData];
    });
}

- (id)formattedByteCount:(unsigned long long)arg1
{
    if (arg1 == 0) return @"—";
    return [NSByteCountFormatter stringFromByteCount:(long long)arg1 countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)showInstalledCLIVersion
{
    NSString *root = [CARuntimePaths runtimeRootForID:@"codex"];
    NSString *manifestPath = [CARuntimePaths installedManifestPathForRuntimeID:@"codex"];
    NSString *executable = [[CACodexEngine sharedEngine] resolveCodexExecutable] ?: @"(未解析)";
    unsigned long long size = [[CAStorageManager sharedManager] directorySizeAtPath:root];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"codex 运行时"
        message:[NSString stringWithFormat:@"安装状态：%@\n已安装版本：%@\n清单版本：%@\n安装根目录：%@\n安装记录：%@\ncodex 可执行：%@\n占用空间：%@\n%@",
                 self.runtimeInstalled ? @"已安装" : @"未安装",
                 self.runtimeInstalledVersion ?: @"(无)",
                 self.runtimeCatalogVersion ?: @"(未获取)",
                 root,
                 manifestPath,
                 executable,
                 [self formattedByteCount:size],
                 self.runtimeUpdateText ?: @""]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"下载安装/修复" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self installOrRepairRuntime];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - MCP

- (BOOL)ensureInternalMCPSectionEnabled:(BOOL)enabled error:(NSError **)error
{
    NSString *path = [CARuntimePaths configTOMLPath];
    NSString *existing = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    NSString *header = [NSString stringWithFormat:@"[mcp_servers.%@]", kSettingsInternalMCPName];
    if ([existing containsString:header]) return YES;

    NSMutableString *text = [NSMutableString stringWithString:existing];
    if (text.length && ![text hasSuffix:@"\n"]) [text appendString:@"\n"];
    [text appendFormat:@"\n%@\nenabled = %@\nurl = \"http://%@:%u%@\"\n",
     header,
     enabled ? @"true" : @"false",
     CAInternalMCPHost,
     (unsigned)CAInternalMCPPort,
     CAInternalMCPPath];

    NSError *writeError = nil;
    BOOL ok = [[text dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path options:NSDataWritingAtomic error:&writeError];
    if (!ok && error) *error = writeError;
    CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"MCP", @"internal MCP section write ok=%d path=%@ enabled=%d",
          ok, path, enabled ? 1 : 0);
    return ok;
}

- (void)mcpSwitchChanged:(UISwitch *)sender
{
    BOOL enabled = sender.isOn;
    CAMCPBridge *bridge = [CAMCPBridge sharedBridge];
    NSError *startError = nil;

    if (enabled && !bridge.running) {
        if (![bridge startOnPort:CAInternalMCPPort error:&startError]) {
            bridge.reportedInternalMCPTransportFailure = YES;
            sender.on = NO;
            [self.tableView reloadData];
            CALog(CALogLevelError, @"MCP", @"settings toggle start failed: %@", startError);
            [self showMessage:[NSString stringWithFormat:@"MCP 桥启动失败：%@", startError.localizedDescription ?: @"端口被占用"]
                        title:@"MCP"];
            return;
        }
    } else if (!enabled && bridge.running) {
        [bridge stop];
        CALog(CALogLevelInfo, @"MCP", @"internal MCP bridge stopped from settings");
    }

    NSError *sectionError = nil;
    if (![self ensureInternalMCPSectionEnabled:enabled error:&sectionError]) {
        CALog(CALogLevelWarn, @"MCP", @"internal MCP section ensure failed: %@", sectionError);
    }

    CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindMCP
                                                          identifier:[NSString stringWithFormat:@"mcp:%@", kSettingsInternalMCPName]];
    item.name = kSettingsInternalMCPName;
    item.enabled = enabled;

    __weak typeof(self) weakSelf = self;
    [[CAComposerCatalog sharedCatalog] setMCPServer:item enabled:enabled completion:^(BOOL ok, NSError *completionError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.tableView reloadData];
            if (ok) {
                [strongSelf showMessage:[NSString stringWithFormat:@"MCP 桥已%@\n端点 %@\n配置 %@",
                                         enabled ? @"开启" : @"关闭",
                                         CAInternalMCPURLString,
                                         [CARuntimePaths configTOMLPath]]
                                  title:@"MCP"];
            } else {
                [strongSelf showMessage:[NSString stringWithFormat:@"桥已%@，但 config.toml 写入失败：%@",
                                         enabled ? @"开启" : @"关闭",
                                         completionError.localizedDescription ?: @"未知错误"]
                                  title:@"MCP"];
            }
        });
    }];
}

#pragma mark - 环境

- (void)showEnvironmentDetails
{
    CAExecutionEnvironment *environment = [CAExecutionEnvironment sharedEnvironment];
    [environment refresh];
    CAExecutionEnvironmentProfile *profile = environment.profile;

    NSString *message = [NSString stringWithFormat:
        @"环境类型：%@\n越狱证据：%@\nTrollStore：%@\nRoot 模式：%@（%ld）\n家族 / 品牌：%@ / %@\n启动器：%@ (%@)\nTrollStore 形态：%@\nshell：%@ · %@\n审计：%@\n证据：%@",
        environment.runtimeEnvironmentKind ?: profile.environmentKind ?: @"unknown",
        environment.runtimeHasJailbreakEvidence ? @"有" : @"无",
        environment.runtimeHasTrollStore ? @"有" : @"无",
        profile.rootModeString ?: @"unknown",
        (long)environment.runtimeRootMode,
        environment.runtimeJailbreakFamily ?: profile.familyName ?: @"none",
        environment.runtimeJailbreakBrand ?: profile.brandName ?: @"none",
        environment.runtimeJailbreakLauncher ?: profile.launcherDisplayName ?: @"none",
        environment.runtimeJailbreakLauncherBundle ?: profile.launcherBundleId ?: @"none",
        environment.runtimeTrollStoreFlavor ?: profile.trollStoreFlavor ?: @"none",
        environment.shellExecutable ?: @"(未解析)",
        environment.shellSpawnMode ?: @"(未知)",
        environment.runtimeEnvironmentEvidence ?: profile.evidenceSummary ?: @"",
        profile.hasTrollStore ? @"TrollStore 导入" : (profile.hasJailbreakEvidence ? @"越狱侧载" : @"standalone")];
    [self showMessage:message title:@"运行环境"];
}

- (void)showKeyPaths
{
    NSString *message = [NSString stringWithFormat:
        @"support：%@\ncodexHome：%@\nconfig.toml：%@\n密钥文件：%@\n运行时目录：%@\n日志：%@\n下载缓存：%@\ntmp：%@",
        CARuntimePaths.supportDirectory,
        CARuntimePaths.codexHome,
        CARuntimePaths.configTOMLPath,
        [CAProviderConfiguration sharedConfiguration].keyPath,
        [CARuntimePaths runtimeRootForID:@"codex"],
        CARuntimePaths.logsDirectory,
        CARuntimePaths.runtimeDownloadsDirectory,
        CARuntimePaths.tmpDirectory];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关键路径" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = message;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showStandaloneEnvironmentForRuntime:(NSString *)runtimeID
{
    NSString *root = [CARuntimePaths runtimeRootForID:runtimeID];
    NSString *installedVersion = [CAUpdateViewController installedVersionForRuntimeID:runtimeID];
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:runtimeID];
    BOOL installed = [CAUpdateViewController isRuntimeInstalled:runtimeID];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ 运行时", runtimeID]
        message:[NSString stringWithFormat:@"状态：%@\n已安装版本：%@\n清单版本：%@\n根目录：%@\n占用空间：%@",
                 installed ? @"已安装" : @"未安装",
                 installedVersion ?: @"(无)",
                 entry.version ?: @"(未获取)",
                 root,
                 [self formattedByteCount:[[CAStorageManager sharedManager] directorySizeAtPath:root]]]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:installed ? @"重新安装/修复" : @"下载安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentUpdateSheetForRuntimeID:runtimeID];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showPythonEnvironment
{
    [self showStandaloneEnvironmentForRuntime:@"python"];
}

- (void)showTheosEnvironment
{
    [self showStandaloneEnvironmentForRuntime:@"theos"];
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
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshRuntimeStatus];
            [self.tableView reloadData];
        });
    }];
}

- (void)showRuntimeToolEntry:(CARuntimeCatalogEntry *)entry installed:(BOOL)installed root:(NSString *)root
{
    NSString *message = [NSString stringWithFormat:@"ID：%@\n版本：%@\n状态：%@\n大小：%@\n安装根：%@\n摘要：%@",
                         entry.runtimeID ?: @"?",
                         entry.version ?: @"?",
                         installed ? @"已安装" : @"未安装",
                         [self formattedByteCount:entry.expandedSize],
                         root ?: @"(未知)",
                         entry.summary ?: @"(无)"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:entry.displayName ?: entry.runtimeID ?: @"运行时"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    if (entry.runtimeID.length && entry.archiveURL.length) {
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:installed ? @"重新安装/修复" : @"下载安装"
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            [weakSelf presentUpdateSheetForRuntimeID:entry.runtimeID];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
        [self refreshRuntimeStatus];
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
        case CASettingsSectionModel:
            return CASettingsModelRowCount;
        case CASettingsSectionRuntime:
            return CASettingsRuntimeRowCount;
        case CASettingsSectionMCP:
            return CASettingsMCPRowCount;
        case CASettingsSectionDiagnostics:
            return CASettingsDiagnosticsRowCount;
        case CASettingsSectionEnvironment:
            return CASettingsEnvironmentRowCount;
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
            if (indexPath.row == CASettingsProviderRowTest) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.imageView.image = nil;
                cell.textLabel.text = @"测试连接";
                cell.textLabel.textColor = self.view.tintColor;
                cell.detailTextLabel.text = @"GET <base>/models";
                cell.accessoryView = nil;
                return cell;
            }
            if (indexPath.row == CASettingsProviderRowClear) {
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
                cell.imageView.image = nil;
                cell.textLabel.text = @"清除密钥与配置";
                cell.textLabel.textColor = UIColor.systemRedColor;
                cell.detailTextLabel.text = [[CACodexEngine sharedEngine] hasThirdPartyAPIKey] ? @"已保存" : @"未保存";
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

        case CASettingsSectionModel: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.imageView.image = nil;
            cell.accessoryView = nil;
            NSString *current = [self currentModelSlug];
            switch ((CASettingsModelRow)indexPath.row) {
                case CASettingsModelRowCurrent:
                    cell.textLabel.text = @"当前模型";
                    cell.detailTextLabel.text = current.length ? current : @"(未设置)";
                    cell.accessoryType = UITableViewCellAccessoryNone;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    break;
                case CASettingsModelRowSelect:
                    cell.textLabel.text = @"选择模型";
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"候选 %lu 个",
                                                 (unsigned long)[self catalogModelSlugs].count];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case CASettingsModelRowReasoning:
                    cell.textLabel.text = @"推理强度";
                    cell.detailTextLabel.text = [defaults stringForKey:CADefaultsThirdPartyReasoning] ?: @"medium";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case CASettingsModelRowCatalog:
                default:
                    cell.textLabel.text = @"模型价格目录";
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 个模型 · %@",
                                                 (unsigned long)[CAModelPricingManager sharedManager].modelCount,
                                                 [CAModelPricingManager sharedManager].lastUpdatedAt ? @"已缓存" : @"未刷新"];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
            }
            return cell;
        }

        case CASettingsSectionRuntime: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.imageView.image = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            switch ((CASettingsRuntimeRow)indexPath.row) {
                case CASettingsRuntimeRowVersion: {
                    cell.textLabel.text = @"codex 运行时";
                    cell.detailTextLabel.text = self.runtimeInstalled
                        ? [NSString stringWithFormat:@"已安装 %@", self.runtimeInstalledVersion ?: @"(版本未知)"]
                        : @"未安装";
                    break;
                }
                case CASettingsRuntimeRowCheckUpdate:
                    cell.textLabel.text = @"检查更新";
                    cell.detailTextLabel.text = self.runtimeUpdateText ?: @"对比运行时清单";
                    break;
                case CASettingsRuntimeRowInstall:
                    cell.textLabel.text = @"下载安装 / 修复";
                    cell.textLabel.textColor = self.view.tintColor;
                    cell.detailTextLabel.text = self.runtimeInstalling
                        ? [NSString stringWithFormat:@"安装中 %d%%", (int)(self.runtimeInstallFraction * 100.0)]
                        : (self.runtimeInstalled ? @"重新安装或修复" : @"从清单下载并安装");
                    break;
                case CASettingsRuntimeRowManager: {
                    cell.textLabel.text = @"运行时管理";
                    cell.textLabel.textColor = UIColor.labelColor;
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

        case CASettingsSectionMCP: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.imageView.image = nil;
            CAMCPBridge *bridge = [CAMCPBridge sharedBridge];
            switch ((CASettingsMCPRow)indexPath.row) {
                case CASettingsMCPRowToggle: {
                    cell.textLabel.text = @"内部 MCP 桥";
                    cell.detailTextLabel.text = @"";
                    UISwitch *toggle = [[UISwitch alloc] init];
                    toggle.on = bridge.running;
                    [toggle addTarget:self action:@selector(mcpSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                    cell.accessoryView = toggle;
                    self.mcpSwitch = toggle;
                    cell.accessoryType = UITableViewCellAccessoryNone;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    return cell;
                }
                case CASettingsMCPRowStatus:
                    cell.textLabel.text = @"状态";
                    cell.detailTextLabel.text = bridge.running
                        ? [NSString stringWithFormat:@"运行中 · %@", CAInternalMCPURLString]
                        : @"未运行";
                    cell.accessoryType = UITableViewCellAccessoryNone;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    break;
                case CASettingsMCPRowConfig:
                default:
                    cell.textLabel.text = @"config.toml";
                    cell.detailTextLabel.text = [NSString stringWithFormat:@"mcp_servers.%@", kSettingsInternalMCPName];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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

        case CASettingsSectionEnvironment: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSettingsCellReuseIdentifier forIndexPath:indexPath];
            cell.imageView.image = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            CAExecutionEnvironmentProfile *profile = [CAExecutionEnvironment sharedEnvironment].profile;
            switch ((CASettingsEnvironmentRow)indexPath.row) {
                case CASettingsEnvironmentRowSummary:
                    cell.textLabel.text = @"运行环境";
                    cell.detailTextLabel.text = profile.environmentKind ?: @"unknown";
                    break;
                case CASettingsEnvironmentRowRootMode:
                    cell.textLabel.text = @"Root 模式";
                    cell.detailTextLabel.text = profile.rootModeString ?: @"unknown";
                    break;
                case CASettingsEnvironmentRowLauncher:
                    cell.textLabel.text = @"启动器";
                    cell.detailTextLabel.text = profile.launcherDisplayName ?: @"none";
                    break;
                case CASettingsEnvironmentRowPaths:
                    cell.textLabel.text = @"关键路径";
                    cell.detailTextLabel.text = CARuntimePaths.supportDirectory;
                    break;
                case CASettingsEnvironmentRowPython:
                    cell.textLabel.text = @"Python 运行时";
                    cell.detailTextLabel.text = [CAUpdateViewController installedVersionForRuntimeID:@"python"] ?: @"未安装";
                    break;
                case CASettingsEnvironmentRowTheos:
                default:
                    cell.textLabel.text = @"Theos 运行时";
                    cell.detailTextLabel.text = [CAUpdateViewController installedVersionForRuntimeID:@"theos"] ?: @"未安装";
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
        case CASettingsSectionModel:       return @"模型";
        case CASettingsSectionRuntime:     return @"Codex Runtime";
        case CASettingsSectionMCP:         return @"MCP 桥";
        case CASettingsSectionDiagnostics: return @"日志与诊断";
        case CASettingsSectionEnvironment: return @"环境";
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
    if ((CASettingsSection)section == CASettingsSectionRuntime) {
        return [NSString stringWithFormat:@"安装目录 %@（确认含 bin/codex 才算安装成功）。",
                [CARuntimePaths runtimeRootForID:@"codex"]];
    }
    if ((CASettingsSection)section == CASettingsSectionMCP) {
        return [NSString stringWithFormat:@"开关会启停 %@ 并把 [mcp_servers.%@] 写回 %@。",
                CAInternalMCPURLString, kSettingsInternalMCPName, [CARuntimePaths configTOMLPath]];
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
            switch ((CASettingsProviderRow)indexPath.row) {
                case CASettingsProviderRowSave:  [self saveThirdPartyConfiguration]; break;
                case CASettingsProviderRowTest:  [self testThirdPartyConnection]; break;
                case CASettingsProviderRowClear: [self clearThirdPartyConfiguration]; break;
                case CASettingsProviderRowModel: [self presentThirdPartyModelPicker:indexPath]; break;
                case CASettingsProviderRowReasoning: [self handleSelectReasoningEffort]; break;
                default: break;
            }
            return;
        }

        case CASettingsSectionModel: {
            switch ((CASettingsModelRow)indexPath.row) {
                case CASettingsModelRowSelect:    [self presentThirdPartyModelPicker:indexPath]; break;
                case CASettingsModelRowReasoning: [self handleSelectReasoningEffort]; break;
                case CASettingsModelRowCatalog:   [self refreshModelCatalog]; break;
                case CASettingsModelRowCurrent:
                default: break;
            }
            return;
        }

        case CASettingsSectionRuntime: {
            switch ((CASettingsRuntimeRow)indexPath.row) {
                case CASettingsRuntimeRowVersion:     [self showInstalledCLIVersion]; break;
                case CASettingsRuntimeRowCheckUpdate: [self checkRuntimeUpdate]; break;
                case CASettingsRuntimeRowInstall:     [self installOrRepairRuntime]; break;
                case CASettingsRuntimeRowManager:     [self showRuntimeManager]; break;
                case CASettingsRuntimeRowRefresh:     [self refreshRuntimeCatalog]; break;
                case CASettingsRuntimeRowClearCache:
                    [[CAStorageManager sharedManager] clearRuntimeDownloadCaches];
                    [self showMessage:@"下载缓存已清理" title:@"运行时"];
                    break;
            }
            return;
        }

        case CASettingsSectionMCP: {
            if ((CASettingsMCPRow)indexPath.row == CASettingsMCPRowConfig) {
                NSString *path = [CARuntimePaths configTOMLPath];
                NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"config.toml"
                    message:text.length ? text : [NSString stringWithFormat:@"文件不存在或为空：%@", path]
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    UIPasteboard.generalPasteboard.string = path;
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
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

        case CASettingsSectionEnvironment: {
            switch ((CASettingsEnvironmentRow)indexPath.row) {
                case CASettingsEnvironmentRowSummary:
                case CASettingsEnvironmentRowRootMode:
                case CASettingsEnvironmentRowLauncher:
                    [self showEnvironmentDetails];
                    break;
                case CASettingsEnvironmentRowPaths:
                    [self showKeyPaths];
                    break;
                case CASettingsEnvironmentRowPython:
                    [self showPythonEnvironment];
                    break;
                case CASettingsEnvironmentRowTheos:
                    [self showTheosEnvironment];
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
