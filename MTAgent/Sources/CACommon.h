//
//  CACommon.h — MT Agent 复刻版共享常量（与原包观测值逐条对齐）
//  对应原二进制观测：Supabase/JWT/UA/端口/defaults 键/环境变量/路径
//

#import <Foundation/Foundation.h>

#pragma mark - Bundle 身份（与原包一致，勿改）

static NSString *const CABundleIdentifier      = @"wiki.qaq.codexapp";
static NSString *const CABundleIdentifierShare = @"wiki.qaq.codexapp.share";
static NSString *const CAAppGroupIdentifier    = @"group.wiki.qaq.codexapp";
static NSString *const CABundleDisplayName     = @"MT 智能体";
static NSString *const CABundleShortVersion    = @"1.0.2";
static NSString *const CABundleVersion         = @"3";
static NSString *const CAExecutableName        = @"CodexApp";
static NSString *const CAURLScheme             = @"mtagent";

#pragma mark - 远端契约（原包观测：CARemoteOperations）

static NSString *const CARemoteBaseURL         = @"https://bctwtbuvphdwbnlbprav.supabase.co";
static NSString *const CARemoteAnonKey         = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJjdHd0YnV2cGhkd2JubGJwcmF2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk3NTU5NjYsImV4cCI6MjA4NTMzMTk2Nn0.Mw4MkBJAnofnDm5Ylxe04pgjsQsloPSbzDNivBdVK-M";
static NSString *const CAPolicyPath            = @"/rest/v1/risk_control_config?id=eq.1&select=feature_flags,log_switches,max_heartbeat_fail_count,updated_at";
static NSString *const CAHeartbeatPath         = @"/rest/v1/heartbeats?on_conflict=anonymous_id";
static NSString *const CAUserAgent             = @"CodexApp/1.0";
static const NSTimeInterval CARemoteTimeout    = 12.0;
static NSString *const CAHeartbeatPrefer       = @"resolution=merge-duplicates,return=minimal";

#pragma mark - 上游目录 / 下载

static NSString *const CAUpdateOwner           = @"susu123oss";
static NSString *const CAUpdateRepo            = @"CodexApp-Runtime";
static NSString *const CARuntimeManifestURL    = @"https://raw.githubusercontent.com/susu123oss/CodexApp-Runtime/main/Runtime/runtime-manifest.json";
static NSString *const CAPricingModelsDevURL   = @"https://models.dev/catalog.json";
static NSString *const CAPricingLiteLLMURL     = @"https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";
static NSString *const CAPricingOpenRouterURL  = @"https://openrouter.ai/api/v1/models";
static NSString *const CARateUSDCNYURL         = @"https://api.frankfurter.dev/v2/rate/usd/cny";
static NSString *const CAGitHubTagAPIFormat    = @"https://api.github.com/repos/%@/%@/releases/tags/%@";
static NSString *const CAGitHubReleasesFormat  = @"https://api.github.com/repos/%@/%@/releases?per_page=50";
static NSString *const CAGitHubAssetFormat     = @"https://github.com/%@/%@/releases/download/%@/%@";
static NSString *const CAGitHubSumsFormat      = @"https://github.com/%@/%@/releases/download/%@/SHA256SUMS";
NSArray<NSString *> *CADownloadProxyPrefixes(void); // @[ @"https://gh-proxy.org/", @"https://ghproxy.net/" ]

#pragma mark - 本机内部 MCP 桥（原包观测：127.0.0.1:27018/mcp）

static NSString *const CAInternalMCPHost       = @"127.0.0.1";
static const uint16_t  CAInternalMCPPort       = 27018;
static NSString *const CAInternalMCPPath       = @"/mcp";
static NSString *const CAInternalMCPURLString  = @"127.0.0.1:27018/mcp";

#pragma mark - Codex CLI 契约（原包观测：-c 覆盖集与子命令）

static NSString *const CACodexConfigProviderLine   = @"model_providers.custom={ name=\"%@\", base_url=\"%@\", env_key=\"CODEX_CUSTOM_API_KEY\", wire_api=\"responses\", requires_openai_auth=false, supports_standalone_web_search=true }";
static NSString *const CACodexConfigModelProvider  = @"model_provider=\"custom\"";
static NSString *const CACodexConfigCodeMode       = @"features.code_mode=true";
static NSString *const CACodexConfigWebSearchFeat  = @"features.standalone_web_search=true";
static NSString *const CACodexConfigWebSearchLive  = @"web_search=\"live\"";
static NSString *const CACodexConfigModelCatalog   = @"model_catalog_json=%@";
static NSString *const CACodexConfigContextWindow  = @"model_context_window=%lu";
static NSString *const CACodexConfigLogDir         = @"log_dir=\"%@\"";
static NSString *const CACodexConfigInstructions   = @"developer_instructions=%@";
static NSString *const CACodexConfigNoLoginShell   = @"allow_login_shell=false";

