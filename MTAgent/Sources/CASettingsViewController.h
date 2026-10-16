//
//  CASettingsViewController.h — 设置页（账号 / Provider / 运行时 / 日志与诊断）
//
//  原包符号对齐：-secretFieldChanged:、-handleAPIKeyLogin、-handleAccessTokenLogin、
//  -handleDeviceAuthLogin、-handleBrowserOAuthLogin、-handleLogout、
//  isLoggedIn / loginStatusText / loginOptionsExpanded / loginAttemptGeneration / loginTask
//

#import <UIKit/UIKit.h>
#import "CAProcess.h"

@class CAProcess;

NS_ASSUME_NONNULL_BEGIN


// ==PARITY-FORWARD-DECLS-BEGIN==
@class CAAccountProfile, CACodexEngine;
// ==PARITY-FORWARD-DECLS-END==

@interface CASettingsViewController : UIViewController

#pragma mark - 登录态

@property (nonatomic, assign) BOOL isLoggedIn;
@property (nonatomic, copy, nullable) NSString *loginStatusText;
@property (nonatomic, assign) BOOL loginOptionsExpanded;
@property (nonatomic, assign) NSUInteger loginAttemptGeneration;
@property (nonatomic, strong, nullable) CAProcess *loginTask;

/// 设置变更回调（原包 ivar: _onSettingsChanged）
@property (nonatomic, copy, nullable) void (^onSettingsChanged)(void);

#pragma mark - 第三方 provider 草稿（原包 ivar: _thirdPartyDraft*）

@property (nonatomic, assign) BOOL thirdPartyExpanded;
@property (nonatomic, copy, nullable) NSString *thirdPartyDraftName;
@property (nonatomic, copy, nullable) NSString *thirdPartyDraftBaseURL;
@property (nonatomic, copy, nullable) NSString *thirdPartyDraftModel;
@property (nonatomic, copy, nullable) NSString *thirdPartyDraftKey;

#pragma mark - Provider

/// 密钥输入变化（原包同名选择器）
- (void)secretFieldChanged:(UITextField *)sender;

/// 其它 provider 字段变化（原包同名选择器）
- (void)thirdPartyFieldChanged:(UITextField *)sender;

- (void)saveThirdPartyConfiguration;

#pragma mark - 登录入口

- (void)handleAPIKeyLogin;
- (void)handleAccessTokenLogin;
- (void)handleDeviceAuthLogin;
- (void)handleBrowserOAuthLogin;
- (void)handleLogout;
- (void)refreshLoginStatus;

#pragma mark - 子页面入口

- (void)showRuntimeManager;
- (void)showLogViewer;
- (void)showDiagnostics;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSString * accountIdentity;
    @property (nonatomic, strong, nullable) UILabel * avatarInitialLabel;
    @property (nonatomic, strong, nullable) NSString * avatarRequestURL;
    @property (nonatomic, strong, nullable) UIImageView * avatarView;
    @property (nonatomic, assign) BOOL checkingCLIUpdate;
    @property (nonatomic, assign) BOOL checkingPythonUpdate;
    @property (nonatomic, strong, nullable) CACodexEngine * contextEngine;
    @property (nonatomic, strong, nullable) CAAccountProfile * currentProfile;
    @property (nonatomic, assign) BOOL dismissingSettings;
    @property (nonatomic, strong, nullable) NSString * displayUserName;
    @property (nonatomic, assign) BOOL focusRequiredRuntimesOnAppear;
    @property (nonatomic, strong, nullable) NSString * latestAvailableVersion;
    @property (nonatomic, assign) BOOL pendingSettingsChanged;
    @property (nonatomic, strong, nullable) UIView * profileCard;
    @property (nonatomic, strong, nullable) NSString * profileRefreshID;
    @property (nonatomic, assign) unsigned long long thirdPartyConnectionGeneration;
    @property (nonatomic, strong, nullable) NSString * thirdPartyDraftContext;
    @property (nonatomic, strong, nullable) NSString * thirdPartyDraftEffort;
    @property (nonatomic, strong, nullable) NSMapTable * thirdPartyFieldHosts;
    @property (nonatomic, strong, nullable) NSMutableDictionary * thirdPartyFields;
    @property (nonatomic, assign) unsigned long long thirdPartyModelsRequestGeneration;
    @property (nonatomic, assign) BOOL toolsExpanded;
    @property (nonatomic, strong, nullable) UILabel * userNameLabel;
    @property (nonatomic, strong, nullable) UILabel * userStatusLabel;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)applyCurrentTheme;
    - (id)applyThirdPartyModelSelection:(id)arg1;
    - (id)attachThirdPartyField:(id)arg1 toCell:(id)arg2;
    - (id)avatarTask;
    - (id)buildProfileHeader;
    - (id)captureThirdPartyFields;
    - (id)chatDisplayModeChanged:(id)arg1;
    - (id)checkCLIUpdateSilently;
    - (id)checkingReverseToolsUpdate;
    - (id)checkingTheosUpdate;
    - (id)clearThirdPartyConfiguration;
    - (id)codexRuntimeEnvironmentChanged;
    - (id)effectiveThirdPartyKeyDraft;
    - (id)fetchThirdPartyModels:(id)arg1;
    - (id)formattedByteCount:(id)arg1;
    - (id)handleEditAPIBaseURL;
    - (id)handleSelectReasoningEffort;
    - (id)handleSelectSandboxMode;
    - (id)loadProfileImageURL:(id)arg1;
    - (id)managedRuntimeEnvironmentChanged:(id)arg1;
    - (id)persistThirdPartyCredentials;
    - (id)presentThirdPartyModelPicker:(id)arg1;
    - (id)profileAvatarCache;
    - (id)profileHeader;
    - (id)refreshLoginStatusReloadTable:(id)arg1;
    - (id)reloadRuntimeToolID:(id)arg1 includeParent:(id)arg2;
    - (id)runtimeToolEntries;
    - (id)runtimeToolEntryForRow:(id)arg1;
    - (id)runtimeToolIndexPathForID:(id)arg1;
    - (id)runtimeToolRequiredMissingCount;
    - (id)runtimeToolUpdateCount;
    - (id)runtimeToolsChildStartRow;
    - (id)runtimeToolsTrailingStartRow;
    - (id)saveThirdPartyDraftsEnabling:(id)arg1;
    - (id)saveThirdPartyDraftsEnabling:(id)arg1 reloadSection:(id)arg2;
    - (id)selectThirdPartyEffort;
    - (id)setAvatarTask:(id)arg1;
    - (id)setCheckingReverseToolsUpdate:(id)arg1;
    - (id)setCheckingTheosUpdate:(id)arg1;
    - (id)setProfileHeader:(id)arg1;
    - (id)showInstalledCLIVersion;
    - (id)showPythonEnvironment;
    - (id)showReverseToolsEnvironment;
    - (id)showTheosEnvironment;
    - (id)testThirdPartyConnection;
    - (id)themeChanged;
    - (id)themeModeChanged:(id)arg1;
    - (id)theosRuntimeStatusText;
    - (id)thirdPartyFieldForTag:(id)arg1 placeholder:(id)arg2 text:(id)arg3;
    - (id)thirdPartyModelsURL;
    - (id)usernameFromStatus:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