static NSString *const CACodexSubcommandAppServer  = @"app-server";
static NSString *const CACodexSubcommandExec       = @"exec";
static NSString *const CACodexSubcommandLogin      = @"login";
static NSString *const CACodexFlagStdio            = @"--stdio";
static NSString *const CACodexFlagJSON             = @"--json";
static NSString *const CACodexFlagDangerous        = @"--dangerously-bypass-approvals-and-sandbox";
static NSString *const CACodexFlagSkipGitRepo      = @"--skip-git-repo-check";
static NSString *const CACodexFlagDeviceAuth       = @"--device-auth";
static NSString *const CACodexFlagWithAPIKey       = @"--with-api-key";
static NSString *const CACodexFlagWithAccessToken  = @"--with-access-token";

// app-server JSON-RPC 方法名（原包观测）
static NSString *const CARPCMethodThreadResume     = @"thread/resume";
static NSString *const CARPCMethodTurnStart        = @"turn/start";
static NSString *const CARPCNotificationInvalidated= @"app-server.invalidated";
static NSString *const CARPCItemRequestUserInput   = @"item/tool/requestUserInput";

#pragma mark - defaults 键（原包观测，全量照抄）

static NSString *const CADefaultsUseThirdPartyProvider   = @"CodexUseThirdPartyProvider";
static NSString *const CADefaultsThirdPartyProviderName  = @"CodexThirdPartyProviderName";
static NSString *const CADefaultsThirdPartyModel         = @"CodexThirdPartyModel";
static NSString *const CADefaultsThirdPartyAvailable     = @"CodexThirdPartyAvailableModels";
static NSString *const CADefaultsThirdPartyContextWindow = @"CodexThirdPartyContextWindowTokens";
static NSString *const CADefaultsThirdPartyReasoning     = @"CodexThirdPartyReasoningEffort";
static NSString *const CADefaultsAPIBaseURL              = @"CodexAPIBaseURL";
static NSString *const CADefaultsSelectedModel           = @"CodexSelectedModel";
static NSString *const CADefaultsActiveModelSlug         = @"CodexActiveModelSlug";
static NSString *const CADefaultsActiveEffort            = @"CodexActiveReasoningEffort";
static NSString *const CADefaultsReasoningEffort         = @"CodexReasoningEffort";
static NSString *const CADefaultsActiveWorkspace         = @"CodexActiveWorkspace";
static NSString *const CADefaultsSavedWorkspaces         = @"CodexSavedWorkspaces";
static NSString *const CADefaultsSidebarExpanded         = @"CodexSidebarExpandedWorkspacePaths";
static NSString *const CADefaultsDocumentsDisplayName    = @"CodexDocumentsWorkspaceDisplayName";
static NSString *const CADefaultsChatDisplayMode         = @"CodexChatDisplayMode";
static NSString *const CADefaultsThemeMode               = @"CodexThemeMode";
static NSString *const CADefaultsEnableWebSearch         = @"CodexEnableWebSearch";
static NSString *const CADefaultsEnableWorktree          = @"CodexEnableWorktree";
static NSString *const CADefaultsSandboxMode             = @"CodexSandboxMode";
static NSString *const CADefaultsKeepAlive               = @"CodexKeepAlive";
static NSString *const CADefaultsRemoteTheosEnabled      = @"CodexRemoteTheosEnabled";
static NSString *const CADefaultsRemoteInstallID         = @"CodexRemoteInstallID";
static NSString *const CADefaultsRemoteHeartbeatLimit    = @"CodexRemoteHeartbeatFailureLimit";
static NSString *const CADefaultsUsePersistentAppServer  = @"CodexUsePersistentAppServerChat";
static NSString *const CADefaultsConversationModels      = @"CodexConversationModelSelections";
static NSString *const CADefaultsAccountProfilePrefix    = @"CodexAccountProfile.v2.";
static NSString *const CADefaultsActiveConversationFmt   = @"CodexActiveConversation.%@";

#pragma mark - 环境变量（原包观测）

extern NSString *const CAEnvCodexHome;          // CODEX_HOME
extern NSString *const CAEnvCustomAPIKey;       // CODEX_CUSTOM_API_KEY
extern NSString *const CAEnvCACertificate;      // CODEX_CA_CERTIFICATE
extern NSString *const CAEnvSSLCertFile;        // SSL_CERT_FILE
extern NSString *const CAEnvWorkspacePath;      // CODEXAPP_WORKSPACE_PATH
extern NSString *const CAEnvWorkspaceName;      // CODEXAPP_WORKSPACE_NAME
extern NSString *const CAEnvWorkspaceHost;      // CODEXAPP_WORKSPACE_HOST
extern NSString *const CAEnvManagedSkillsPath;  // CODEXAPP_MANAGED_SKILLS_PATH
extern NSString *const CAEnvSpawnExternal;      // CODEXAPP_SPAWN_EXTERNAL
extern NSString *const CAEnvUpdateTmpRoot;      // CODEXAPP_UPDATE_TMP_ROOT
extern NSString *const CAEnvHelpers;            // CA_HELPERS
extern NSString *const CAEnvTheosHelper;        // CA_THEOS_HELPER
extern NSString *const CAEnvTheosBash;          // CA_THEOS_BASH
extern NSString *const CAEnvTheosRuntime;       // CA_THEOS_RUNTIME
extern NSString *const CAEnvTheosSDKRoot;       // CA_THEOS_SDKROOT
extern NSString *const CAEnvTheosEmbedded;      // CA_THEOS_EMBEDDED
extern NSString *const CAEnvTheosPackageMode;   // CA_THEOS_PACKAGE_MODE
extern NSString *const CAEnvTheosPath;          // CA_THEOS_PATH
extern NSString *const CAEnvTheosClang;         // CA_THEOS_CLANG
extern NSString *const CAEnvTheosMake;          // CA_THEOS_MAKE
extern NSString *const CAEnvTheosPerl;          // CA_THEOS_PERL
extern NSString *const CAEnvTheosDpkgDeb;       // CA_THEOS_DPKG_DEB
extern NSString *const CAEnvTheosTar;           // CA_THEOS_TAR
extern NSString *const CAEnvTheosGzip;          // CA_THEOS_GZIP
extern NSString *const CAEnvTheosXz;            // CA_THEOS_XZ
extern NSString *const CAEnvTheosZsh;           // CA_THEOS_ZSH
extern NSString *const CAEnvTheosModuleCache;   // CA_THEOS_MODULE_CACHE
extern NSString *const CAEnvTheosTarABI;        // CA_THEOS_TAR_ABI
extern NSString *const CAEnvTheosSequenceDir;   // CA_THEOS_SEQUENCE_DIR
extern NSString *const CAEnvRuntimeEnvKind;     // CA_RUNTIME_ENV_KIND
extern NSString *const CAEnvRuntimeJailbreakBrand;  // CA_RUNTIME_JAILBREAK_BRAND
extern NSString *const CAEnvRuntimeJailbreakFamily; // CA_RUNTIME_JAILBREAK_FAMILY
extern NSString *const CAEnvRuntimeRootMode;    // CA_RUNTIME_ROOT_MODE
extern NSString *const CAEnvRuntimeTrollStoreFlavor; // CA_RUNTIME_TROLLSTORE_FLAVOR
extern NSString *const CAEnvReverseToolsStaging; // CA_REVERSE_TOOLS_STAGING
extern NSString *const CAEnvGitProbe;           // CA_GIT_PROBE
extern NSString *const CAEnvUserlandProbe;      // CA_USERLAND_PROBE
extern NSString *const CAEnvProbeFile;          // CA_PROBE_FILE
extern NSString *const CAEnvPipeRedirectDir;    // CA_PIPE_REDIRECT_DIR
extern NSString *const CAEnvRedirectProbe;      // CA_REDIRECT_PROBE
extern NSString *const CAEnvGitConfigCount;     // GIT_CONFIG_COUNT
extern NSString *const CAEnvGitTerminalPrompt;  // GIT_TERMINAL_PROMPT
extern NSString *const CAEnvGitSSLCAlinfo;      // GIT_SSL_CAINFO

#pragma mark - 日志

typedef NS_ENUM(NSInteger, CALogLevel) { CALogLevelDebug = 1, CALogLevelInfo = 2, CALogLevelWarn = 3, CALogLevelError = 4 };

void CALog(CALogLevel level, NSString *category, NSString *format, ...) NS_FORMAT_FUNCTION(3, 4);

#pragma mark - 运行时助手（多调用二进制）

BOOL CAIsHelperInvocation(void);                 // 当前进程是否是 helper（argv[0] 为 bash/sh/…）
NSString *CACurrentInvocationName(void);         // argv[0] 的 basename
int CARunHelperInvocation(int argc, char **argv);// 分发到 bash.real / codex / ca-filetool / code-mode-host
