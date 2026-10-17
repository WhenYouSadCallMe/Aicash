//
//  CAChatViewController.m
//
//  会话页外壳：消息表格 + 输入框 + 运行状态条。
//
//  引擎接线（原包行为）：
//    · 默认走 CACodexEngine -startExecWithPrompt:workspace:model:executionMode:sandbox:output:completion:
//      逐行 JSON（--json）解析成消息；thread_id 记住后供下一轮复用。
//    · defaults 键 CodexUsePersistentAppServerChat 为真时改走
//      -sendPromptViaPersistentAppServer:threadId:completion:（常驻 app-server turn），
//      该 completion 在「回合结束」时回调；回合内的增量由引擎转发的
//      CACodexEngineAppServerNotification 驱动（逐块刷新助手消息）。
//    · 后台保活：UIBackgroundModes=audio + 静音音频 + renewBackgroundTask（原包同款做法）。
//
//  聊天主流程实装（本轮）：
//    · 消息模型用 CAMessageItem（文本 / 思考 / 工具卡片 / 提示），渲染交给
//      CAMessageCell / CAThinkingCell / CAToolCardCell（代码块用 CACodeBlockView，
//      流式文本用 CAStreamingTextView）；
//    · 会话读写全部走 CAConversationStore（用户消息落盘 + 立即上屏）；
//    · 运行时未安装 / 供应商未配置时给出可操作引导（设置页 / 诊断页），不静默失败；
//    · 输入 “/” 唤起 CAComposerCatalog 条目面板（命令 / MCP / 技能），选中后插入输入框。
//

#import "CAChatViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CARuntimeCatalog.h"
#import "CALogger.h"
#import "CACodexEngine.h"
#import "CAAppServerSession.h"
#import "CAConversationStore.h"
#import "CAComposerCatalog.h"
#import "CAProviderConfiguration.h"
#import "CASettingsViewController.h"
#import "CADiagnosticsViewController.h"
#import "CAMessageItem.h"
#import "CAToolItem.h"
#import "CAMessageCell.h"
#import "CAThinkingCell.h"
#import "CAToolCardCell.h"
#import "CAComposerPopupView.h"
#import "CAComposerPopupSection.h"
#import "CAComposerPopupItem.h"
#import "CAReasoningEffortViewController.h"
#import "CAConversationSidebarViewController.h"
#import "CAGitChangesViewController.h"
#import "CAGitRepository.h"
#import "CAGitSnapshot.h"
#import "CAWorkspaceViewController.h"
#import "CAModelPickerViewController.h"
#import "CAModelPricingViewController.h"
#import "CAModelPricingManager.h"
#import "CAAgentStatusDetailViewController.h"
#import "CAExtensionListViewController.h"
#import "CAExtensionsViewController.h"
#import "CATextDetailViewController.h"
#import "CAArtifactPreviewViewController.h"
#import "CAControlCenterPanels.h"
#import "CAPlanDecisionViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kChatExecutionModeDefaultsKey = @"CodexExecutionMode";
static NSString * const kChatActiveThreadDefaultsKey   = @"CodexActiveThreadID";
static NSString * const kChatPlaceholderPoolKey        = @"CodexComposerPlaceholderPool";
static NSString * const kChatMessageCellReuseIdentifier  = @"CAChatMessageCell";
static NSString * const kChatThinkingCellReuseIdentifier = @"CAChatThinkingCell";
static NSString * const kChatToolCardCellReuseIdentifier = @"CAChatToolCardCell";
static NSString * const kChatSidebarCellReuseIdentifier  = @"CAConversationCell";
static const NSTimeInterval kChatPlaceholderRotateInterval = 12.0;
static const NSTimeInterval kChatSilentAudioSeconds        = 3.0;
static const NSUInteger kChatRawTailLimit                  = 40;
static const NSUInteger kChatStderrTailLimit               = 6;

#pragma mark 空态字面量（01 主会话页·空态，逐字对齐真机截图，别动半角/全角与间隔）

static NSString * const kChatWelcomeTitleText        = @"今天想完成什么?";
static NSString * const kChatWelcomeSubtitleLine1    = @"从理解项目到交付代码";
static NSString * const kChatWelcomeSubtitleLine2    = @"在当前工作区开始一个任务";
static NSString * const kChatWelcomeCardProjectTitle = @"了解这个项目";
static NSString * const kChatWelcomeCardInspectTitle = @"检查代码问题";
static NSString * const kChatWelcomeCardFeatureTitle = @"实现一个功能";
static NSString * const kChatCollaborationReadyText  = @"Agent 协作就绪";
static NSString * const kChatContextCaptionText      = @"上下文 0% · 缓存 —";
static NSString * const kChatDefaultModelChipTitle   = @"6.1-Sol";
static NSString * const kChatDefaultEffortChipTitle  = @"High";

/// 点按建议卡后填进输入框的提示词（只填不发）
static NSString * const kChatWelcomePromptProject   = @"先带我过一遍这个项目：读主要目录和关键文件，说明它是做什么的、怎么跑起来、关键代码在哪。";
static NSString * const kChatWelcomePromptInspect   = @"帮我检查这个项目的代码问题：先跑构建和测试，把报错、告警和明显隐患列出来，并给出修复建议。";
static NSString * const kChatWelcomePromptFeature   = @"我想实现一个新功能：请先给实现方案，确认后再改代码。";

#pragma mark 空态 / 底部条尺寸（SPEC/UI_还原基准.md §3 实测值，单位 pt）

static const CGFloat kChatWelcomeCardHeight      = 46.0;   // 建议卡高（截图实测 46）
static const CGFloat kChatWelcomeCardSpacing     = 8.0;    // 卡间距（46 + 8 = 行距 54）
static const CGFloat kChatWelcomeCardSideInset   = 31.0;   // 建议卡左右内缩（截图实测 31.3）
static const CGFloat kChatBottomBarSideInset     = 12.0;   // 协作条 / 输入卡左右内缩
static const CGFloat kChatBottomCircleSize       = 32.0;   // 圆形按钮直径（+ / 发送 / 垃圾桶 / 电闪）
static const CGFloat kChatBottomChipHeight       = 30.0;   // 胶囊高（6.1-Sol / High / 协作药丸）
static const CGFloat kChatBottomBarHeight        = 42.0;   // 协作条整条高
static const CGFloat kChatComposerCardRadius     = 16.0;   // 输入卡圆角

#pragma mark Git 角标轮询

static const NSTimeInterval kChatGitBadgePollInterval = 5.0;
/// 读不到 git（没有 git 可执行文件 / 非仓库）时给真机截图同款的角标文案
static NSString * const kChatGitBadgeFallbackText = @"99+";

#pragma mark - 会话页

@interface CAChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong, readwrite) CACodexEngine *chatEngine;
@property (nonatomic, strong, nullable) UIView *welcomeExtensionHint;
@property (nonatomic, strong, nullable) UIScrollView *chipScrollView;
@property (nonatomic, strong, nullable) UIStackView *chipStackView;
@property (nonatomic, strong, readwrite) NSMutableArray *messages;

#pragma mark 视图

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *statusStrip;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusTitleLabel;
@property (nonatomic, strong) UILabel *statusDetailLabel;

@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextView *composerField;
@property (nonatomic, strong) UILabel *inputPlaceholderLabel;
@property (nonatomic, strong) UILabel *attachmentHintLabel;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *stopButton;

@property (nonatomic, strong) UIView *runtimeBanner;
@property (nonatomic, strong) UILabel *runtimeBannerLabel;
@property (nonatomic, strong) UIButton *runtimeInstallButton;
@property (nonatomic, strong) UIButton *runtimeSettingsButton;
@property (nonatomic, strong, nullable) NSLayoutConstraint *runtimeBannerHeightConstraint;

@property (nonatomic, strong, nullable) NSLayoutConstraint *historyDrawerLeading;

#pragma mark 数据

@property (nonatomic, strong) NSMutableArray<NSString *> *pendingAttachments;
@property (nonatomic, strong) NSMutableArray<NSString *> *rawTailLines;
@property (nonatomic, strong) NSMutableArray<NSString *> *stderrTailLines;
@property (nonatomic, strong, nullable) NSMutableArray<NSString *> *chatStderrTailLines;

#pragma mark 回合状态

@property (nonatomic, strong, nullable) CAMessageItem *streamingAssistantMessage;
@property (nonatomic, strong, nullable) CAMessageItem *thinkingMessage;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CAMessageItem *> *streamingMessagesByItemId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CAMessageItem *> *toolMessagesByItemId;
@property (nonatomic, copy, nullable) NSString *activeTurnIdentifier;
@property (nonatomic, assign) BOOL chatTurnActive;
@property (nonatomic, assign) BOOL chatStreamRefreshScheduled;
@property (nonatomic, copy, nullable) NSString *chatLastErrorMessage;

#pragma mark 服务端用户输入请求（item/tool/requestUserInput）

/// 待应答的 app-server 请求 id（引擎缓存镜像）
@property (nonatomic, strong, nullable) NSNumber *pendingUserInputRequestID;
/// 待应答请求的 params（questions 等）
@property (nonatomic, strong, nullable) NSDictionary *pendingUserInputParams;
/// 当前展示中的决策卡（dismiss 未选择时也要回一个取消应答，避免回合挂死）
@property (nonatomic, strong, nullable) UIViewController *activeDecisionPanel;

#pragma mark 侧栏

@property (nonatomic, strong, nullable) CAConversationSidebarViewController *conversationSidebar;
@property (nonatomic, assign) BOOL chatHistoryDrawerOpen;

#pragma mark 计时器 / 音频

@property (nonatomic, strong, nullable) NSTimer *pulseTimer;
@property (nonatomic, strong, nullable) NSTimer *rotationTimer;
@property (nonatomic, strong, nullable) AVAudioPlayer *silentPlayer;
@property (nonatomic, assign) BOOL audioObserversInstalled;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTaskIdentifier;

@property (nonatomic, strong, nullable) NSLayoutConstraint *inputBottomConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *inputHeightConstraint;
@property (nonatomic, assign) NSUInteger streamGeneration;
@property (nonatomic, copy, nullable) NSString *lastUsageSummary;

// P1 补齐（原包方法对齐）：thread/tokenUsage/updated → composer 卡上下文行
@property (nonatomic, assign) double contextWindowUsedPercent;
@property (nonatomic, assign) double cacheHitPercent;
@property (nonatomic, assign) BOOL hasContextUsage;

#pragma mark 空态 / 底部固定条（01 主会话页·空态）

@property (nonatomic, strong, nullable) NSLayoutConstraint *statusStripHeightConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *attachmentHintHeightConstraint;
@property (nonatomic, strong, nullable) UILabel *welcomeTitleLabel;
@property (nonatomic, strong, nullable) UIView *collaborationBoltCircle;
@property (nonatomic, strong, nullable) UIView *collaborationPill;
@property (nonatomic, strong, nullable) UIImageView *collaborationPillIcon;
@property (nonatomic, strong, nullable) UILabel *collaborationPillLabel;
@property (nonatomic, strong, nullable) UIView *composerActionRow;
@property (nonatomic, strong, nullable) UIButton *slashButton;
@property (nonatomic, strong, nullable) NSTimer *gitBadgeTimer;
/// “/”插入后抑制再次弹出菜单的那段文本（原包 ivar 语义；访问器在 .h 里是 id 签名，这里用别名属性实现）
@property (nonatomic, copy, nullable) NSString *composerSuppressedToken;

- (void)setupQuickActionBar;
- (void)applyOpaqueNavigationBarAppearance;
- (UIButton *)welcomeCardWithTitle:(NSString *)title symbol:(NSString *)symbol prompt:(NSString *)prompt;
- (UIButton *)circularBarButtonWithSymbol:(NSString *)symbol pointSize:(CGFloat)pointSize;
- (void)applyChipTitle:(NSString *)title toButton:(UIButton *)button;
- (void)fillComposerWithPrompt:(NSString *)prompt;
- (id)handleSlashMenuButton;
- (void)handleComposerMenuLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)updateConversationBottomInset;
- (void)stopGitBadgePolling;
- (void)gitBadgeTimerTick:(NSTimer *)timer;
- (void)applyGitBadgeChangeCount:(NSUInteger)count available:(BOOL)available;
- (NSString *)currentModelChipTitle;
- (NSString *)chipLabelForModelSlug:(NSString *)slug;
- (NSString *)currentEffortChipTitle;
- (NSString *)effortDisplayTitleForLevel:(NSString *)level;
- (id)presentPanelInNavigationController:(nullable UIViewController *)controller;
- (id)presentPanelPlaceholderNoticeWithTitle:(NSString *)title detail:(nullable NSString *)detail;
- (nullable NSString *)textForSelectionArgument:(id)arg1;

#pragma mark 空态 / 底部条 / 面板入口

- (void)setupUI;
- (void)setupNavigationItems;
- (void)setupKeyboardNotifications;
- (UIView *)buildHistorySidebar;
- (void)workspaceDidChange:(NSNotification *)notification;

- (void)submitCurrentComposerText;
- (void)handleSend;
- (void)handleAttach;
- (void)handleNewChat;
- (void)handleShowHistory;
- (void)closeHistorySidebar;
- (void)handleOpenSettings;

- (void)appendMessageWithRole:(CAMessageRole)role text:(NSString *)text detail:(nullable NSString *)detail;
- (void)finalizeStreamingMessages;
- (void)refreshStreamingRow;
- (void)scrollToBottomAnimated:(BOOL)animated;
- (void)conversationDidChange;

- (void)handleEngineOutputLine:(NSString *)line isStderr:(BOOL)isStderr;
- (NSString *)textFromPayload:(NSDictionary *)payload;
- (void)rememberThreadIdentifierFromPayload:(NSDictionary *)payload;
- (void)consumeUsageFromPayload:(NSDictionary *)payload;
- (void)applyTokenUsagePayload:(NSDictionary *)payload;
- (void)renderContextCaption;
- (void)renderStreamTail:(NSString *)line;

- (void)updateSendButtonState;
- (void)updateInputHeight;
- (void)renderStatusStrip;
- (void)applyComposerPlaceholder;
- (void)rotateComposerPlaceholderIfNeeded;
- (NSArray *)composerPlaceholderPool;
- (NSString *)runtimeSummaryText;
- (NSString *)trimmedText:(NSString *)text;
- (NSString *)composedPromptWithText:(NSString *)text attachments:(nullable NSArray *)attachments;

- (void)startRotationTimer;
- (void)stopRotationTimer;
- (void)rotationTimerTick:(NSTimer *)timer;
- (void)pulseTimerTick:(NSTimer *)timer;

- (void)keyboardWillChangeFrame:(NSNotification *)notification;
- (void)keyboardWillShow:(NSNotification *)notification;
- (void)keyboardWillHide:(NSNotification *)notification;

- (void)mediaServicesWereReset:(NSNotification *)notification;
- (void)audioSessionInterrupted:(NSNotification *)notification;
- (NSData *)silentWAVDataWithSeconds:(NSTimeInterval)seconds;
- (void)endBackgroundTaskIfNeeded;

- (void)loadActiveConversation;

#pragma mark 聊天主流程（本轮新增的私有入口）

- (void)dispatchPromptText:(NSString *)prompt displayText:(NSString *)displayText attachments:(nullable NSArray *)attachments;
- (void)beginTurnWithTitle:(NSString *)title detail:(nullable NSString *)detail;
- (void)finishTurnWithStatus:(NSInteger)status message:(nullable NSString *)message;
- (BOOL)chatRuntimeAvailable;
- (BOOL)chatProviderConfigured;
- (void)refreshRuntimeBanner;
- (void)appendNoticeText:(NSString *)text;
- (void)persistConversation;
- (NSArray<NSDictionary *> *)messageDictionaries;
- (void)restoreMessagesFromRecord:(CAConversationRecord *)record;
- (id)applyRecordSelection:(id)record resetEngine:(id)resetEngine;
- (void)rebindThreadForRecord:(CAConversationRecord *)record;

- (void)engineDidEmitNotification:(NSNotification *)notification;
- (void)composerCatalogDidChange:(NSNotification *)notification;
- (void)runtimeCatalogDidChange:(NSNotification *)notification;
- (void)handleEngineEvent:(NSDictionary *)event source:(NSString *)source;
- (void)handleEngineItem:(NSDictionary *)item method:(NSString *)method;
- (void)presentDecisionCardForUserInput:(NSDictionary *)params requestID:(nullable NSNumber *)requestID;
- (void)respondToPendingUserInputWithAnswers:(NSDictionary *)answers remember:(BOOL)remember requestID:(nullable NSNumber *)requestID;
- (void)steerActiveTurnWithPrompt:(NSString *)prompt displayText:(NSString *)displayText attachments:(nullable NSArray *)attachments;
- (CAMessageItem *)assistantMessageForItemId:(NSString *)itemId createIfNeeded:(BOOL)create;
- (void)updateThinkingDetail:(NSString *)detail running:(BOOL)running;
- (void)updateToolCardForItem:(NSDictionary *)item itemId:(NSString *)itemId method:(NSString *)method;
- (void)scheduleStreamingRefresh;
- (void)presentRuntimeGuidanceForRuntime:(BOOL)missingRuntime detail:(nullable NSString *)detail;
- (id)presentRuntimeDiagnostics;
- (id)presentSettingsForRequiredRuntimes;
- (id)presentSettingsFocusingRequiredRuntimes:(id)arg1;

#pragma mark “/” 面板

- (id)setupComposerPopup;
- (id)updateComposerSlashMenuState;
- (id)reloadSlashComposerPopupPreserving:(id)arg1;
- (NSArray *)composerPopupSections;
- (id)handleComposerPopupItem:(id)arg1;
- (id)insertComposerText:(id)arg1;
- (id)composerSlashContext;
- (id)openSlashComposerPopupTextDriven:(id)arg1;
- (NSString *)composerReferenceForCatalogItem:(CAComposerCatalogItem *)item;
- (void)setChatComposerPopupVisible:(BOOL)visible animated:(BOOL)animated;

@end

@implementation CAChatViewController

#pragma mark - 生命周期

- (instancetype)init
{
    if ((self = [super init])) {
        _chatEngine = [CACodexEngine sharedEngine];
        _messages = [NSMutableArray array];
        _pendingAttachments = [NSMutableArray array];
        _rawTailLines = [NSMutableArray array];
        _stderrTailLines = [NSMutableArray array];
        _streamingMessagesByItemId = [NSMutableDictionary dictionary];
        _toolMessagesByItemId = [NSMutableDictionary dictionary];
        _autoFollowLatest = YES;
        _backgroundTaskIdentifier = UIBackgroundTaskInvalid;
        _composerPlaceholderIndex = 0;

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _workspacePath = [defaults stringForKey:CADefaultsActiveWorkspace];
        if (_workspacePath.length == 0) {
            _workspacePath = CARuntimePaths.documentsCodexDirectory;
        }
        _threadId = [defaults stringForKey:kChatActiveThreadDefaultsKey];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // 截图 01 顶栏中间没有标题：这里不设 self.title，导航栏保持空白
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self applyOpaqueNavigationBarAppearance];
    [self setupUI];
    [self setupQuickActionBar];
    [self setupWelcomeView];
    [self setupNavigationItems];
    [self setupKeyboardNotifications];
    [self installAudioObserversIfNeeded];
    [self configureAudioSession];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(engineDidEmitNotification:) name:CACodexEngineAppServerNotification object:nil];
    [center addObserver:self selector:@selector(composerCatalogDidChange:) name:CAComposerCatalogDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(runtimeCatalogDidChange:) name:CARuntimeCatalogDidChangeNotification object:nil];

    [self loadActiveConversation];
    [self refreshAttachmentPlaceholder];
    [self refreshRuntimeBanner];
    [self renderStatusStrip];
    [self refreshBottomSelectors];
    [self refreshWelcomeState];
    [self refreshGitBadge];

    [[CARuntimeCatalog sharedCatalog] startAutoRefresh];
    [CAComposerCatalog.sharedCatalog restorePersistentCacheForWorkspace:self.workspacePath];

    CALog(CALogLevelInfo, @"CHAT", @"chat view loaded workspace=%@ thread=%@ runtime=%@",
          self.workspacePath, self.threadId ?: @"(none)", [self chatRuntimeAvailable] ? @"ready" : @"missing");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshAttachmentPlaceholder];
    [self startRotationTimer];
    if (self.thinking) {
        [self startPulseTimer];
    }
    [self refreshRuntimeBanner];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(workspaceDidChange:)
                                                 name:@"CAWorkspaceDidChangeNotification"
                                               object:nil];
    [self refreshWelcomeState];
    [self updateGitBadgePolling];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopRotationTimer];
    [self saveActiveConversation];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"CAWorkspaceDidChangeNotification" object:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    // 离开会话页就停掉 git 角标轮询，回来（viewWillAppear）再起
    [self stopGitBadgePolling];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateInputHeight];
    [self updateConversationBottomInset];
}

- (void)dealloc
{
    [self stopPulseTimer];
    [self stopRotationTimer];
    [self stopGitBadgePolling];
    _silentPlayer = nil;
    [self endBackgroundTaskIfNeeded];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)setupUI
{
    self.statusStrip = [[UIView alloc] init];
    self.statusStrip.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusStrip.backgroundColor = UIColor.secondarySystemBackgroundColor;
    [self.view addSubview:self.statusStrip];

    self.statusDot = [[UIView alloc] init];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.backgroundColor = UIColor.systemGreenColor;
    self.statusDot.layer.cornerRadius = 4.0;
    self.statusDot.layer.masksToBounds = YES;
    [self.statusStrip addSubview:self.statusDot];

    self.statusTitleLabel = [[UILabel alloc] init];
    self.statusTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusTitleLabel.text = @"就绪";
    [self.statusStrip addSubview:self.statusTitleLabel];

    self.statusDetailLabel = [[UILabel alloc] init];
    self.statusDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDetailLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.statusDetailLabel.textColor = UIColor.secondaryLabelColor;
    self.statusDetailLabel.textAlignment = NSTextAlignmentRight;
    self.statusDetailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [self.statusStrip addSubview:self.statusDetailLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 96.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:CAMessageCell.class forCellReuseIdentifier:kChatMessageCellReuseIdentifier];
    [self.tableView registerClass:CAThinkingCell.class forCellReuseIdentifier:kChatThinkingCellReuseIdentifier];
    [self.tableView registerClass:CAToolCardCell.class forCellReuseIdentifier:kChatToolCardCellReuseIdentifier];
    [self.view addSubview:self.tableView];

    self.inputBar = [[UIView alloc] init];
    self.inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;
    // 输入卡：白底 + 1px 描边 + 大圆角（截图里是白卡叠在白页上，靠细描边分界）
    self.inputBar.layer.cornerRadius = kChatComposerCardRadius;
    self.inputBar.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.inputBar.layer.borderColor = UIColor.systemGray5Color.CGColor;
    self.inputBar.layer.masksToBounds = YES;
    [self.view addSubview:self.inputBar];

    // 卡内首行：上下文 0% · 缓存 —（灰色小字）
    self.contextCaption = [[UILabel alloc] init];
    self.contextCaption.translatesAutoresizingMaskIntoConstraints = NO;
    self.contextCaption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.contextCaption.textColor = UIColor.secondaryLabelColor;
    self.contextCaption.text = kChatContextCaptionText;
    [self.inputBar addSubview:self.contextCaption];

    self.attachmentHintLabel = [[UILabel alloc] init];
    self.attachmentHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentHintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.attachmentHintLabel.textColor = UIColor.secondaryLabelColor;
    self.attachmentHintLabel.hidden = YES;
    [self.inputBar addSubview:self.attachmentHintLabel];

    self.attachmentHintHeightConstraint = [self.attachmentHintLabel.heightAnchor constraintEqualToConstant:0.0];

    self.inputPlaceholderLabel = [[UILabel alloc] init];
    self.inputPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputPlaceholderLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.inputPlaceholderLabel.textColor = UIColor.placeholderTextColor;
    [self.inputBar addSubview:self.inputPlaceholderLabel];

    self.composerField = [[UITextView alloc] init];
    self.composerField.translatesAutoresizingMaskIntoConstraints = NO;
    self.composerField.delegate = self;
    self.composerField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.composerField.backgroundColor = UIColor.clearColor;
    self.composerField.scrollsToTop = NO;
    [self.inputBar addSubview:self.composerField];

    // 卡内按钮行：+ / 6.1-Sol / High / ↑
    self.composerActionRow = [[UIView alloc] init];
    self.composerActionRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.inputBar addSubview:self.composerActionRow];

    self.attachButton = [self circularBarButtonWithSymbol:@"plus" pointSize:17.0];
    [self.attachButton addTarget:self action:@selector(handleAttach) forControlEvents:UIControlEventTouchUpInside];
    self.attachButton.accessibilityLabel = @"添加附件";
    [self.composerActionRow addSubview:self.attachButton];

    // “/”：斜杠菜单（走已有的 “/” 弹出逻辑）；长按是 ⋯ 入口菜单
    self.composerMenuButton = [self circularBarButtonWithSymbol:@"slash" pointSize:17.0];
    [self.composerMenuButton addTarget:self action:@selector(handleSlashMenuButton) forControlEvents:UIControlEventTouchUpInside];
    [self.composerMenuButton addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleComposerMenuLongPress:)]];
    self.composerMenuButton.accessibilityLabel = @"斜杠菜单";
    [self.composerActionRow addSubview:self.composerMenuButton];

    // 模型 / 强度 chip：放进横向滚动条，永不压缩、永不截断（原版 chip 压缩阻力为 required）
    UIScrollView *chipScroll = [[UIScrollView alloc] init];
    chipScroll.translatesAutoresizingMaskIntoConstraints = NO;
    chipScroll.showsHorizontalScrollIndicator = NO;
    chipScroll.alwaysBounceHorizontal = YES;
    [self.composerActionRow addSubview:chipScroll];
    self.chipScrollView = chipScroll;

    UIStackView *chipStack = [[UIStackView alloc] init];
    chipStack.translatesAutoresizingMaskIntoConstraints = NO;
    chipStack.axis = UILayoutConstraintAxisHorizontal;
    chipStack.alignment = UIStackViewAlignmentFill;
    chipStack.spacing = 9.0;
    [chipScroll addSubview:chipStack];
    self.chipStackView = chipStack;

    self.bottomModelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bottomModelBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self applyChipTitle:kChatDefaultModelChipTitle toButton:self.bottomModelBtn];
    [self.bottomModelBtn addTarget:self action:@selector(handleBottomModelBtnTapped) forControlEvents:UIControlEventTouchUpInside];
    [chipStack addArrangedSubview:self.bottomModelBtn];

    self.bottomEffortBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bottomEffortBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self applyChipTitle:kChatDefaultEffortChipTitle toButton:self.bottomEffortBtn];
    [self.bottomEffortBtn addTarget:self action:@selector(handleBottomEffortBtnTapped) forControlEvents:UIControlEventTouchUpInside];
    [chipStack addArrangedSubview:self.bottomEffortBtn];

    self.sendButton = [self circularBarButtonWithSymbol:@"arrow.up" pointSize:17.0];
    self.sendButton.backgroundColor = UIColor.secondarySystemFillColor;
    [self.sendButton setTintColor:UIColor.whiteColor];
    [self.sendButton addTarget:self action:@selector(handleSend) forControlEvents:UIControlEventTouchUpInside];
    self.sendButton.accessibilityLabel = @"发送";
    [self.composerActionRow addSubview:self.sendButton];

    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stopButton setTitle:@"停止" forState:UIControlStateNormal];
    self.stopButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [self.stopButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(handleStop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.hidden = YES;
    [self.composerActionRow addSubview:self.stopButton];

    [self setupRuntimeBanner];
    [self setupComposerPopup];

    self.inputHeightConstraint = [self.composerField.heightAnchor constraintEqualToConstant:36.0];
    self.inputBottomConstraint = [self.inputBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    // 空态时把顶部的运行状态条让开（截图里导航栏下是空的），靠高度约束折叠
    self.statusStripHeightConstraint = [self.statusStrip.heightAnchor constraintEqualToConstant:30.0];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusStrip.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.statusStrip.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.statusStrip.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.statusStripHeightConstraint,

        [self.statusDot.leadingAnchor constraintEqualToAnchor:self.statusStrip.leadingAnchor constant:12.0],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.statusStrip.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:8.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:8.0],

        [self.statusTitleLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:8.0],
        [self.statusTitleLabel.centerYAnchor constraintEqualToAnchor:self.statusStrip.centerYAnchor],

        [self.statusDetailLabel.leadingAnchor constraintEqualToAnchor:self.statusTitleLabel.trailingAnchor constant:8.0],
        [self.statusDetailLabel.trailingAnchor constraintEqualToAnchor:self.statusStrip.trailingAnchor constant:-12.0],
        [self.statusDetailLabel.centerYAnchor constraintEqualToAnchor:self.statusStrip.centerYAnchor],

        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kChatBottomBarSideInset],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kChatBottomBarSideInset],
        self.inputBottomConstraint,

        // 卡内首行：上下文 0% · 缓存 —
        [self.contextCaption.topAnchor constraintEqualToAnchor:self.inputBar.topAnchor constant:14.0],
        [self.contextCaption.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:16.0],
        [self.contextCaption.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-16.0],

        [self.attachmentHintLabel.topAnchor constraintEqualToAnchor:self.contextCaption.bottomAnchor constant:2.0],
        [self.attachmentHintLabel.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:16.0],
        [self.attachmentHintLabel.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-16.0],
        self.attachmentHintHeightConstraint,

        [self.composerField.topAnchor constraintEqualToAnchor:self.attachmentHintLabel.bottomAnchor constant:4.0],
        [self.composerField.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:16.0],
        [self.composerField.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-16.0],
        self.inputHeightConstraint,

        [self.inputPlaceholderLabel.topAnchor constraintEqualToAnchor:self.composerField.topAnchor constant:8.0],
        [self.inputPlaceholderLabel.leadingAnchor constraintEqualToAnchor:self.composerField.leadingAnchor constant:5.0],
        [self.inputPlaceholderLabel.trailingAnchor constraintEqualToAnchor:self.composerField.trailingAnchor],

        // 卡内按钮行
        [self.composerActionRow.topAnchor constraintEqualToAnchor:self.composerField.bottomAnchor constant:8.0],
        [self.composerActionRow.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:14.0],
        [self.composerActionRow.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-12.0],
        [self.composerActionRow.heightAnchor constraintEqualToConstant:kChatBottomCircleSize],

        [self.attachButton.leadingAnchor constraintEqualToAnchor:self.composerActionRow.leadingAnchor],
        [self.attachButton.centerYAnchor constraintEqualToAnchor:self.composerActionRow.centerYAnchor],
        [self.attachButton.widthAnchor constraintEqualToConstant:kChatBottomCircleSize],
        [self.attachButton.heightAnchor constraintEqualToConstant:kChatBottomCircleSize],

        [self.composerMenuButton.leadingAnchor constraintEqualToAnchor:self.attachButton.trailingAnchor constant:10.0],
        [self.composerMenuButton.centerYAnchor constraintEqualToAnchor:self.composerActionRow.centerYAnchor],
        [self.composerMenuButton.widthAnchor constraintEqualToConstant:kChatBottomCircleSize],
        [self.composerMenuButton.heightAnchor constraintEqualToConstant:kChatBottomCircleSize],

        // 滚动条占满「斜杠按钮 → 发送按钮」之间，chip 按自身内容宽度排布
        [self.chipScrollView.leadingAnchor constraintEqualToAnchor:self.composerMenuButton.trailingAnchor constant:11.0],
        [self.chipScrollView.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-8.0],
        [self.chipScrollView.centerYAnchor constraintEqualToAnchor:self.composerActionRow.centerYAnchor],
        [self.chipScrollView.heightAnchor constraintEqualToConstant:kChatBottomChipHeight],

        [self.chipStackView.leadingAnchor constraintEqualToAnchor:self.chipScrollView.contentLayoutGuide.leadingAnchor],
        [self.chipStackView.trailingAnchor constraintEqualToAnchor:self.chipScrollView.contentLayoutGuide.trailingAnchor],
        [self.chipStackView.topAnchor constraintEqualToAnchor:self.chipScrollView.contentLayoutGuide.topAnchor],
        [self.chipStackView.bottomAnchor constraintEqualToAnchor:self.chipScrollView.contentLayoutGuide.bottomAnchor],
        [self.chipStackView.heightAnchor constraintEqualToAnchor:self.chipScrollView.frameLayoutGuide.heightAnchor],

        [self.bottomModelBtn.heightAnchor constraintEqualToConstant:kChatBottomChipHeight],
        [self.bottomEffortBtn.heightAnchor constraintEqualToConstant:kChatBottomChipHeight],

        [self.stopButton.trailingAnchor constraintEqualToAnchor:self.composerActionRow.trailingAnchor],
        [self.stopButton.centerYAnchor constraintEqualToAnchor:self.composerActionRow.centerYAnchor],

        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.composerActionRow.trailingAnchor],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.composerActionRow.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:kChatBottomCircleSize],
        [self.sendButton.heightAnchor constraintEqualToConstant:kChatBottomCircleSize],

        [self.inputBar.bottomAnchor constraintEqualToAnchor:self.composerActionRow.bottomAnchor constant:13.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.statusStrip.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        // 列表铺满整屏，底部固定条（协作条 + 输入卡）用 contentInset.bottom 让位
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupRuntimeBanner
{
    self.runtimeBanner = [[UIView alloc] init];
    self.runtimeBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.runtimeBanner.backgroundColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.12];
    [self.view addSubview:self.runtimeBanner];

    self.runtimeBannerLabel = [[UILabel alloc] init];
    self.runtimeBannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.runtimeBannerLabel.numberOfLines = 2;
    self.runtimeBannerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.runtimeBannerLabel.textColor = UIColor.labelColor;
    [self.runtimeBanner addSubview:self.runtimeBannerLabel];

    self.runtimeInstallButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runtimeInstallButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runtimeInstallButton setTitle:@"安装运行时" forState:UIControlStateNormal];
    self.runtimeInstallButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    [self.runtimeInstallButton addTarget:self action:@selector(handleInstallRuntime) forControlEvents:UIControlEventTouchUpInside];
    [self.runtimeBanner addSubview:self.runtimeInstallButton];

    self.runtimeSettingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runtimeSettingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.runtimeSettingsButton setTitle:@"去设置" forState:UIControlStateNormal];
    self.runtimeSettingsButton.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    [self.runtimeSettingsButton addTarget:self action:@selector(handleOpenSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.runtimeBanner addSubview:self.runtimeSettingsButton];

    self.runtimeBannerHeightConstraint = [self.runtimeBanner.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.runtimeBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.runtimeBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.runtimeBannerHeightConstraint,

        [self.runtimeBannerLabel.leadingAnchor constraintEqualToAnchor:self.runtimeBanner.leadingAnchor constant:12.0],
        [self.runtimeBannerLabel.topAnchor constraintEqualToAnchor:self.runtimeBanner.topAnchor constant:6.0],

        [self.runtimeSettingsButton.trailingAnchor constraintEqualToAnchor:self.runtimeBanner.trailingAnchor constant:-12.0],
        [self.runtimeSettingsButton.centerYAnchor constraintEqualToAnchor:self.runtimeBanner.centerYAnchor],

        [self.runtimeInstallButton.trailingAnchor constraintEqualToAnchor:self.runtimeSettingsButton.leadingAnchor constant:-8.0],
        [self.runtimeInstallButton.centerYAnchor constraintEqualToAnchor:self.runtimeBanner.centerYAnchor],

        [self.runtimeBannerLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.runtimeInstallButton.leadingAnchor constant:-8.0],
    ]];
}

- (void)setupNavigationItems
{
    // 左：侧栏切换（打开历史抽屉，走已有的 handleShowHistory）
    UIButton *sidebarButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [sidebarButton setImage:[UIImage systemImageNamed:@"sidebar.left"
                                     withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightRegular]]
                   forState:UIControlStateNormal];
    sidebarButton.tintColor = UIColor.labelColor;
    sidebarButton.frame = CGRectMake(0.0, 0.0, 32.0, 32.0);
    sidebarButton.accessibilityLabel = @"历史会话";
    [sidebarButton addTarget:self action:@selector(handleShowHistory) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sidebarButton];

    // 右：git 分支图标 + 红色角标 99+（角标文案见 refreshGitBadge）
    UIButton *branchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [branchButton setImage:[UIImage systemImageNamed:@"arrow.triangle.branch"
                                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightRegular]]
                  forState:UIControlStateNormal];
    branchButton.tintColor = UIColor.labelColor;
    branchButton.accessibilityLabel = @"Git 变更";
    [branchButton addTarget:self action:@selector(handleOpenGitChanges) forControlEvents:UIControlEventTouchUpInside];
    branchButton.showsMenuAsPrimaryAction = NO;
    branchButton.menu = [self sourceControlMenu];
    self.sourceControlButton = branchButton;

    UILabel *badge = [[UILabel alloc] init];
    badge.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    badge.textColor = UIColor.whiteColor;
    badge.backgroundColor = UIColor.systemRedColor;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.text = kChatGitBadgeFallbackText;
    badge.hidden = YES;
    badge.layer.cornerRadius = 9.0;
    badge.layer.masksToBounds = YES;
    self.gitBadgeLabel = badge;

    // 分支图标 + 右上角角标装进同一个 bar button item
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 52.0, 34.0)];
    branchButton.frame = CGRectMake(4.0, 4.0, 28.0, 26.0);
    badge.frame = CGRectMake(24.0, 0.0, 28.0, 18.0);
    [container addSubview:branchButton];
    [container addSubview:badge];
    UIBarButtonItem *branchItem = [[UIBarButtonItem alloc] initWithCustomView:container];

    // 截图 01：顶栏右侧只有 git 分支图标 + 红角标，没有 ⋯ 按钮。
    // 「更多入口…」菜单仍从 git 图标长按菜单与「/」长按两处进入（handleComposerMenu 未变）。
    self.navigationItem.rightBarButtonItems = @[ branchItem ];
}

/// git 图标长按菜单：把工作区/价格/Agent 状态等入口也接上（点按仍然是 Git 变更）
- (UIMenu *)sourceControlMenu
{
    __weak typeof(self) weakSelf = self;
    UIAction *workspace = [UIAction actionWithTitle:@"工作区…"
                                              image:[UIImage systemImageNamed:@"folder"]
                                         identifier:nil
                                            handler:^(UIAction *action) {
        [weakSelf handleOpenWorkspaceManager];
    }];
    UIAction *pricing = [UIAction actionWithTitle:@"模型价格…"
                                            image:[UIImage systemImageNamed:@"tag"]
                                       identifier:nil
                                          handler:^(UIAction *action) {
        [weakSelf handleShowUsageDetails];
    }];
    UIAction *agent = [UIAction actionWithTitle:@"Agent 状态"
                                          image:[UIImage systemImageNamed:@"bolt.fill"]
                                     identifier:nil
                                        handler:^(UIAction *action) {
        [weakSelf handleAgentStatusInfo];
    }];
    UIAction *settings = [UIAction actionWithTitle:@"设置…"
                                             image:[UIImage systemImageNamed:@"gearshape"]
                                        identifier:nil
                                           handler:^(UIAction *action) {
        [weakSelf handleOpenSettings];
    }];
    UIAction *more = [UIAction actionWithTitle:@"更多入口…"
                                         image:[UIImage systemImageNamed:@"ellipsis.circle"]
                                    identifier:nil
                                       handler:^(UIAction *action) {
        [weakSelf handleComposerMenu];
    }];
    return [UIMenu menuWithTitle:@"" children:@[ workspace, pricing, agent, settings, more ]];
}

- (void)setupKeyboardNotifications
{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (UIView *)buildHistorySidebar
{
    // 历史抽屉的承载视图由 prepareHistoryDrawer 建立；这里给出一个占位容器，
    // 保持 setHistorySidebar: 的既有语义（老实现是直接挂一个面板）。
    UIView *sidebar = [[UIView alloc] init];
    sidebar.backgroundColor = UIColor.systemBackgroundColor;
    return sidebar;
}

#pragma mark - 输入 / 发送

- (void)handleSend
{
    [self submitCurrentComposerText];
}

- (void)handleAttach
{
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeItem ]];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)submitCurrentComposerText
{
    NSString *text = [self trimmedText:self.composerField.text];
    if (text.length == 0 && self.pendingAttachments.count == 0) return;

    if (![self chatRuntimeAvailable] || ![self chatProviderConfigured]) {
        // 运行时/供应商缺失：保留下输入，直接给可操作引导，不静默失败。
        [self refreshRuntimeBanner];
        [self presentRuntimeGuidanceForRuntime:![self chatRuntimeAvailable] detail:nil];
        return;
    }

    NSArray<NSString *> *attachments = [self.pendingAttachments copy];
    [self.pendingAttachments removeAllObjects];
    BOOL turnActiveNow = (self.chatTurnActive || self.chatEngine.persistentTurnInFlight);
    // 回合进行中走 turn/steer：accepted 之前不清空输入框（失败保留原文可重试）
    if (!turnActiveNow) {
        self.composerField.text = @"";
        [self updateInputHeight];
        [self refreshAttachmentPlaceholder];
    }
    [self setChatComposerPopupVisible:NO animated:NO];

    [self dispatchPromptText:text displayText:text attachments:attachments];
}

/// 原包同名选择器：真正的发送入口（文本 + 附件 → 落盘 → 走引擎）
- (id)beginPromptText:(id)arg1 displayText:(id)arg2 attachments:(id)arg3 existingUserMessage:(id)arg4 dismissKeyboard:(id)arg5
{
    NSString *prompt = [arg1 isKindOfClass:NSString.class] ? arg1 : @"";
    NSString *displayText = [arg2 isKindOfClass:NSString.class] ? arg2 : prompt;
    NSArray *attachments = [arg3 isKindOfClass:NSArray.class] ? arg3 : @[];
    if ([arg5 respondsToSelector:@selector(boolValue)] && [arg5 boolValue]) {
        [self.view endEditing:YES];
    }
    [self dispatchPromptText:prompt displayText:displayText attachments:attachments];
    return nil;
}

- (void)dispatchPromptText:(NSString *)prompt displayText:(NSString *)displayText attachments:(NSArray *)attachments
{
    NSString *composed = [self composedPromptWithText:prompt attachments:attachments];
    if (composed.length == 0) return;

    // 回合进行中 → turn/steer 插话（accepted 前不清输入框，失败保留原文）
    if (self.chatTurnActive || self.chatEngine.persistentTurnInFlight) {
        [self steerActiveTurnWithPrompt:composed displayText:(displayText.length > 0 ? displayText : composed)
                            attachments:attachments];
        return;
    }
    if (![self chatRuntimeAvailable] || ![self chatProviderConfigured]) {
        [self refreshRuntimeBanner];
        [self presentRuntimeGuidanceForRuntime:![self chatRuntimeAvailable] detail:nil];
        return;
    }

    // 1) 用户消息立即上屏 + 立刻写入 CAConversationStore
    [self appendMessageWithRole:CAMessageRoleUser text:(displayText.length > 0 ? displayText : composed) detail:nil];
    [self persistConversation];
    [self conversationDidChange];

    // 2) 进入运行态
    [self beginTurnWithTitle:@"思考中…" detail:nil];
    [self conversationDidChange];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:CADefaultsUsePersistentAppServer]) {
        [self sendPromptViaPersistentAppServer:composed attachments:attachments];
        return;
    }

    NSString *workspace = self.workspacePath ?: CARuntimePaths.documentsCodexDirectory;
    NSString *model = [defaults stringForKey:CADefaultsSelectedModel] ?: [defaults stringForKey:CADefaultsThirdPartyModel];
    NSString *sandbox = [defaults stringForKey:CADefaultsSandboxMode] ?: @"danger-full-access";
    NSString *executionMode = [defaults stringForKey:kChatExecutionModeDefaultsKey] ?: @"agent";

    CALog(CALogLevelInfo, @"CHAT", @"turn via exec workspace=%@ model=%@ sandbox=%@ mode=%@",
          workspace, model ?: @"(default)", sandbox, executionMode);

    __weak typeof(self) weakSelf = self;
    [[CACodexEngine sharedEngine] startExecWithPrompt:composed
                                            workspace:workspace
                                                model:model
                                        executionMode:executionMode
                                              sandbox:sandbox
                                               output:^(NSString *line, BOOL isStderr) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!NSThread.isMainThread) {
            dispatch_async(dispatch_get_main_queue(), ^{ [strongSelf handleEngineOutputLine:line isStderr:isStderr]; });
            return;
        }
        [strongSelf handleEngineOutputLine:line isStderr:isStderr];
    }
                                           completion:^(NSInteger exitStatus, NSString *errorMessage) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf finishTurnWithStatus:exitStatus message:errorMessage];
        });
    }];
}

- (void)sendPromptViaPersistentAppServer:(NSString *)prompt attachments:(NSArray *)attachments
{
    NSString *text = [self trimmedText:prompt];
    if (text.length == 0 && attachments.count == 0) return;

    NSString *composed = [self composedPromptWithText:text attachments:attachments];
    if (composed.length == 0) return;

    if (!self.chatTurnActive) {
        [self appendMessageWithRole:CAMessageRoleUser text:text detail:nil];
        [self persistConversation];
        [self conversationDidChange];
        [self beginTurnWithTitle:@"思考中…" detail:nil];
        [self conversationDidChange];
    }

    NSString *threadId = self.threadId;
    CALog(CALogLevelInfo, @"CHAT", @"turn via app-server thread=%@ chars=%lu", threadId ?: @"(new)", (unsigned long)composed.length);

    __weak typeof(self) weakSelf = self;
    [[CACodexEngine sharedEngine] sendPromptViaPersistentAppServer:composed
                                                          threadId:threadId
                                                        completion:^(NSInteger exitStatus, NSString *errorMessage) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf finishTurnWithStatus:exitStatus message:errorMessage];
        });
    }];
}

#pragma mark - turn/steer（回合进行中发送 = 插话）

/// 回合进行中点发送：走引擎 steerPrompt:attachments:completion:
/// accepted 才清输入框；失败保留输入内容，用户可重试。
- (void)steerActiveTurnWithPrompt:(NSString *)prompt displayText:(NSString *)displayText attachments:(NSArray *)attachments
{
    CACodexEngine *engine = self.chatEngine ?: [CACodexEngine sharedEngine];
    CALog(CALogLevelInfo, @"CHAT", @"steer requested chars=%lu canSteer=%@",
          (unsigned long)prompt.length, [engine canSteerActiveTurn] ? @"YES" : @"NO");

    __weak typeof(self) weakSelf = self;
    [engine steerPrompt:prompt attachments:attachments completion:^(BOOL ok, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (ok) {
                // 用户消息上屏 + 清输入框
                [strongSelf appendMessageWithRole:CAMessageRoleUser text:(displayText.length > 0 ? displayText : prompt) detail:nil];
                [strongSelf persistConversation];
                strongSelf.composerField.text = @"";
                [strongSelf updateInputHeight];
                [strongSelf refreshAttachmentPlaceholder];
                [strongSelf conversationDidChange];
            } else {
                // 失败：输入框内容保留，提示可重试
                [strongSelf appendNoticeText:[NSString stringWithFormat:@"插话失败：%@（输入已保留，可重试）",
                                              error.localizedDescription ?: @"未知原因"]];
                [strongSelf conversationDidChange];
            }
        });
    }];
}

- (void)handleStop
{
    CALog(CALogLevelInfo, @"CHAT", @"stop requested thread=%@", self.threadId ?: @"(none)");

    BOOL requested = NO;
    if (self.chatEngine.persistentTurnInFlight) {
        requested = YES;
        [self.chatEngine cancelCurrentTurnWithCompletion:^(BOOL ok) {
            CALog(ok ? CALogLevelInfo : CALogLevelWarn, @"CHAT", @"turn/interrupt ok=%@", ok ? @"YES" : @"NO");
        }];
    }
    id cancelled = [self.chatEngine cancelExecution];
    if ([cancelled respondsToSelector:@selector(boolValue)] && [cancelled boolValue]) requested = YES;
    if (!requested) {
        [self.chatEngine invalidatePersistentServerWithReason:@"user-stop"];
    }
    [self appendNoticeText:@"已请求停止当前运行"];
    [self finishTurnWithStatus:0 message:@"用户中断"];
}

- (void)handleNewChat
{
    [self saveActiveConversation];
    self.threadId = nil;
    [self.messages removeAllObjects];
    self.lastUsageSummary = nil;
    self.streamingAssistantMessage = nil;
    self.thinkingMessage = nil;
    [self.streamingMessagesByItemId removeAllObjects];
    [self.toolMessagesByItemId removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kChatActiveThreadDefaultsKey];

    CAConversationStore *store = [CAConversationStore sharedStore];
    self.activeRecord = [store createConversationForWorkspace:self.workspacePath];
    [self.conversationSidebar reloadConversations];
    [self conversationDidChange];
    [self renderStatusStrip];
    [self refreshRuntimeBanner];
    CALog(CALogLevelInfo, @"CHAT", @"new conversation id=%@", self.activeRecord.conversationId ?: @"(none)");
}

- (void)handleShowHistory
{
    [self prepareHistoryDrawer];
    if (!self.historyDrawer) return;
    [self.conversationSidebar setWorkspacePath:self.workspacePath];
    [self.conversationSidebar reloadConversations];
    [self setChatHistoryDrawerOpen:YES animated:YES];
}

- (void)handleOpenSettings
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CASettingsViewController alloc] init]];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)handleInstallRuntime
{
    [self presentRuntimeDiagnostics];
}

- (void)workspaceDidChange:(NSNotification *)notification
{
    NSString *workspace = notification.userInfo[@"workspacePath"];
    if (workspace.length > 0) {
        self.workspacePath = workspace;
        CALog(CALogLevelInfo, @"CHAT", @"workspace changed path=%@", workspace);
        [self refreshAttachmentPlaceholder];
        [self renderStatusStrip];
        [self loadActiveConversation];
        [self.conversationSidebar setWorkspacePath:workspace];
    }
}

#pragma mark - 运行时 / 供应商引导

- (BOOL)chatRuntimeAvailable
{
    return [self.chatEngine resolveCodexExecutable].length > 0;
}

- (BOOL)chatProviderConfigured
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:CADefaultsUseThirdPartyProvider]) {
        NSString *key = [CAProviderConfiguration.sharedConfiguration readAPIKeyWithError:NULL];
        if (key.length > 0) return YES;
        // 引擎侧也可能已经持有密钥（保存位置不同），一并认下
        return [self.chatEngine hasThirdPartyAPIKey];
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:CARuntimePaths.authJSONPath]) return YES;
    return self.chatEngine.isLoggedIn;
}

- (void)refreshRuntimeBanner
{
    BOOL runtimeOK = [self chatRuntimeAvailable];
    BOOL providerOK = [self chatProviderConfigured];
    BOOL needsAttention = (!runtimeOK || !providerOK);

    // 截图 01 底部那条只有「闪电圆钮 + Agent 协作就绪 药丸 + 垃圾桶」：
    // 运行时 / 凭据缺失不再往这条上堆文字与按钮（原包只用设置页里的状态文字表达，安装也由设置页的行触发），
    // 提示条恒为 0 高 + 空文案，状态交给既有的闪电圆钮（蓝=就绪，橙=待处理）。
    self.runtimeBannerLabel.text = @"";
    self.runtimeInstallButton.hidden = YES;
    self.runtimeSettingsButton.hidden = YES;
    self.runtimeBanner.hidden = YES;
    self.runtimeBannerHeightConstraint.constant = 0.0;
    self.agentStatusIcon.tintColor = needsAttention ? UIColor.systemOrangeColor : UIColor.systemBlueColor;

    CALog(CALogLevelDebug, @"RUNTIME", @"bottom bar state runtime=%d provider=%d", runtimeOK, providerOK);
}

- (void)presentRuntimeGuidanceForRuntime:(BOOL)missingRuntime detail:(NSString *)detail
{
    NSString *text = nil;
    if (missingRuntime) {
        text = @"发送被拦住了：本机还没有可用的 Codex 运行时。\n"
                "· 点上方「安装运行时」→ 诊断页会自动安装必需运行时；\n"
                "· 或去设置 → 运行时里手动装。";
    } else {
        text = @"发送被拦住了：还没有可用的供应商凭据。\n"
                "· 第三方：设置 → Provider，填 base_url / model / API Key；\n"
                "· 官方：设置 → 账号，用 API Key / Access Token / 设备码登录。";
    }
    if (detail.length > 0) text = [text stringByAppendingFormat:@"\n(%@)", detail];
    [self appendNoticeText:text];
    [self conversationDidChange];
    [self refreshRuntimeBanner];
}

- (id)presentRuntimeDiagnostics
{
    CADiagnosticsViewController *diagnostics = [[CADiagnosticsViewController alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:diagnostics];
    [self presentViewController:navigation animated:YES completion:^{
        [diagnostics run];
    }];
    return diagnostics;
}

- (id)presentSettingsForRequiredRuntimes
{
    return [self presentSettingsFocusingRequiredRuntimes:@YES];
}

- (id)presentSettingsFocusingRequiredRuntimes:(id)arg1
{
    CASettingsViewController *settings = [[CASettingsViewController alloc] init];
    settings.focusRequiredRuntimesOnAppear = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    [self presentViewController:navigation animated:YES completion:nil];
    return settings;
}

- (void)runtimeCatalogDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshRuntimeBanner];
        [self renderStatusStrip];
    });
}

#pragma mark - 附件 / 占位

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    for (NSURL *url in urls) {
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSString *destination = [CARuntimePaths.tmpDirectory stringByAppendingPathComponent:url.lastPathComponent];
        NSError *error = nil;
        [NSFileManager.defaultManager removeItemAtPath:destination error:NULL];
        if ([NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:destination] error:&error]) {
            [self.pendingAttachments addObject:destination];
        } else {
            CALog(CALogLevelWarn, @"CHAT", @"attachment copy failed %@: %@", url.path, error);
            [self.pendingAttachments addObject:url.path];
        }
        if (scoped) [url stopAccessingSecurityScopedResource];
    }
    [self refreshAttachmentPlaceholder];
}

- (void)refreshAttachmentPlaceholder
{
    if (self.pendingAttachments.count == 0) {
        self.attachmentHintLabel.text = [NSString stringWithFormat:@"未添加附件 · %@", [self runtimeSummaryText]];
    } else {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *path in self.pendingAttachments) {
            [names addObject:path.lastPathComponent ?: path];
        }
        self.attachmentHintLabel.text = [NSString stringWithFormat:@"附件 %lu 个：%@",
                                         (unsigned long)self.pendingAttachments.count,
                                         [names componentsJoinedByString:@"、"]];
    }
    // 没有附件时不占位（截图空态输入卡里只有 上下文 0% · 缓存 — 这一行）
    self.attachmentHintLabel.hidden = (self.pendingAttachments.count == 0);
    self.attachmentHintHeightConstraint.constant = self.attachmentHintLabel.hidden ? 0.0 : 15.0;
    [self applyComposerPlaceholder];
    [self updateSendButtonState];
}

- (void)applyComposerPlaceholder
{
    // 截图 01 的输入卡里只有「上下文 0% · 缓存 —」一行，卡内没有占位文案：
    // 占位池仍然保留（composerPlaceholderPool 供后续使用），但不再往输入卡上贴字。
    self.composerPlaceholderText = @"";
    self.inputPlaceholderLabel.text = @"";
    self.inputPlaceholderLabel.hidden = YES;
}

- (void)rotateComposerPlaceholderIfNeeded
{
    if (self.composerField.text.length > 0) return;
    self.composerPlaceholderIndex = self.composerPlaceholderIndex + 1;
}

- (NSArray *)composerPlaceholderPool
{
    NSArray<NSString *> *pool = [NSUserDefaults.standardUserDefaults arrayForKey:kChatPlaceholderPoolKey];
    if (pool.count > 0) return pool;
    return @[ @"描述你的任务，@ 引用文件，/ 调用技能",
              @"让 MT 智能体改代码、跑测试、查日志",
              @"直接说需求，例如：把设置页的登录流程补完",
              @"粘贴报错信息，我来定位问题" ];
}

- (NSString *)runtimeSummaryText
{
    CARuntimeCatalogEntry *entry = [[CARuntimeCatalog sharedCatalog] entryForID:@"codex"];
    NSString *version = entry.version.length > 0 ? entry.version : @"未安装";
    return [NSString stringWithFormat:@"Codex Runtime %@", version];
}

- (NSString *)trimmedText:(NSString *)text
{
    return [(text ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)composedPromptWithText:(NSString *)text attachments:(NSArray *)attachments
{
    if (attachments.count == 0) return text ?: @"";
    NSMutableString *composed = [NSMutableString stringWithString:text ?: @""];
    [composed appendString:@"\n\n附件："];
    for (NSString *path in attachments) {
        [composed appendFormat:@"\n- %@", path];
    }
    return composed;
}

#pragma mark - 消息渲染

- (void)appendMessageWithRole:(CAMessageRole)role text:(NSString *)text detail:(NSString *)detail
{
    CAMessageItem *message = [[CAMessageItem alloc] init];
    [message setRole:@((long long)role)];
    message.text = text ?: @"";
    if (detail.length > 0) message.activityDetail = detail;
    if (role == CAMessageRoleSystem) [message setActivityOfKind:CAMessageActivityKindNotice title:@"提示" detail:detail ?: @"" running:NO];
    [self.messages addObject:message];
    [self conversationDidChange];
}

- (void)appendNoticeText:(NSString *)text
{
    if (text.length == 0) return;
    CAMessageItem *message = [[CAMessageItem alloc] init];
    [message setRole:@(CAMessageRoleSystem)];
    [message setActivityOfKind:CAMessageActivityKindNotice title:@"提示" detail:text running:NO];
    message.text = text;
    [self.messages addObject:message];
}

- (void)finalizeStreamingMessages
{
    for (CAMessageItem *message in self.messages) {
        if (message.streaming) [message setStreamingFlag:NO];
    }
    [self.streamingMessagesByItemId removeAllObjects];
    self.streamingAssistantMessage = nil;
}

- (void)flushStreamingMessages
{
    [self finalizeStreamingMessages];
    [self.tableView reloadData];
    if (self.autoFollowLatest) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)refreshStreamingRow
{
    CAMessageItem *message = self.streamingAssistantMessage;
    if (!message) return;
    NSUInteger row = [self.messages indexOfObjectIdenticalTo:message];
    if (row == NSNotFound) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:CAMessageCell.class]) {
        [(CAMessageCell *)cell updateStreamingText:message.text];
    } else if (!cell) {
        // 行还没在屏幕上：下次 cellForRow 会用最新文本重建。
    }
    if (self.autoFollowLatest) [self scrollToBottomAnimated:NO];
}

- (void)scheduleStreamingRefresh
{
    if (self.chatStreamRefreshScheduled) return;
    self.chatStreamRefreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.chatStreamRefreshScheduled = NO;
        [strongSelf refreshStreamingRow];
    });
}

- (void)conversationDidChange
{
    [self.tableView reloadData];
    [self refreshWelcomeState];
    if (self.autoFollowLatest) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    NSInteger rows = [self tableView:self.tableView numberOfRowsInSection:0];
    if (rows <= 0) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:rows - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - 回合状态

- (void)beginTurnWithTitle:(NSString *)title detail:(NSString *)detail
{
    self.thinking = YES;
    self.chatTurnActive = YES;
    self.chatLastErrorMessage = nil;
    self.thinkingStartedAt = [NSDate date];
    self.thinkingSummaryCard = title ?: @"思考中…";
    [self.stderrTailLines removeAllObjects];

    CAMessageItem *thinking = [[CAMessageItem alloc] init];
    [thinking setRole:@(CAMessageRoleAssistant)];
    [thinking setActivityOfKind:CAMessageActivityKindThinking title:(title ?: @"思考中…") detail:detail ?: @"" running:YES];
    self.thinkingMessage = thinking;

    [self startPulseTimer];
    [self renderStatusStrip];
    [self.tableView reloadData];
    [self refreshWelcomeState];
}

- (void)finishTurnWithStatus:(NSInteger)status message:(NSString *)message
{
    if (!self.chatTurnActive && !self.thinking) return;
    self.chatTurnActive = NO;
    self.thinking = NO;
    [self stopPulseTimer];

    // 思考卡片收尾
    CAMessageItem *thinking = self.thinkingMessage;
    if (thinking) {
        BOOL failed = (status != 0 && !(status == 0 && message.length > 0));
        NSString *title = failed ? @"运行结束（有错误）" : @"已完成";
        if (message.length > 0 && [message isEqualToString:@"用户中断"]) title = @"已停止";
        double duration = [[NSDate date] timeIntervalSinceDate:thinking.activityStartedAt ?: [NSDate date]];
        [thinking setActivityDuration:@(duration)];
        [thinking setActivityOfKind:CAMessageActivityKindThinking title:title detail:thinking.activityDetail running:NO];
        self.thinkingMessage = nil;
    }

    // 流式消息收尾（内容补齐 + 去掉光标）
    [self finalizeStreamingMessages];

    // 错误信息：给出可读摘要（引擎错误 + stderr 尾巴）
    NSString *errorLine = nil;
    if (message.length > 0 && ![message isEqualToString:@"用户中断"]) {
        errorLine = message;
    } else if (status != 0) {
        errorLine = [NSString stringWithFormat:@"运行结束（退出码 %ld）", (long)status];
    }
    if (errorLine.length > 0) {
        self.chatLastErrorMessage = errorLine;
        NSMutableString *notice = [NSMutableString stringWithFormat:@"出错了：%@", errorLine];
        if (self.stderrTailLines.count > 0) {
            [notice appendString:@"\n\n最近 stderr：\n"];
            [notice appendString:[self.stderrTailLines componentsJoinedByString:@"\n"]];
        }
        [self appendNoticeText:notice];
    }

    [self.tableView reloadData];
    [self renderStatusStrip];
    [self persistConversation];
    [self.conversationSidebar reloadConversations];
    [self refreshWelcomeState];
    if (self.autoFollowLatest) [self scrollToBottomAnimated:YES];
}

- (void)updateThinkingDetail:(NSString *)detail running:(BOOL)running
{
    CAMessageItem *thinking = self.thinkingMessage;
    if (!thinking) {
        // 没在思考态（例如上一轮已结束）→ 作为一条独立卡片追加
        CAMessageItem *card = [[CAMessageItem alloc] init];
        [card setRole:@(CAMessageRoleAssistant)];
        [card setActivityOfKind:(running ? CAMessageActivityKindThinking : CAMessageActivityKindNotice)
                          title:(running ? @"思考中…" : @"提示")
                         detail:detail ?: @""
                        running:running];
        [self.messages addObject:card];
        if (running) self.thinkingMessage = card;
        [self.tableView reloadData];
        return;
    }
    if (detail.length > 0) {
        [thinking setActivityOfKind:CAMessageActivityKindThinking
                              title:thinking.activityTitle ?: @"思考中…"
                             detail:detail
                            running:running];
    } else {
        [thinking setActivityOfKind:CAMessageActivityKindThinking
                              title:thinking.activityTitle ?: @"思考中…"
                             detail:thinking.activityDetail ?: @""
                            running:running];
    }
    self.thinkingSummaryCard = detail.length > 0 ? detail : (thinking.activityTitle ?: @"思考中…");
    NSUInteger row = [self.messages indexOfObjectIdenticalTo:thinking];
    if (row != NSNotFound) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
        if ([cell isKindOfClass:CAThinkingCell.class]) [(CAThinkingCell *)cell configureWithMessage:thinking];
    }
    if (self.thinking) {
        NSUInteger thinkingRow = self.messages.count;
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)thinkingRow inSection:0]];
        if ([cell isKindOfClass:CAThinkingCell.class]) [(CAThinkingCell *)cell configureWithMessage:thinking];
    }
    [self renderStatusStrip];
}

#pragma mark - 引擎事件路由（exec --json 与 app-server 通知共用）

- (void)handleEngineOutputLine:(NSString *)line isStderr:(BOOL)isStderr
{
    if (line.length == 0) return;

    if (isStderr) {
        [self.stderrTailLines addObject:line];
        while (self.stderrTailLines.count > kChatStderrTailLimit) {
            [self.stderrTailLines removeObjectAtIndex:0];
        }
        [self renderStreamTail:[NSString stringWithFormat:@"stderr %@", line]];
        return;
    }

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![object isKindOfClass:NSDictionary.class]) {
        [self renderStreamTail:line];
        return;
    }
    [self handleEngineEvent:object source:@"exec"];
}

- (void)engineDidEmitNotification:(NSNotification *)notification
{
    NSString *method = notification.userInfo[CACodexEngineNotificationMethodKey];
    NSDictionary *params = notification.userInfo[CACodexEngineNotificationParamsKey];
    if (![method isKindOfClass:NSString.class] || method.length == 0) return;
    if (![params isKindOfClass:NSDictionary.class]) params = @{};

    NSDictionary *event = @{ @"method": method, @"params": params };
    if (NSThread.isMainThread) {
        [self handleEngineEvent:event source:@"app-server"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf handleEngineEvent:event source:@"app-server"];
    });
}

- (void)handleEngineEvent:(NSDictionary *)event source:(NSString *)source
{
    NSDictionary *params = [event[@"params"] isKindOfClass:NSDictionary.class] ? event[@"params"] : event;
    NSDictionary *msg = [event[@"msg"] isKindOfClass:NSDictionary.class] ? event[@"msg"] : nil;
    if (msg) params = msg;

    NSString *method = [event[@"method"] isKindOfClass:NSString.class] ? event[@"method"] : nil;
    NSString *type = [params[@"type"] isKindOfClass:NSString.class] ? params[@"type"] : nil;
    NSString *rawName = method ?: type ?: @"";
    NSString *name = rawName.lowercaseString;

    // 服务端用户输入请求（item/tool/requestUserInput）：弹计划/决策卡，点完选项回包给 app-server
    if (method.length > 0 && [method isEqualToString:CARPCItemRequestUserInput]) {
        NSNumber *requestID = self.pendingUserInputRequestID ?: self.chatEngine.pendingUserInputRequestID;
        id rawRID = params[@"id"];
        if ([rawRID isKindOfClass:NSNumber.class]) requestID = rawRID;
        else if ([rawRID isKindOfClass:NSString.class]) requestID = @([(NSString *)rawRID integerValue]);
        self.pendingUserInputRequestID = requestID;
        self.pendingUserInputParams = params;
        [self presentDecisionCardForUserInput:params requestID:requestID];
        return;
    }

    [self rememberThreadIdentifierFromPayload:params];
    [self consumeUsageFromPayload:params];

    // P1 补齐（原包方法对齐）：thread/tokenUsage/updated（及 token_count 变体）→ 上下文百分比实时化
    {
        NSString *lowerMethod = name;
        if ([lowerMethod containsString:@"tokenusage"] || [lowerMethod containsString:@"token_usage"]
            || [lowerMethod containsString:@"token_count"] || [lowerMethod containsString:@"tokencount"]) {
            [self applyTokenUsagePayload:params];
        }
    }

    // 1) 错误事件
    BOOL isError = [name containsString:@"error"] || params[@"error"] != nil;
    if (isError && ![name containsString:@"turn"]) {
        NSString *text = [self textFromPayload:params];
        if (text.length == 0 && [params[@"error"] isKindOfClass:NSString.class]) text = params[@"error"];
        if (text.length == 0) text = rawName;
        [self appendNoticeText:[NSString stringWithFormat:@"引擎报错：%@", text]];
        [self.tableView reloadData];
        return;
    }

    // 2) 回合终止（真正的收尾在引擎 completion 回调里做，这里只更新状态条）
    if ([name containsString:@"turn/completed"] || [name containsString:@"turn.completed"]
        || [name containsString:@"turn/failed"] || [name containsString:@"turn.failed"]
        || [name containsString:@"turn/aborted"]) {
        [self renderStatusStrip];
        return;
    }

    // 3) 增量文本
    NSString *delta = [params[@"delta"] isKindOfClass:NSString.class] ? params[@"delta"] : nil;
    NSString *itemId = params[@"itemId"] ?: params[@"item_id"];
    if (![itemId isKindOfClass:NSString.class]) itemId = nil;
    if (delta.length > 0) {
        if ([name containsString:@"reasoning"]) {
            [self updateThinkingDetail:delta running:YES];
        } else if ([name containsString:@"command"] || [name containsString:@"output"] || [name containsString:@"filechange"]) {
            [self updateToolCardForItem:params itemId:itemId ?: @"command-output" method:name];
        } else {
            CAMessageItem *message = [self assistantMessageForItemId:itemId ?: @"stream-main" createIfNeeded:YES];
            [message appendText:delta];
            [self scheduleStreamingRefresh];
        }
        return;
    }

    // 4) item 快照事件
    NSDictionary *item = [params[@"item"] isKindOfClass:NSDictionary.class] ? params[@"item"] : nil;
    if (item) {
        [self handleEngineItem:item method:name];
        return;
    }

    // 5) reasoning / 状态类文本
    if ([name containsString:@"reasoning"]) {
        NSString *text = [self textFromPayload:params];
        if (text.length > 0) [self updateThinkingDetail:text running:YES];
        return;
    }

    // 6) 纯文本事件（老版本 exec 的事件形态）
    NSString *text = [self textFromPayload:params];
    if (text.length > 0) {
        BOOL deltaLike = [name containsString:@"delta"];
        if (deltaLike) {
            CAMessageItem *message = [self assistantMessageForItemId:@"stream-main" createIfNeeded:YES];
            [message appendText:text];
            [self scheduleStreamingRefresh];
        } else if ([name containsString:@"agent_message"] || [name containsString:@"message"]) {
            CAMessageItem *message = [self assistantMessageForItemId:itemId ?: @"stream-main" createIfNeeded:YES];
            message.text = text;
            [self scheduleStreamingRefresh];
        } else {
            [self renderStreamTail:(type.length > 0 ? type : rawName)];
        }
        return;
    }

    if (rawName.length > 0) [self renderStreamTail:rawName];
}

- (void)handleEngineItem:(NSDictionary *)item method:(NSString *)method
{
    id rawItemType = item[@"type"];
    NSString *itemType = [rawItemType isKindOfClass:NSString.class] ? [rawItemType lowercaseString] : @"";
    id rawItemId = item[@"id"];
    NSString *itemId = [rawItemId isKindOfClass:NSString.class] ? rawItemId : [[NSUUID UUID] UUIDString];

    if ([itemType containsString:@"agent_message"] || [itemType containsString:@"assistant"] || [itemType containsString:@"message"]) {
        NSString *text = [self textFromPayload:item];
        if (text.length == 0) return;
        CAMessageItem *message = [self assistantMessageForItemId:itemId createIfNeeded:YES];
        if ([method containsString:@"delta"]) {
            [message appendText:text];
        } else {
            message.text = text;
        }
        if ([method containsString:@"completed"] || [method containsString:@"done"]) {
            [message setStreamingFlag:NO];
        }
        [self scheduleStreamingRefresh];
        return;
    }

    if ([itemType containsString:@"reasoning"]) {
        NSString *summary = item[@"summary"] ?: item[@"text"] ?: item[@"content"];
        if (![summary isKindOfClass:NSString.class]) {
            NSArray *parts = [item[@"summary"] isKindOfClass:NSArray.class] ? item[@"summary"] : nil;
            if (parts.count > 0) summary = [parts componentsJoinedByString:@"\n"];
        }
        if ([summary isKindOfClass:NSString.class] && summary.length > 0) {
            [self updateThinkingDetail:summary running:![method containsString:@"completed"]];
        }
        return;
    }

    if ([itemType containsString:@"command"] || [itemType containsString:@"tool"]
        || [itemType containsString:@"file_change"] || [itemType containsString:@"filechange"]
        || [itemType containsString:@"patch"] || [itemType containsString:@"search"]) {
        [self updateToolCardForItem:item itemId:itemId method:method];
        return;
    }

    if ([itemType containsString:@"error"]) {
        NSString *text = [self textFromPayload:item];
        if (text.length > 0) {
            [self appendNoticeText:[NSString stringWithFormat:@"引擎报错：%@", text]];
            [self.tableView reloadData];
        }
        return;
    }
}

- (CAMessageItem *)assistantMessageForItemId:(NSString *)itemId createIfNeeded:(BOOL)create
{
    NSString *key = itemId.length > 0 ? itemId : @"stream-main";
    CAMessageItem *message = self.streamingMessagesByItemId[key];
    if (message || !create) return message;

    message = [[CAMessageItem alloc] init];
    [message setRole:@(CAMessageRoleAssistant)];
    [message setStreamingFlag:YES];
    message.text = @"";
    self.streamingMessagesByItemId[key] = message;
    self.streamingAssistantMessage = message;
    [self.messages addObject:message];
    [self.tableView reloadData];
    return message;
}

- (void)updateToolCardForItem:(NSDictionary *)item itemId:(NSString *)itemId method:(NSString *)method
{
    NSString *key = itemId.length > 0 ? itemId : @"tool";
    CAMessageItem *message = self.toolMessagesByItemId[key];
    NSString *command = [self toolCommandDescriptionForItem:item];
    if (!message) {
        CAToolItem *tool = [[CAToolItem alloc] init];
        tool.itemId = key;
        tool.command = command.length > 0 ? command : @"工具调用";
        message = [[CAMessageItem alloc] init];
        [message setRole:@(CAMessageRoleAssistant)];
        [message setActivityOfKind:CAMessageActivityKindTool
                            title:@"工具调用"
                           detail:tool.command
                          running:YES];
        message.toolItem = tool;
        self.toolMessagesByItemId[key] = message;
        [self.messages addObject:message];
        [self.tableView reloadData];
        if (self.autoFollowLatest) [self scrollToBottomAnimated:NO];
    }

    CAToolItem *tool = message.toolItem;
    if (!tool) return;
    if (command.length > 0) tool.command = command;

    // 命令输出的增量（app-server: item/commandExecution/outputDelta）
    id rawDelta = item[@"delta"];
    if ([rawDelta isKindOfClass:NSString.class] && [rawDelta length] > 0) {
        [tool chatAppendOutput:rawDelta];
    }

    id rawOutput = item[@"aggregated_output"] ?: item[@"output"] ?: item[@"stdout"] ?: item[@"text"];
    if ([rawOutput isKindOfClass:NSString.class] && [rawOutput length] > 0) {
        [tool setOutput:rawOutput];
    } else if ([rawOutput isKindOfClass:NSArray.class] && [(NSArray *)rawOutput count] > 0) {
        [tool setOutput:[(NSArray *)rawOutput componentsJoinedByString:@"\n"]];
    }

    id rawStatus = item[@"status"];
    NSString *status = [rawStatus isKindOfClass:NSString.class] ? [rawStatus lowercaseString] : method;
    NSNumber *exitCode = [item[@"exit_code"] isKindOfClass:NSNumber.class] ? item[@"exit_code"] : item[@"exitCode"];
    BOOL running = ![status containsString:@"completed"] && ![status containsString:@"fail"] && ![status containsString:@"done"];
    if (running) {
        [tool chatSetStatus:CAToolStatusRunning exitCode:0];
    } else if ([status containsString:@"fail"] || (exitCode && exitCode.integerValue != 0)) {
        [tool chatSetStatus:CAToolStatusFailed exitCode:(exitCode ? exitCode.integerValue : 1)];
    } else {
        [tool chatSetStatus:CAToolStatusSucceeded exitCode:(exitCode ? exitCode.integerValue : 0)];
    }
    [message setActivityOfKind:CAMessageActivityKindTool
                        title:@"工具调用"
                       detail:tool.command ?: @""
                      running:running];

    NSUInteger row = [self.messages indexOfObjectIdenticalTo:message];
    if (row != NSNotFound) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
        if ([cell isKindOfClass:CAToolCardCell.class]) [(CAToolCardCell *)cell configureWithToolItem:tool];
    }
    [self renderStatusStrip];
}

- (NSString *)toolCommandDescriptionForItem:(NSDictionary *)item
{
    NSArray<NSString *> *keys = @[ @"command", @"name", @"query", @"path", @"server", @"tool" ];
    for (NSString *key in keys) {
        id value = item[key];
        if ([value isKindOfClass:NSString.class] && [value length] > 0) return value;
    }
    NSArray *changes = [item[@"changes"] isKindOfClass:NSArray.class] ? item[@"changes"] : nil;
    if (changes.count > 0) {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (id change in changes) {
            if ([change isKindOfClass:NSDictionary.class] && [change[@"path"] isKindOfClass:NSString.class]) {
                [paths addObject:change[@"path"]];
            } else if ([change isKindOfClass:NSString.class]) {
                [paths addObject:change];
            }
        }
        if (paths.count > 0) return [paths componentsJoinedByString:@" "];
    }
    // 认不出来就返回 nil：纯增量事件（只有 delta/itemId）不应该把已有命令名覆盖掉
    return nil;
}

- (NSString *)textFromPayload:(NSDictionary *)payload
{
    NSArray<NSString *> *keys = @[ @"text", @"message", @"content", @"delta", @"output_text", @"summary" ];
    for (NSString *key in keys) {
        id value = payload[key];
        if ([value isKindOfClass:NSString.class] && [value length] > 0) return value;
        if ([value isKindOfClass:NSArray.class]) {
            NSMutableArray<NSString *> *parts = [NSMutableArray array];
            for (id item in (NSArray *)value) {
                if ([item isKindOfClass:NSString.class]) {
                    [parts addObject:item];
                } else if ([item isKindOfClass:NSDictionary.class] && [item[@"text"] isKindOfClass:NSString.class]) {
                    [parts addObject:item[@"text"]];
                }
            }
            if (parts.count > 0) return [parts componentsJoinedByString:@""];
        }
        if ([value isKindOfClass:NSDictionary.class] && [value[@"text"] isKindOfClass:NSString.class]) {
            return value[@"text"];
        }
    }
    return @"";
}

- (void)rememberThreadIdentifierFromPayload:(NSDictionary *)payload
{
    NSString *identifier = payload[@"thread_id"] ?: payload[@"threadId"] ?: payload[@"conversation_id"] ?: payload[@"conversationId"];
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return;

    NSString *turnId = payload[@"turn_id"] ?: payload[@"turnId"] ?: payload[@"id"];
    if ([turnId isKindOfClass:NSString.class] && turnId.length > 0) self.activeTurnIdentifier = turnId;

    if ([identifier isEqualToString:self.threadId ?: @""]) return;
    self.threadId = identifier;
    [NSUserDefaults.standardUserDefaults setObject:identifier forKey:kChatActiveThreadDefaultsKey];
    CALog(CALogLevelInfo, @"CHAT", @"thread id=%@", identifier);
}

- (void)consumeUsageFromPayload:(NSDictionary *)payload
{
    NSDictionary *usage = [payload[@"usage"] isKindOfClass:NSDictionary.class] ? payload[@"usage"] : nil;
    if (!usage) return;
    NSNumber *input = usage[@"input_tokens"] ?: usage[@"prompt_tokens"];
    NSNumber *output = usage[@"output_tokens"] ?: usage[@"completion_tokens"];
    NSNumber *total = usage[@"total_tokens"];
    if (!input && !output && !total) return;
    self.lastUsageSummary = [NSString stringWithFormat:@"tokens in=%@ out=%@ total=%@",
                             input ?: @0, output ?: @0, total ?: @"?"];
    [self renderStatusStrip];
}

// P1 补齐（原包方法对齐）：thread/tokenUsage/updated 宽松解析 → composer 卡上下文行
- (void)applyTokenUsagePayload:(NSDictionary *)payload
{
    if (![payload isKindOfClass:NSDictionary.class]) return;

    // 候选容器：total_token_usage / model_usage / context_window / 顶层
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray arrayWithObject:payload];
    for (NSString *key in @[ @"total_token_usage", @"totalTokenUsage", @"model_usage", @"modelUsage",
                             @"context_window", @"contextWindow", @"info", @"token_usage", @"tokenUsage" ]) {
        id container = payload[key];
        if ([container isKindOfClass:NSDictionary.class]) [candidates addObject:container];
    }
    if ([payload[@"model_usage"] isKindOfClass:NSArray.class]) {
        for (id entry in payload[@"model_usage"]) {
            if ([entry isKindOfClass:NSDictionary.class]) [candidates addObject:entry];
        }
    }

    // 累计窗口优先 total_token_usage（含 cached_input_tokens / input_tokens）
    unsigned long long input = 0, cached = 0, output = 0, total = 0;
    BOOL sawAny = NO;
    unsigned long long contextLimit = 0;
    for (NSDictionary *candidate in candidates) {
        NSNumber *value = nil;
        if ((value = [self p1NumberFrom:candidate[@"input_tokens"]] ?: [self p1NumberFrom:candidate[@"inputTokens"]])) {
            input = MAX(input, value.unsignedLongLongValue); sawAny = YES;
        }
        if ((value = [self p1NumberFrom:candidate[@"cached_input_tokens"]] ?: [self p1NumberFrom:candidate[@"cachedInputTokens"]])) {
            cached = MAX(cached, value.unsignedLongLongValue); sawAny = YES;
        }
        if ((value = [self p1NumberFrom:candidate[@"output_tokens"]] ?: [self p1NumberFrom:candidate[@"outputTokens"]])) {
            output = MAX(output, value.unsignedLongLongValue); sawAny = YES;
        }
        if ((value = [self p1NumberFrom:candidate[@"total_tokens"]] ?: [self p1NumberFrom:candidate[@"totalTokens"]])) {
            total = MAX(total, value.unsignedLongLongValue); sawAny = YES;
        }
        if ((value = [self p1NumberFrom:candidate[@"context_window"]] ?: [self p1NumberFrom:candidate[@"contextWindow"]]
            ?: [self p1NumberFrom:candidate[@"limit"]])) {
            contextLimit = MAX(contextLimit, value.unsignedLongLongValue);
        }
    }
    if (!sawAny) return;

    unsigned long long used = total > 0 ? total : (input + output);
    if (used == 0) return;
    if (contextLimit == 0) contextLimit = [self p1ContextWindowLimit];
    if (contextLimit > 0) {
        self.contextWindowUsedPercent = MIN(100.0, ((double)used / (double)contextLimit) * 100.0);
        self.hasContextUsage = YES;
    }
    if (input > 0) {
        self.cacheHitPercent = MIN(100.0, ((double)cached / (double)MAX(input, 1)) * 100.0);
    }
    [self renderContextCaption];
}

- (nullable NSNumber *)p1NumberFrom:(id)value
{
    if ([value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) return @([(NSString *)value doubleValue]);
    return nil;
}

- (unsigned long long)p1ContextWindowLimit
{
    // 优先引擎的第三方 context window，其次默认 272k（原包 gpt 系上限观测）
    if ([self.chatEngine respondsToSelector:@selector(contextWindowLimitTokens)]) {
        id limit = [self.chatEngine contextWindowLimitTokens];
        if ([limit respondsToSelector:@selector(unsignedLongLongValue)]) return [limit unsignedLongLongValue];
    }
    return 272000ull;
}

/// composer 卡首行「上下文 N% · 缓存 M」数字实时化（文案结构不动，只改数字）
- (void)renderContextCaption
{
    if (!self.hasContextUsage) {
        self.contextCaption.text = kChatContextCaptionText;
        return;
    }
    NSInteger percent = (NSInteger)round(self.contextWindowUsedPercent);
    NSString *cacheText = (self.cacheHitPercent > 0.0)
        ? [NSString stringWithFormat:@"%d%%", (int)round(self.cacheHitPercent)]
        : @"—";
    self.contextCaption.text = [NSString stringWithFormat:@"上下文 %ld%% · 缓存 %@",
                                (long)percent, cacheText];
}

- (void)renderStreamTail:(NSString *)line
{
    if (line.length == 0) return;
    [self.rawTailLines addObject:line];
    while (self.rawTailLines.count > kChatRawTailLimit) {
        [self.rawTailLines removeObjectAtIndex:0];
    }
    [self renderStatusStrip];
}

#pragma mark - 状态条

- (void)renderStatusStrip
{
    if (self.thinking) {
        self.statusTitleLabel.text = self.thinkingSummaryCard.length > 0 ? self.thinkingSummaryCard : @"思考中…";
        self.statusDot.backgroundColor = UIColor.systemOrangeColor;
    } else if (self.chatLastErrorMessage.length > 0) {
        self.statusTitleLabel.text = @"上次运行出错";
        self.statusDot.backgroundColor = UIColor.systemRedColor;
    } else {
        self.statusTitleLabel.text = @"就绪";
        self.statusDot.backgroundColor = UIColor.systemGreenColor;
    }

    NSString *tail = self.rawTailLines.lastObject ?: @"";
    if (tail.length > 96) {
        tail = [NSString stringWithFormat:@"…%@", [tail substringFromIndex:tail.length - 96]];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *workspace = self.workspacePath.lastPathComponent;
    if (workspace.length > 0) [parts addObject:workspace];
    if (self.lastUsageSummary.length > 0) [parts addObject:self.lastUsageSummary];
    if (tail.length > 0) [parts addObject:tail];
    if (parts.count == 0) [parts addObject:[self runtimeSummaryText]];
    self.statusDetailLabel.text = [parts componentsJoinedByString:@" · "];

    self.stopButton.hidden = !self.thinking;
    self.sendButton.hidden = self.thinking;
}

- (void)updateSendButtonState
{
    BOOL hasText = [self trimmedText:self.composerField.text].length > 0 || self.pendingAttachments.count > 0;
    self.sendButton.enabled = hasText;
    self.sendButton.alpha = hasText ? 1.0 : 0.4;
    self.inputPlaceholderLabel.hidden = YES;
}

- (void)updateInputHeight
{
    CGFloat height = [self.composerField sizeThatFits:CGSizeMake(self.composerField.bounds.size.width, CGFLOAT_MAX)].height;
    height = MAX(36.0, MIN(height, 140.0));
    self.inputHeightConstraint.constant = height;
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.messages.count + (self.thinking ? 1 : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.thinking && indexPath.row == (NSInteger)self.messages.count) {
        CAThinkingCell *cell = (CAThinkingCell *)[tableView dequeueReusableCellWithIdentifier:kChatThinkingCellReuseIdentifier forIndexPath:indexPath];
        [cell configureWithMessage:self.thinkingMessage];
        return cell;
    }

    CAMessageItem *message = (indexPath.row >= 0 && (NSUInteger)indexPath.row < self.messages.count) ? self.messages[(NSUInteger)indexPath.row] : nil;
    if (!message) {
        CAMessageCell *cell = (CAMessageCell *)[tableView dequeueReusableCellWithIdentifier:kChatMessageCellReuseIdentifier forIndexPath:indexPath];
        [cell configureWithMessage:message];
        return cell;
    }

    if (message.toolItem) {
        CAToolCardCell *cell = (CAToolCardCell *)[tableView dequeueReusableCellWithIdentifier:kChatToolCardCellReuseIdentifier forIndexPath:indexPath];
        [cell configureWithToolItem:message.toolItem];
        return cell;
    }

    CAMessageCell *cell = (CAMessageCell *)[tableView dequeueReusableCellWithIdentifier:kChatMessageCellReuseIdentifier forIndexPath:indexPath];
    [cell configureWithMessage:message];
    return cell;
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    [self updateInputHeight];
    [self updateSendButtonState];
    self.inputPlaceholderLabel.hidden = textView.text.length > 0;
    [self updateComposerSlashMenuState];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@"\n"]) {
        if (self.composerPopupVisible) {
            [self.composerPopupView selectHighlightedItem];
            return NO;
        }
        [self submitCurrentComposerText];
        return NO;
    }
    return YES;
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    [self updateComposerSlashMenuState];
}

#pragma mark - “/” 目录面板（CAComposerCatalog）

- (id)setupComposerPopup
{
    CAComposerPopupView *popup = [[CAComposerPopupView alloc] init];
    popup.hidden = YES;
    // 原版字符串（__ustring 提取）：标题「引用 MCP、插件与 Skills」+ 右侧计数
    popup.headerTitle = @"引用 MCP、插件与 Skills";
    popup.headerHint = [self composerPopupCountHint];

    __weak typeof(self) weakSelf = self;
    popup.onSelectItem = ^(CAComposerPopupItem *item) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf handleComposerPopupItem:item];
    };
    popup.onClose = ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf) [strongSelf setChatComposerPopupVisible:NO animated:YES];
    };
    [self.view addSubview:popup];
    self.composerPopupView = popup;

    self.composerPopupHeightConstraint = [popup.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [popup.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8.0],
        [popup.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8.0],
        [popup.bottomAnchor constraintEqualToAnchor:self.runtimeBanner.topAnchor constant:-6.0],
        self.composerPopupHeightConstraint,
    ]];
    return popup;
}

- (void)setChatComposerPopupVisible:(BOOL)visible animated:(BOOL)animated
{
    [self setComposerPopupVisible:@(visible) animated:@(animated)];
}

- (void)setComposerPopupVisible:(id)arg1 animated:(id)arg2
{
    BOOL visible = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
    BOOL animated = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;
    if (!self.composerPopupView) return;

    self.composerPopupVisible = visible;
    self.composerPopupHeightConstraint.constant = visible ? (CGFloat)[self.composerPopupView preferredHeight] : 0.0;
    if (visible) {
        self.composerPopupView.hidden = NO;
        self.composerPopupView.alpha = animated ? 0.0 : 1.0;
    }

    void (^changes)(void) = ^{
        self.composerPopupView.alpha = visible ? 1.0 : 0.0;
        [self.view layoutIfNeeded];
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (!visible) self.composerPopupView.hidden = YES;
    };
    if (animated) {
        [UIView animateWithDuration:0.16 animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (id)composerSlashContext
{
    UITextView *field = self.composerField;
    NSString *text = field.text ?: @"";
    NSRange selection = field.selectedRange;
    if (selection.location == NSNotFound || selection.location > text.length) return nil;

    NSRange lineRange = [text lineRangeForRange:NSMakeRange(selection.location, 0)];
    NSString *linePrefix = [text substringWithRange:NSMakeRange(lineRange.location, selection.location - lineRange.location)];
    NSRange slash = [linePrefix rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location == NSNotFound) return nil;
    if (slash.location > 0) {
        unichar previous = [linePrefix characterAtIndex:slash.location - 1];
        if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:previous]) return nil;
    }
    NSString *token = [linePrefix substringFromIndex:slash.location];
    if ([token rangeOfString:@" "].location != NSNotFound) return nil;

    return @{ @"token": token,
              @"filter": token.length > 1 ? [token substringFromIndex:1] : @"",
              @"location": @(lineRange.location + slash.location),
              @"length": @(token.length) };
}

- (id)updateComposerSlashMenuState
{
    NSString *text = self.composerField.text ?: @"";
    NSString *suppressed = [self composerSlashSuppressedText];
    if ([suppressed isKindOfClass:NSString.class] && suppressed.length > 0 && [suppressed isEqualToString:text]) {
        return @NO;
    }
    [self setComposerSlashSuppressedText:nil];

    NSDictionary *context = [self composerSlashContext];
    if (!context) {
        if (self.composerPopupVisible) [self setChatComposerPopupVisible:NO animated:YES];
        return @NO;
    }

    self.composerSlashFilter = context[@"filter"] ?: @"";
    [self reloadSlashComposerPopupPreserving:@NO];
    [self setChatComposerPopupVisible:@YES animated:YES];

    // 目录可能是空的（首次进入）：触发一次扫描，回来后自动刷新
    if (CAComposerCatalog.sharedCatalog.items.count == 0) {
        __weak typeof(self) weakSelf = self;
        [CAComposerCatalog.sharedCatalog refreshForWorkspace:self.workspacePath force:NO completion:^(NSError *error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.composerPopupVisible) [strongSelf reloadSlashComposerPopupPreserving:@YES];
            });
            if (error) CALog(CALogLevelWarn, @"CHAT", @"composer catalog refresh failed: %@", error.localizedDescription);
        }];
    }
    return @YES;
}

- (id)openSlashComposerPopupTextDriven:(id)arg1
{
    BOOL show = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    if (!show) {
        [self setChatComposerPopupVisible:NO animated:YES];
        return @NO;
    }
    return [self updateComposerSlashMenuState];
}

- (id)reloadSlashComposerPopupPreserving:(id)arg1
{
    NSArray *sections = [self composerPopupSections];
    self.composerPopupView.headerHint = [self composerPopupCountHint];
    [self.composerPopupView setSections:sections preserveHighlight:arg1 ?: @NO];
    if (self.composerPopupVisible) {
        self.composerPopupHeightConstraint.constant = (CGFloat)[self.composerPopupView preferredHeight];
    }
    return @(sections.count);
}

- (NSArray *)composerPopupSections
{
    NSString *filter = (self.composerSlashFilter ?: @"").lowercaseString;
    NSArray<CAComposerCatalogItem *> *items = CAComposerCatalog.sharedCatalog.items ?: @[];

    NSMutableDictionary<NSNumber *, NSMutableArray<CAComposerPopupItem *> *> *grouped = [NSMutableDictionary dictionary];
    for (CAComposerCatalogItem *entry in items) {
        if (![entry isKindOfClass:CAComposerCatalogItem.class]) continue;
        if (filter.length > 0) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", entry.name ?: @"", entry.displayTitle ?: @""].lowercaseString;
            if ([haystack rangeOfString:filter].location == NSNotFound) continue;
        }
        CAComposerPopupItem *item = [self composerPopupItemForCatalogEntry:entry];
        if (!item) continue;
        NSNumber *key = @((NSInteger)entry.kind);
        NSMutableArray *bucket = grouped[key];
        if (!bucket) {
            bucket = [NSMutableArray array];
            grouped[key] = bucket;
        }
        [bucket addObject:item];
    }

    NSMutableArray<CAComposerPopupSection *> *sections = [NSMutableArray array];
    NSArray<NSNumber *> *order = @[ @(CAComposerCatalogKindPrompt), @(CAComposerCatalogKindSkill),
                                    @(CAComposerCatalogKindMCP), @(CAComposerCatalogKindPlugin),
                                    @(CAComposerCatalogKindMemory) ];
    for (NSNumber *key in order) {
        NSMutableArray *bucket = grouped[key];
        if (bucket.count == 0) continue;
        CAComposerPopupSection *section = [[CAComposerPopupSection alloc] init];
        section.title = [self titleForComposerCatalogKind:(CAComposerCatalogKind)key.integerValue];
        section.items = bucket;
        [sections addObject:section];
    }

    if (sections.count == 0) {
        BOOL loading = CAComposerCatalog.sharedCatalog.loading;
        BOOL hasAny = CAComposerCatalog.sharedCatalog.items.count > 0;
        CAComposerPopupItem *empty = [[CAComposerPopupItem alloc] init];
        empty.identifier = @"empty";
        if (loading) {
            // 原版：首次读取需要启动 Codex
            empty.title = @"正在读取 MCP、插件与 Skills…";
            empty.subtitle = @"首次读取需要启动 Codex，稍等片刻";
            empty.symbol = @"hourglass";
        } else if (hasAny) {
            // 原版：有内容但被筛选词过滤掉
            empty.title = [NSString stringWithFormat:@"没有匹配“%@”的项目", filter.length ? filter : @""];
            empty.subtitle = @"继续输入或删除 / 关闭面板";
            empty.symbol = @"magnifyingglass";
        } else {
            empty.title = @"没有可引用的 Skills、插件或 MCP";
            empty.subtitle = @"请在设置中检查是否已安装并启用";
            empty.symbol = @"folder";
        }
        [empty setEnabled:@NO];
        CAComposerPopupSection *section = [[CAComposerPopupSection alloc] init];
        section.title = @"结果";
        section.items = @[ empty ];
        [sections addObject:section];
    }
    return sections;
}

- (NSString *)composerPopupCountHint
{
    CAComposerCatalog *catalog = CAComposerCatalog.sharedCatalog;
    NSUInteger total = catalog.items.count;
    if (catalog.loading && total == 0) return @"正在读取…";
    if (catalog.loading) return [NSString stringWithFormat:@"%lu 项 · 后台刷新", (unsigned long)total];
    return [NSString stringWithFormat:@"%lu 项", (unsigned long)total];
}

- (NSString *)titleForComposerCatalogKind:(CAComposerCatalogKind)kind
{
    switch (kind) {
        case CAComposerCatalogKindSkill:  return @"Skills";
        case CAComposerCatalogKindPlugin: return @"插件";
        case CAComposerCatalogKindMCP:    return @"MCP 服务";
        case CAComposerCatalogKindPrompt: return @"指令";
        case CAComposerCatalogKindMemory: return @"记忆";
        default:                          return @"其它";
    }
}

- (id)composerPopupItemForCatalogEntry:(id)arg1
{
    CAComposerCatalogItem *entry = [arg1 isKindOfClass:CAComposerCatalogItem.class] ? arg1 : nil;
    if (!entry) return nil;

    CAComposerPopupItem *item = [[CAComposerPopupItem alloc] init];
    item.identifier = entry.identifier.length > 0 ? entry.identifier : (entry.name ?: entry.displayTitle);
    item.title = entry.displayTitle ?: entry.name ?: entry.identifier;
    item.subtitle = entry.summary.length > 0 ? entry.summary : (entry.detail ?: entry.scope ?: @"");
    item.symbol = [self symbolForComposerCatalogKind:entry.kind];
    item.badge = [entry.kindName uppercaseString];
    item.payload = entry;
    [item setEnabled:@(entry.enabled)];
    if (!entry.enabled) item.subtitle = @"已禁用（在设置里启用后可用）";
    return item;
}

- (NSString *)symbolForComposerCatalogKind:(CAComposerCatalogKind)kind
{
    switch (kind) {
        case CAComposerCatalogKindSkill:  return @"wand.and.stars";
        case CAComposerCatalogKindPlugin: return @"puzzlepiece.extension";
        case CAComposerCatalogKindMCP:    return @"server.rack";
        case CAComposerCatalogKindPrompt: return @"text.badge.plus";
        case CAComposerCatalogKindMemory: return @"brain";
        default:                          return @"circle";
    }
}

- (id)handleComposerPopupItem:(id)arg1
{
    CAComposerPopupItem *item = [arg1 isKindOfClass:CAComposerPopupItem.class] ? arg1 : nil;
    if (!item) return @NO;

    NSString *reference = item.title ?: @"";
    if ([item.payload isKindOfClass:CAComposerCatalogItem.class]) {
        reference = [self composerReferenceForCatalogItem:item.payload];
    }
    [self insertComposerText:reference];
    [self setChatComposerPopupVisible:NO animated:YES];
    return @YES;
}

- (NSString *)composerReferenceForCatalogItem:(CAComposerCatalogItem *)item
{
    NSString *name = item.name.length > 0 ? item.name : (item.title ?: item.identifier ?: @"");
    if (name.length == 0) return @"/";
    if (item.kind == CAComposerCatalogKindMCP) return [NSString stringWithFormat:@"/mcp:%@ ", name];
    if (item.kind == CAComposerCatalogKindMemory) return [NSString stringWithFormat:@"/memory:%@ ", name];
    return [NSString stringWithFormat:@"/%@ ", name];
}

- (id)insertComposerText:(id)arg1
{
    NSString *insertion = [arg1 isKindOfClass:NSString.class] ? arg1 : ([arg1 description] ?: @"");
    if (insertion.length == 0) return @NO;

    UITextView *field = self.composerField;
    NSString *text = field.text ?: @"";
    NSDictionary *context = [self composerSlashContext];
    NSRange replaceRange = NSMakeRange(MIN(field.selectedRange.location, text.length), 0);
    if (context) {
        NSUInteger location = [context[@"location"] unsignedIntegerValue];
        NSUInteger length = [context[@"length"] unsignedIntegerValue];
        if (location + length <= text.length) replaceRange = NSMakeRange(location, length);
    }

    NSString *updated = [text stringByReplacingCharactersInRange:replaceRange withString:insertion];
    field.text = updated;
    field.selectedRange = NSMakeRange(replaceRange.location + insertion.length, 0);
    [self setComposerSlashSuppressedText:updated];

    [self updateInputHeight];
    [self updateSendButtonState];
    self.inputPlaceholderLabel.hidden = updated.length > 0;
    CALog(CALogLevelDebug, @"CHAT", @"composer inserted reference=%@", insertion);
    return @YES;
}

- (id)selectHighlightedComposerPopupItem
{
    BOOL selected = [self.composerPopupView selectHighlightedItem];
    return @(selected);
}

- (void)composerCatalogDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.composerPopupVisible) return;
        [self reloadSlashComposerPopupPreserving:@YES];
    });
}

#pragma mark - 会话持久化（CAConversationStore）

- (NSArray<NSDictionary *> *)messageDictionaries
{
    NSMutableArray<NSDictionary *> *payload = [NSMutableArray array];
    for (CAMessageItem *message in self.messages) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"message_id"] = message.messageId ?: @"";
        entry[@"role"] = @(message.role);
        entry[@"kind"] = @(message.activityKind);
        entry[@"text"] = message.text ?: @"";
        entry[@"detail"] = message.activityDetail ?: @"";
        entry[@"title"] = message.activityTitle ?: @"";
        entry[@"created_at"] = @((message.timestamp ?: [NSDate date]).timeIntervalSince1970);
        if (message.toolItem) {
            CAToolItem *tool = message.toolItem;
            entry[@"tool_id"] = tool.itemId ?: @"";
            entry[@"tool_command"] = tool.command ?: @"";
            entry[@"tool_output"] = tool.output ?: @"";
            entry[@"tool_status"] = @(tool.status);
            entry[@"tool_exit_code"] = @(tool.exitCode);
        }
        [payload addObject:entry];
    }
    return payload;
}

- (void)persistConversation
{
    CAConversationStore *store = [CAConversationStore sharedStore];
    CAConversationRecord *record = self.activeRecord;
    if (!record) {
        record = [store loadActiveConversationForWorkspace:self.workspacePath];
        if (!record) record = [store createConversationForWorkspace:self.workspacePath];
        self.activeRecord = record;
    }

    record.workspacePath = self.workspacePath ?: record.workspacePath;
    record.threadId = self.threadId;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    record.modelSlug = [defaults stringForKey:CADefaultsSelectedModel] ?: [defaults stringForKey:CADefaultsThirdPartyModel];
    record.reasoningEffort = [defaults stringForKey:CADefaultsActiveEffort];
    record.executionMode = [defaults stringForKey:kChatExecutionModeDefaultsKey];
    record.apiBaseURL = [defaults stringForKey:CADefaultsAPIBaseURL];
    record.messages = [[self messageDictionaries] mutableCopy] ?: [NSMutableArray array];
    if (record.title.length == 0) record.title = [self derivedConversationTitle];
    record.updatedAt = [NSDate date];

    if (![store saveRecord:record]) {
        CALog(CALogLevelWarn, @"CHAT", @"conversation save failed id=%@", record.conversationId ?: @"(none)");
        return;
    }
    [store setActiveConversationId:record.conversationId workspace:self.workspacePath];
    CALog(CALogLevelDebug, @"CHAT", @"conversation saved id=%@ messages=%lu",
          record.conversationId ?: @"(none)", (unsigned long)record.messages.count);
}

- (void)saveActiveConversation
{
    [self persistConversation];
}

- (NSString *)derivedConversationTitle
{
    for (CAMessageItem *message in self.messages) {
        if (message.role != CAMessageRoleUser) continue;
        NSString *text = [self trimmedText:message.text];
        if (text.length == 0) continue;
        NSString *singleLine = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] firstObject] ?: text;
        if (singleLine.length > 24) singleLine = [[singleLine substringToIndex:24] stringByAppendingString:@"…"];
        return singleLine;
    }
    return @"";
}

- (void)restoreMessagesFromRecord:(CAConversationRecord *)record
{
    [self.messages removeAllObjects];
    [self.streamingMessagesByItemId removeAllObjects];
    [self.toolMessagesByItemId removeAllObjects];
    self.streamingAssistantMessage = nil;
    self.thinkingMessage = nil;

    for (NSDictionary *entry in record.messages ?: @[]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;

        CAMessageItem *message = [[CAMessageItem alloc] init];
        id identifier = entry[@"message_id"];
        if ([identifier isKindOfClass:NSString.class] && [identifier length] > 0) message.messageId = identifier;

        id role = entry[@"role"];
        long long roleValue = [role respondsToSelector:@selector(longLongValue)] ? [role longLongValue] : CAMessageRoleAssistant;
        [message setRole:@(roleValue)];

        id kind = entry[@"kind"];
        long long kindValue = [kind respondsToSelector:@selector(longLongValue)] ? [kind longLongValue] : CAMessageActivityKindText;
        message.text = [entry[@"text"] isKindOfClass:NSString.class] ? entry[@"text"] : @"";
        message.activityTitle = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
        message.activityDetail = [entry[@"detail"] isKindOfClass:NSString.class] ? entry[@"detail"] : @"";

        id createdAt = entry[@"created_at"];
        double timestamp = [createdAt respondsToSelector:@selector(doubleValue)] ? [createdAt doubleValue] : 0;
        if (timestamp > 0) message.timestamp = [NSDate dateWithTimeIntervalSince1970:timestamp];

        if (kindValue == CAMessageActivityKindTool) {
            CAToolItem *tool = [[CAToolItem alloc] init];
            if ([entry[@"tool_id"] isKindOfClass:NSString.class]) tool.itemId = entry[@"tool_id"];
            if ([entry[@"tool_command"] isKindOfClass:NSString.class]) tool.command = entry[@"tool_command"];
            if ([entry[@"tool_output"] isKindOfClass:NSString.class]) tool.output = entry[@"tool_output"];
            NSNumber *status = [entry[@"tool_status"] isKindOfClass:NSNumber.class] ? entry[@"tool_status"] : @(CAToolStatusSucceeded);
            NSNumber *exitCode = [entry[@"tool_exit_code"] isKindOfClass:NSNumber.class] ? entry[@"tool_exit_code"] : @0;
            [tool chatSetStatus:(CAToolStatus)status.integerValue exitCode:exitCode.integerValue];
            message.toolItem = tool;
            [message setActivityOfKind:CAMessageActivityKindTool title:message.activityTitle ?: @"工具调用" detail:message.activityDetail running:NO];
            self.toolMessagesByItemId[tool.itemId ?: message.messageId] = message;
        } else {
            [message setActivityOfKind:(CAMessageActivityKind)kindValue title:message.activityTitle detail:message.activityDetail running:NO];
        }
        [self.messages addObject:message];
    }
    [self.tableView reloadData];
    [self refreshWelcomeState];
}

- (void)loadActiveConversation
{
    CAConversationStore *store = [CAConversationStore sharedStore];
    CAConversationRecord *record = [store loadActiveConversationForWorkspace:self.workspacePath];

    if (!record) {
        NSArray<CAConversationRecord *> *existing = [store loadRecordsForWorkspace:self.workspacePath];
        record = existing.firstObject;
    }
    if (!record) {
        self.activeRecord = nil;
        if (self.messages.count > 0) return;
        [self.tableView reloadData];
        return;
    }
    self.activeRecord = record;
    if (record.threadId.length > 0) {
        self.threadId = record.threadId;
        [NSUserDefaults.standardUserDefaults setObject:record.threadId forKey:kChatActiveThreadDefaultsKey];
    }
    [store setActiveConversationId:record.conversationId workspace:self.workspacePath];
    [self restoreMessagesFromRecord:record];
    [self.conversationSidebar reloadConversations];
    CALog(CALogLevelInfo, @"CHAT", @"conversation restored id=%@ messages=%lu",
          record.conversationId ?: @"(none)", (unsigned long)record.messages.count);
}

- (id)applyRecordSelection:(id)arg1 resetEngine:(id)arg2
{
    CAConversationRecord *record = [arg1 isKindOfClass:CAConversationRecord.class] ? arg1 : nil;
    if (!record) return @NO;
    BOOL reset = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;

    self.activeRecord = record;
    if (record.workspacePath.length > 0) self.workspacePath = record.workspacePath;
    self.threadId = record.threadId;
    if (record.threadId.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:record.threadId forKey:kChatActiveThreadDefaultsKey];
    }
    [self restoreMessagesFromRecord:record];
    [self refreshRuntimeBanner];
    [self renderStatusStrip];
    if (reset) [self rebindThreadForRecord:record];
    CALog(CALogLevelInfo, @"CHAT", @"selection applied id=%@ workspace=%@", record.conversationId ?: @"(none)", self.workspacePath);
    return @YES;
}

- (void)rebindThreadForRecord:(CAConversationRecord *)record
{
    // 常驻 app-server 上的一轮还没结束：先停掉，避免把新会话的问题发到旧 thread 上。
    if (self.chatEngine.persistentTurnInFlight) {
        [self.chatEngine invalidatePersistentServerWithReason:@"conversation switched"];
    }
    self.activeTurnIdentifier = nil;
}

#pragma mark - 会话侧栏（历史抽屉）

- (id)prepareHistoryDrawer
{
    if (self.historyDrawer) return self.historyDrawer;

    UIControl *overlay = [[UIControl alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    overlay.alpha = 0.0;
    overlay.hidden = YES;
    [overlay addTarget:self action:@selector(closeHistoryDrawer) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:overlay];
    self.historyDrawerOverlay = overlay;

    CAConversationSidebarViewController *sidebar = [[CAConversationSidebarViewController alloc] init];
    sidebar.delegate = self;
    [sidebar setWorkspacePath:self.workspacePath];
    // 截图 02：顶栏右侧是灰色圆形 ×（标题「MT 智能体」由侧栏自己的 title 居中显示）
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(0.0, 0.0, 30.0, 30.0);
    closeButton.backgroundColor = UIColor.systemGrayColor;
    closeButton.layer.cornerRadius = 15.0;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeButton.tintColor = UIColor.whiteColor;
    [closeButton addTarget:self action:@selector(closeHistoryDrawer) forControlEvents:UIControlEventTouchUpInside];
    closeButton.accessibilityLabel = @"关闭";
    sidebar.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:closeButton];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:sidebar];
    // 抽屉顶栏与内容同为分组灰底、无分割线（截图 02 顶栏看不到白色条与 hairline）
    UINavigationBarAppearance *drawerAppearance = [[UINavigationBarAppearance alloc] init];
    [drawerAppearance configureWithTransparentBackground];
    drawerAppearance.backgroundColor = UIColor.clearColor;
    drawerAppearance.shadowColor = UIColor.clearColor;
    drawerAppearance.titleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.labelColor };
    navigation.navigationBar.standardAppearance = drawerAppearance;
    navigation.navigationBar.scrollEdgeAppearance = drawerAppearance;
    navigation.navigationBar.compactAppearance = drawerAppearance;
    navigation.navigationBar.tintColor = UIColor.labelColor;
    [self addChildViewController:navigation];
    navigation.view.translatesAutoresizingMaskIntoConstraints = NO;
    [navigation didMoveToParentViewController:self];
    self.historySidebarNavigationController = navigation;
    self.conversationSidebar = sidebar;

    UIView *drawer = [[UIView alloc] init];
    drawer.translatesAutoresizingMaskIntoConstraints = NO;
    drawer.backgroundColor = UIColor.systemGroupedBackgroundColor;
    drawer.layer.shadowColor = UIColor.blackColor.CGColor;
    drawer.layer.shadowOpacity = 0.18;
    drawer.layer.shadowRadius = 8.0;
    [drawer addSubview:navigation.view];
    [self.view addSubview:drawer];
    self.historyDrawer = drawer;

    // 截图 02 实测抽屉宽度 329pt / 屏宽 393pt ≈ 0.84
    CGFloat width = MIN(340.0, MAX(260.0, self.view.bounds.size.width * 0.84));
    self.historyDrawerWidthConstraint = [drawer.widthAnchor constraintEqualToConstant:width];
    self.historyDrawerLeading = [drawer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:-width];

    [NSLayoutConstraint activateConstraints:@[
        self.historyDrawerLeading,
        self.historyDrawerWidthConstraint,
        [drawer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [drawer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [navigation.view.topAnchor constraintEqualToAnchor:drawer.topAnchor],
        [navigation.view.bottomAnchor constraintEqualToAnchor:drawer.bottomAnchor],
        [navigation.view.leadingAnchor constraintEqualToAnchor:drawer.leadingAnchor],
        [navigation.view.trailingAnchor constraintEqualToAnchor:drawer.trailingAnchor],

        [overlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    return self.historyDrawer;
}

- (void)setChatHistoryDrawerOpen:(BOOL)open animated:(BOOL)animated
{
    [self prepareHistoryDrawer];
    if (!self.historyDrawer) return;

    self.chatHistoryDrawerOpen = open;
    CGFloat width = self.historyDrawerWidthConstraint.constant;
    self.historyDrawerOverlay.hidden = NO;
    if (open) self.historyDrawer.hidden = NO;

    void (^changes)(void) = ^{
        self.historyDrawerLeading.constant = open ? 0.0 : -width;
        self.historyDrawerOverlay.alpha = open ? 1.0 : 0.0;
        [self.view layoutIfNeeded];
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (!open) {
            self.historyDrawer.hidden = YES;
            self.historyDrawerOverlay.hidden = YES;
        }
    };
    if (animated) {
        [UIView animateWithDuration:0.24 animations:changes completion:completion];
    } else {
        changes();
        completion(YES);
    }
}

- (void)closeHistoryDrawer
{
    [self setChatHistoryDrawerOpen:NO animated:YES];
}

- (id)closeHistoryDrawerWithCompletion:(id)arg1
{
    void (^completion)(void) = [arg1 isKindOfClass:NSClassFromString(@"NSBlock")] ? arg1 : nil;
    [self setChatHistoryDrawerOpen:NO animated:YES];
    if (completion) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)), dispatch_get_main_queue(), completion);
    }
    return nil;
}

- (id)removeHistoryDrawer
{
    if (!self.historyDrawer) return nil;
    [self.historyDrawer removeFromSuperview];
    [self.historySidebarNavigationController willMoveToParentViewController:nil];
    [self.historySidebarNavigationController.view removeFromSuperview];
    [self.historySidebarNavigationController removeFromParentViewController];
    [self.historyDrawerOverlay removeFromSuperview];
    self.historyDrawer = nil;
    self.historyDrawerOverlay = nil;
    self.historySidebarNavigationController = nil;
    self.conversationSidebar = nil;
    self.chatHistoryDrawerOpen = NO;
    return nil;
}

- (id)historyDrawerContainerController
{
    return self;
}

- (id)historyDrawerTransition
{
    return nil;
}

- (id)setHistoryDrawerTransition:(id)arg1
{
    // 抽屉用约束动画实现，不使用自定义转场
    return nil;
}

- (id)installHistoryEdgeGesture
{
    if (!self.historyOpenGesture) {
        UIScreenEdgePanGestureRecognizer *gesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHistoryEdgePan:)];
        gesture.edges = UIRectEdgeLeft;
        [self.view addGestureRecognizer:gesture];
        self.historyOpenGesture = gesture;
    }
    return self.historyOpenGesture;
}

- (id)handleHistoryEdgePan:(id)arg1
{
    UIScreenEdgePanGestureRecognizer *gesture = [arg1 isKindOfClass:UIGestureRecognizer.class] ? arg1 : nil;
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self setChatHistoryDrawerOpen:YES animated:YES];
    }
    return nil;
}

#pragma mark - 侧栏 delegate（原包选择器）

- (void)conversationSidebar:(id)arg1 didSelectRecord:(id)arg2
{
    CAConversationRecord *record = [arg2 isKindOfClass:CAConversationRecord.class] ? arg2 : nil;
    if (!record) return;
    if ([record.conversationId isEqualToString:self.activeRecord.conversationId ?: @""]) {
        [self closeHistoryDrawer];
        return;
    }
    [self persistConversation];
    [self applyRecordSelection:record resetEngine:@YES];
    [self closeHistoryDrawer];
}

- (void)conversationSidebar:(id)arg1 didDeleteRecord:(id)arg2
{
    CAConversationRecord *record = [arg2 isKindOfClass:CAConversationRecord.class] ? arg2 : nil;
    if (!record) return;
    BOOL wasActive = [record.conversationId isEqualToString:self.activeRecord.conversationId ?: @""];
    CALog(CALogLevelInfo, @"CHAT", @"sidebar deleted conversation=%@ active=%@", record.conversationId ?: @"(none)", wasActive ? @"YES" : @"NO");
    if (wasActive) {
        self.activeRecord = nil;
        self.threadId = nil;
        [self.messages removeAllObjects];
        [self restoreMessagesFromRecord:nil];
        [self handleNewChat];
    }
    [self.conversationSidebar reloadConversations];
}

- (void)conversationSidebar:(id)arg1 didRenameRecord:(id)arg2 title:(id)arg3
{
    CAConversationRecord *record = [arg2 isKindOfClass:CAConversationRecord.class] ? arg2 : nil;
    NSString *title = [arg3 isKindOfClass:NSString.class] ? arg3 : @"";
    if (!record) return;
    if ([record.conversationId isEqualToString:self.activeRecord.conversationId ?: @""]) {
        self.activeRecord.title = title;
        [self persistConversation];
    }
    CALog(CALogLevelInfo, @"CHAT", @"sidebar renamed conversation=%@ title=%@", record.conversationId ?: @"(none)", title);
}

- (void)conversationSidebar:(id)arg1 didMoveRecord:(id)arg2 toWorkspace:(id)arg3
{
    CAConversationRecord *record = [arg2 isKindOfClass:CAConversationRecord.class] ? arg2 : nil;
    NSString *workspace = [arg3 isKindOfClass:NSString.class] ? arg3 : @"";
    if (!record || workspace.length == 0) return;
    CALog(CALogLevelInfo, @"CHAT", @"sidebar moved conversation=%@ -> %@", record.conversationId ?: @"(none)", workspace);

    if ([record.conversationId isEqualToString:self.activeRecord.conversationId ?: @""]) {
        [self switchWorkspaceToPath:workspace];
    }
    [self.conversationSidebar reloadConversations];
}

- (void)conversationSidebar:(id)arg1 didRequestNewConversationForWorkspace:(id)arg2
{
    NSString *workspace = [arg2 isKindOfClass:NSString.class] ? arg2 : nil;
    if (workspace.length > 0 && ![workspace isEqualToString:self.workspacePath ?: @""]) {
        [self switchWorkspaceToPath:workspace];
    }
    [self handleNewChat];
}

- (void)conversationSidebar:(id)arg1 didRequestPermanentDeleteWorkspaceAtPath:(id)arg2
{
    NSString *path = [arg2 isKindOfClass:NSString.class] ? arg2 : nil;
    if (path.length == 0) return;
    NSMutableArray<NSString *> *saved = [[NSUserDefaults.standardUserDefaults arrayForKey:CADefaultsSavedWorkspaces] mutableCopy] ?: [NSMutableArray array];
    if ([saved containsObject:path]) {
        [saved removeObject:path];
        [NSUserDefaults.standardUserDefaults setObject:saved forKey:CADefaultsSavedWorkspaces];
    }
    [self appendNoticeText:[NSString stringWithFormat:@"已从工作区列表移除：%@（磁盘内容未删除）", path.lastPathComponent ?: path]];
    [self conversationDidChange];
}

- (id)conversationSidebarDidRequestClose:(id)arg1
{
    [self closeHistoryDrawer];
    return nil;
}

- (id)conversationSidebarDidRequestNewConversation:(id)arg1
{
    [self handleNewChat];
    [self closeHistoryDrawer];
    return nil;
}

- (id)conversationSidebarDidRequestSettings:(id)arg1
{
    [self closeHistoryDrawerWithCompletion:nil];
    [self handleOpenSettings];
    return nil;
}

- (id)conversationSidebarDidRequestUsage:(id)arg1
{
    [self closeHistoryDrawer];
    [self appendNoticeText:@"用量页还没接入（CAUsageViewController 仍是骨架）。"];
    [self conversationDidChange];
    return nil;
}

- (id)conversationSidebarDidRequestWorkspaces:(id)arg1
{
    [self closeHistoryDrawer];
    CAWorkspaceViewController *workspace = [[CAWorkspaceViewController alloc] init];
    if (!workspace) {
        [self appendNoticeText:@"工作区面板还没接入（CAWorkspaceViewController 仍是骨架）。"];
        [self conversationDidChange];
        return nil;
    }
    __weak typeof(self) weakSelf = self;
    // 激活工作区后切过去
    workspace.onActiveWorkspaceChanged = ^(NSString *path) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && path.length > 0) [strongSelf switchWorkspaceToPath:path];
    };
    // 有会话在跑的工作区禁止删除
    workspace.workspaceBusyProvider = ^BOOL(NSString *path) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return NO;
        id busy = [strongSelf workspaceHasRunningConversation:path];
        return [busy respondsToSelector:@selector(boolValue)] ? [busy boolValue] : NO;
    };
    [self presentPanelInNavigationController:workspace];
    return nil;
}

/// 这个工作区里还有没有在跑的会话（工作区面板的删除守卫用）
- (id)workspaceHasRunningConversation:(id)arg1
{
    NSString *path = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    if (path.length == 0) return @NO;
    if (self.chatTurnActive && [self.workspacePath isEqualToString:path]) return @YES;
    for (NSString *key in self.backgroundRuns.allKeys) {
        if ([key isKindOfClass:NSString.class] && [key containsString:path]) return @YES;
    }
    return @NO;
}

- (id)switchToWorkspacePath:(id)arg1
{
    [self switchWorkspaceToPath:[arg1 isKindOfClass:NSString.class] ? arg1 : nil];
    return nil;
}

- (void)switchWorkspaceToPath:(NSString *)workspace
{
    if (workspace.length == 0) return;
    [self persistConversation];
    self.workspacePath = workspace;
    [NSUserDefaults.standardUserDefaults setObject:workspace forKey:CADefaultsActiveWorkspace];
    [self loadActiveConversation];
    [self refreshAttachmentPlaceholder];
    [self refreshRuntimeBanner];
    [self renderStatusStrip];
}

#pragma mark - 键盘

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = MAX(0.0, self.view.bounds.size.height - [self.view convertRect:frame fromView:nil].origin.y);
    CGFloat inset = MAX(0.0, overlap - self.view.safeAreaInsets.bottom);
    self.inputBottomConstraint.constant = -inset;
    [self.view layoutIfNeeded];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    [self keyboardWillChangeFrame:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    self.inputBottomConstraint.constant = 0.0;
    [self.view layoutIfNeeded];
}

#pragma mark - 运行脉冲

- (void)startPulseTimer
{
    if (self.pulseTimer) return;
    self.pulseTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 target:self selector:@selector(pulseTimerTick:) userInfo:nil repeats:YES];
    self.statusDot.alpha = 1.0;
}

- (void)stopPulseTimer
{
    if (!self.pulseTimer) return;
    [self.pulseTimer invalidate];
    self.pulseTimer = nil;
    self.statusDot.alpha = 1.0;
    [self renderStatusStrip];
}

- (void)pulseTimerTick:(NSTimer *)timer
{
    self.statusDot.alpha = (self.statusDot.alpha > 0.5) ? 0.25 : 1.0;
}

- (void)startRotationTimer
{
    if (self.rotationTimer) return;
    self.rotationTimer = [NSTimer scheduledTimerWithTimeInterval:kChatPlaceholderRotateInterval
                                                          target:self
                                                        selector:@selector(rotationTimerTick:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)stopRotationTimer
{
    if (!self.rotationTimer) return;
    [self.rotationTimer invalidate];
    self.rotationTimer = nil;
}

- (void)rotationTimerTick:(NSTimer *)timer
{
    [self rotateComposerPlaceholderIfNeeded];
}

#pragma mark - 后台保活（原包：UIBackgroundModes=audio + 静音音频）

- (void)installAudioObserversIfNeeded
{
    if (self.audioObserversInstalled) return;
    self.audioObserversInstalled = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(mediaServicesWereReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    [center addObserver:self selector:@selector(audioSessionInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)configureAudioSession
{
    NSError *error = nil;
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (![session setCategory:AVAudioSessionCategoryPlayback
                    withOptions:AVAudioSessionCategoryOptionMixWithOthers
                          error:&error]) {
        CALog(CALogLevelWarn, @"GENERAL", @"audio session category failed: %@", error);
    }
    if (![session setActive:YES error:&error]) {
        CALog(CALogLevelWarn, @"GENERAL", @"audio session activate failed: %@", error);
    }
}

- (void)startSilentAudio
{
    if (self.silentPlayer.isPlaying) return;
    if (!self.silentPlayer) {
        NSData *data = [self silentWAVDataWithSeconds:kChatSilentAudioSeconds];
        NSError *error = nil;
        AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:data error:&error];
        if (!player) {
            CALog(CALogLevelWarn, @"GENERAL", @"silent audio player failed: %@", error);
            return;
        }
        player.numberOfLoops = -1;
        player.volume = 1.0;
        self.silentPlayer = player;
    }
    [self.silentPlayer play];
    CALog(CALogLevelInfo, @"GENERAL", @"silent audio started");
}

- (NSData *)silentWAVDataWithSeconds:(NSTimeInterval)seconds
{
    const uint32_t sampleRate = 8000;
    const uint16_t channels = 1;
    const uint16_t bitsPerSample = 16;
    const uint16_t bytesPerSample = bitsPerSample / 8;
    const uint16_t blockAlign = channels * bytesPerSample;
    const uint32_t byteRate = sampleRate * blockAlign;
    const uint32_t frames = (uint32_t)(sampleRate * MAX(seconds, 1.0));
    const uint32_t dataBytes = frames * blockAlign;
    const uint32_t riffSize = 36 + dataBytes;
    const uint16_t audioFormat = 1;
    const uint32_t fmtSize = 16;

    NSMutableData *data = [NSMutableData dataWithCapacity:44 + dataBytes];
    [data appendBytes:"RIFF" length:4];
    [data appendBytes:&riffSize length:4];
    [data appendBytes:"WAVE" length:4];
    [data appendBytes:"fmt " length:4];
    [data appendBytes:&fmtSize length:4];
    [data appendBytes:&audioFormat length:2];
    [data appendBytes:&channels length:2];
    [data appendBytes:&sampleRate length:4];
    [data appendBytes:&byteRate length:4];
    [data appendBytes:&blockAlign length:2];
    [data appendBytes:&bitsPerSample length:2];
    [data appendBytes:"data" length:4];
    [data appendBytes:&dataBytes length:4];
    [data increaseLengthBy:dataBytes];
    return data;
}

- (void)mediaServicesWereReset:(NSNotification *)notification
{
    CALog(CALogLevelWarn, @"GENERAL", @"media services reset; rebuilding silent audio");
    self.silentPlayer = nil;
    [self configureAudioSession];
    [self startSilentAudio];
    [self renewBackgroundTask];
}

- (void)audioSessionInterrupted:(NSNotification *)notification
{
    AVAudioSessionInterruptionType type = (AVAudioSessionInterruptionType)[notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    CALog(CALogLevelInfo, @"GENERAL", @"audio interruption type=%lu", (unsigned long)type);
    if (type == AVAudioSessionInterruptionTypeEnded) {
        [self configureAudioSession];
        [self startSilentAudio];
    }
}

- (void)renewBackgroundTask
{
    [self endBackgroundTaskIfNeeded];
    __weak typeof(self) weakSelf = self;
    self.backgroundTaskIdentifier = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"CAChatViewController.keepAlive"
                                                                               expirationHandler:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf endBackgroundTaskIfNeeded];
    }];
    CALog(CALogLevelInfo, @"GENERAL", @"background task renewed id=%lu", (unsigned long)self.backgroundTaskIdentifier);
}

- (void)endBackgroundTaskIfNeeded
{
    if (self.backgroundTaskIdentifier == UIBackgroundTaskInvalid) return;
    [UIApplication.sharedApplication endBackgroundTask:self.backgroundTaskIdentifier];
    self.backgroundTaskIdentifier = UIBackgroundTaskInvalid;
}

#pragma mark - 属性回调（原包 ivar 语义）

- (void)setThinkingSummaryCard:(NSString *)thinkingSummaryCard
{
    _thinkingSummaryCard = [thinkingSummaryCard copy];
    [self renderStatusStrip];
}

- (void)setComposerPlaceholderIndex:(NSUInteger)composerPlaceholderIndex
{
    _composerPlaceholderIndex = composerPlaceholderIndex;
    [self applyComposerPlaceholder];
}

- (void)setHistorySidebar:(UIView *)historySidebar
{
    if (_historySidebar == historySidebar) return;
    [_historySidebar removeFromSuperview];
    _historySidebar = historySidebar;
    if (!historySidebar) return;
    historySidebar.hidden = YES;
}

#pragma mark - 空态 hero（01 主会话页·空态）

/// 顶部导航栏固定不透明（内容从导航栏下方滚过，截图里导航栏下没有分割线）
- (void)applyOpaqueNavigationBarAppearance
{
    UINavigationController *navigation = self.navigationController;
    if (!navigation) return;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColor.systemBackgroundColor;
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.labelColor };
    navigation.navigationBar.standardAppearance = appearance;
    navigation.navigationBar.scrollEdgeAppearance = appearance;
    navigation.navigationBar.compactAppearance = appearance;
    navigation.navigationBar.tintColor = UIColor.labelColor;
}

/// 建空态视图：终端图标 → 标题 → 两行副标题 → 三张建议卡（版式取自 SPEC/UI_还原基准.md §3）
- (id)setupWelcomeView
{
    UIView *welcome = [[UIView alloc] init];
    welcome.translatesAutoresizingMaskIntoConstraints = NO;
    welcome.backgroundColor = UIColor.clearColor;
    welcome.hidden = YES;
    // 插在消息列表之上、底部固定条之下
    [self.view insertSubview:welcome aboveSubview:self.tableView];
    self.welcomeView = welcome;

    // 终端图标：SF Symbol terminal（regular，约 34pt，截图 y 238–272）
    UIImageView *icon = [[UIImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [UIImage systemImageNamed:@"terminal"
                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34.0 weight:UIImageSymbolWeightRegular]];
    icon.tintColor = UIColor.labelColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.hidden = NO;
    [welcome addSubview:icon];
    self.welcomeIcon = icon;

    // 标题：今天想完成什么?（约 28pt bold）
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kChatWelcomeTitleText;
    title.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    title.textColor = UIColor.labelColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 1;
    [welcome addSubview:title];
    self.welcomeTitleLabel = title;

    // 副标题两行：从理解项目到交付代码 / 在当前工作区开始一个任务（.subheadline，灰色，居中）
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.numberOfLines = 2;
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.textColor = UIColor.secondaryLabelColor;
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.lineSpacing = 2.0;
    NSString *subtitleText = [NSString stringWithFormat:@"%@\n%@", kChatWelcomeSubtitleLine1, kChatWelcomeSubtitleLine2];
    subtitle.attributedText = [[NSAttributedString alloc] initWithString:subtitleText
                                                             attributes:@{ NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline],
                                                                           NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
                                                                           NSParagraphStyleAttributeName: paragraph }];
    [welcome addSubview:subtitle];
    self.welcomeSubtitle = subtitle;

    // 原版空态：三枚横排胶囊（了解这个项目 / 检查代码问题 / 实现一个功能），居中一行
    UIButton *projectCard = [self welcomePillWithTitle:kChatWelcomeCardProjectTitle prompt:kChatWelcomePromptProject];
    UIButton *inspectCard = [self welcomePillWithTitle:kChatWelcomeCardInspectTitle prompt:kChatWelcomePromptInspect];
    UIButton *featureCard = [self welcomePillWithTitle:kChatWelcomeCardFeatureTitle prompt:kChatWelcomePromptFeature];

    UIStackView *cards = [[UIStackView alloc] initWithArrangedSubviews:@[ projectCard, inspectCard, featureCard ]];
    cards.translatesAutoresizingMaskIntoConstraints = NO;
    cards.axis = UILayoutConstraintAxisHorizontal;
    cards.spacing = 8.0;
    cards.distribution = UIStackViewDistributionFillEqually;
    [welcome addSubview:cards];
    self.welcomeActions = cards;

    // 原版空态提示卡：没有可引用的 Skills、插件或 MCP（catalog 为空时显示）
    UIView *extensionHint = [self buildExtensionHintCard];
    NSMutableArray *heroViews = [NSMutableArray arrayWithObjects:icon, title, subtitle, nil];
    if (extensionHint) [heroViews addObject:extensionHint];
    [heroViews addObject:cards];
    self.welcomeExtensionHint = extensionHint;
    UIStackView *hero = [[UIStackView alloc] initWithArrangedSubviews:heroViews];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.axis = UILayoutConstraintAxisVertical;
    hero.alignment = UIStackViewAlignmentCenter;
    hero.spacing = 10.0;
    [hero setCustomSpacing:16.0 afterView:icon];
    [hero setCustomSpacing:10.0 afterView:title];
    [hero setCustomSpacing:12.0 afterView:subtitle];
    if (extensionHint) [hero setCustomSpacing:10.0 afterView:extensionHint];
    [welcome addSubview:hero];

    [NSLayoutConstraint activateConstraints:@[
        [welcome.topAnchor constraintEqualToAnchor:self.statusStrip.bottomAnchor],
        [welcome.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [welcome.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [welcome.bottomAnchor constraintEqualToAnchor:self.quickActionBar.topAnchor],

        // 建议卡左右内缩 31pt（截图实测 31.3），整块内容在空态区里居中
        [hero.leadingAnchor constraintEqualToAnchor:welcome.leadingAnchor constant:kChatWelcomeCardSideInset],
        [hero.trailingAnchor constraintEqualToAnchor:welcome.trailingAnchor constant:-kChatWelcomeCardSideInset],
        [hero.centerYAnchor constraintEqualToAnchor:welcome.centerYAnchor constant:4.0],

        [icon.widthAnchor constraintEqualToConstant:34.0],
        [icon.heightAnchor constraintEqualToConstant:34.0],
        // 横排胶囊行：与 hero 同宽，高度由内容决定（原版胶囊高约 36pt）
        [cards.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor],
        [cards.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor],
    ]];
    return nil;
}

/// 单张建议卡：浅灰底 + 12pt 圆角 + 左图标 + 左对齐文案；点按只填输入框，不直接发送
- (UIButton *)welcomeCardWithTitle:(NSString *)title symbol:(NSString *)symbol prompt:(NSString *)prompt
{
    UIButton *card = [UIButton buttonWithType:UIButtonTypeSystem];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.systemGray6Color;
    card.layer.cornerRadius = 12.0;
    card.layer.masksToBounds = YES;
    card.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    card.contentEdgeInsets = UIEdgeInsetsMake(0.0, 18.0, 0.0, 16.0);
    card.titleEdgeInsets = UIEdgeInsetsMake(0.0, 16.0, 0.0, -16.0);
    card.tintColor = UIColor.labelColor;
    [card setImage:[UIImage systemImageNamed:symbol
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightRegular]]
          forState:UIControlStateNormal];
    [card setTitle:title forState:UIControlStateNormal];
    [card setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    card.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    card.accessibilityHint = prompt;
    [card addTarget:self action:@selector(handleWelcomeAction:) forControlEvents:UIControlEventTouchUpInside];
    return card;
}

/// 原版空态提示卡：没有可引用的 Skills、插件或 MCP（catalog 为空时显示，点击进设置）
- (nullable UIView *)buildExtensionHintCard
{
    if (CAComposerCatalog.sharedCatalog.items.count > 0) return nil;

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.systemGray6Color;
    card.layer.cornerRadius = 12.0;
    card.layer.masksToBounds = YES;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.secondaryLabelColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:icon];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 2;
    label.font = [UIFont systemFontOfSize:14.0];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = @"没有可引用的 Skills、插件或 MCP\n请在设置中检查是否已安装并启用";
    [card addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleOpenSettings)];
    [card addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22.0],
        [icon.heightAnchor constraintEqualToConstant:22.0],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
        [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [label.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(extensionHintCatalogChanged:)
                                                 name:CAComposerCatalogDidChangeNotification
                                               object:nil];
    return card;
}

/// catalog 从空变有扩展后自动收起提示卡
- (void)extensionHintCatalogChanged:(NSNotification *)notification
{
    if (CAComposerCatalog.sharedCatalog.items.count == 0) return;
    UIView *hint = self.welcomeExtensionHint;
    if (!hint || hint.hidden) return;
    hint.hidden = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:CAComposerCatalogDidChangeNotification
                                                  object:nil];
}

/// 原版空态胶囊：浅灰胶囊、居中文字、无图标；点按填输入框
- (UIButton *)welcomePillWithTitle:(NSString *)title prompt:(NSString *)prompt
{
    UIButton *pill = [UIButton buttonWithType:UIButtonTypeSystem];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = UIColor.systemGray6Color;
    pill.layer.cornerRadius = 18.0;
    pill.layer.masksToBounds = YES;
    pill.contentEdgeInsets = UIEdgeInsetsMake(0.0, 14.0, 0.0, 14.0);
    [pill setTitle:title forState:UIControlStateNormal];
    [pill setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    pill.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    pill.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    pill.accessibilityHint = prompt;
    [pill addTarget:self action:@selector(handleWelcomeAction:) forControlEvents:UIControlEventTouchUpInside];
    [pill.heightAnchor constraintEqualToConstant:36.0].active = YES;
    return pill;
}

/// 圆形底部按钮（+ / 发送 / 垃圾桶）：浅灰底圆形，图标居中
- (UIButton *)circularBarButtonWithSymbol:(NSString *)symbol pointSize:(CGFloat)pointSize
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setImage:[UIImage systemImageNamed:symbol
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightRegular]]
            forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.backgroundColor = UIColor.tertiarySystemFillColor;
    button.layer.cornerRadius = kChatBottomCircleSize / 2.0;
    button.layer.masksToBounds = YES;
    return button;
}

/// 选择器胶囊（6.1-Sol / High）：浅灰胶囊 + 右侧 chevron
- (void)applyChipTitle:(NSString *)title toButton:(UIButton *)button
{
    if (!button) return;
    NSString *text = title.length > 0 ? title : kChatDefaultModelChipTitle;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.attributedTitle = [[NSAttributedString alloc] initWithString:text
                                                                    attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular] }];
    // chip 必须单行：禁止内部换行（原版 "High" 单词；长模型名靠省略号截断）
    configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
    configuration.titleAlignment = UIControlContentHorizontalAlignmentCenter;
    configuration.image = [UIImage systemImageNamed:@"chevron.down"
                                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10.0 weight:UIImageSymbolWeightSemibold]];
    configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
    configuration.imagePadding = 5.0;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 13.0, 0.0, 12.0);
    configuration.baseForegroundColor = UIColor.labelColor;
    configuration.background.backgroundColor = UIColor.tertiarySystemFillColor;
    configuration.background.cornerRadius = kChatBottomChipHeight / 2.0;
    button.configuration = configuration;
    button.tintColor = UIColor.labelColor;
    // 原版：chip 横向压缩阻力 required（1150 附近），保证文字永不因挤压被截断
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    button.titleLabel.adjustsFontSizeToFitWidth = NO;
}

/// 底部协作条：蓝色电闪 + Agent 协作就绪 药丸 + 垃圾桶（截图 y 778–790 那一行）
- (void)setupQuickActionBar
{
    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:bar];
    self.quickActionBar = bar;

    // 左：圆形底 + 蓝色电闪（点按看 Agent 状态详情）
    UIView *boltCircle = [[UIView alloc] init];
    boltCircle.translatesAutoresizingMaskIntoConstraints = NO;
    boltCircle.backgroundColor = UIColor.tertiarySystemFillColor;
    boltCircle.layer.cornerRadius = kChatBottomCircleSize / 2.0;
    boltCircle.layer.masksToBounds = YES;
    [bar addSubview:boltCircle];
    self.collaborationBoltCircle = boltCircle;

    UIImageView *boltIcon = [[UIImageView alloc] init];
    boltIcon.translatesAutoresizingMaskIntoConstraints = NO;
    boltIcon.image = [UIImage systemImageNamed:@"bolt.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold]];
    boltIcon.tintColor = UIColor.systemBlueColor;
    boltIcon.contentMode = UIViewContentModeScaleAspectFit;
    [boltCircle addSubview:boltIcon];
    self.agentStatusIcon = boltIcon;

    UIButton *boltButton = [UIButton buttonWithType:UIButtonTypeCustom];
    boltButton.translatesAutoresizingMaskIntoConstraints = NO;
    boltButton.backgroundColor = UIColor.clearColor;
    boltButton.accessibilityLabel = @"Agent 状态";
    [boltButton addTarget:self action:@selector(handleAgentStatusInfo) forControlEvents:UIControlEventTouchUpInside];
    [boltCircle addSubview:boltButton];

    // 中：药丸（person.2.fill + Agent 协作就绪）
    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = UIColor.tertiarySystemFillColor;
    pill.layer.cornerRadius = kChatBottomChipHeight / 2.0;
    pill.layer.masksToBounds = YES;
    [bar addSubview:pill];
    self.collaborationPill = pill;

    UIImageView *pillIcon = [[UIImageView alloc] init];
    pillIcon.translatesAutoresizingMaskIntoConstraints = NO;
    pillIcon.image = [UIImage systemImageNamed:@"person.2.fill"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightRegular]];
    pillIcon.tintColor = UIColor.labelColor;
    pillIcon.contentMode = UIViewContentModeScaleAspectFit;
    [pill addSubview:pillIcon];
    self.collaborationPillIcon = pillIcon;

    UILabel *pillLabel = [[UILabel alloc] init];
    pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    pillLabel.text = kChatCollaborationReadyText;
    pillLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    pillLabel.textColor = UIColor.labelColor;
    [pill addSubview:pillLabel];
    self.collaborationPillLabel = pillLabel;

    UIButton *pillButton = [UIButton buttonWithType:UIButtonTypeCustom];
    pillButton.translatesAutoresizingMaskIntoConstraints = NO;
    pillButton.backgroundColor = UIColor.clearColor;
    pillButton.accessibilityLabel = kChatCollaborationReadyText;
    [pillButton addTarget:self action:@selector(handleAgentStatusInfo) forControlEvents:UIControlEventTouchUpInside];
    [pill addSubview:pillButton];

    // 右：垃圾桶（清空当前会话）
    UIButton *trashButton = [self circularBarButtonWithSymbol:@"trash" pointSize:16.0];
    trashButton.accessibilityLabel = @"清空当前会话";
    [trashButton addTarget:self action:@selector(handleClearCurrentConversation) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:trashButton];
    self.clearChatButton = trashButton;

    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:kChatBottomBarHeight],

        [boltCircle.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:kChatBottomBarSideInset],
        [boltCircle.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [boltCircle.widthAnchor constraintEqualToConstant:kChatBottomCircleSize],
        [boltCircle.heightAnchor constraintEqualToConstant:kChatBottomCircleSize],

        [boltIcon.centerXAnchor constraintEqualToAnchor:boltCircle.centerXAnchor],
        [boltIcon.centerYAnchor constraintEqualToAnchor:boltCircle.centerYAnchor],
        [boltIcon.widthAnchor constraintEqualToConstant:20.0],
        [boltIcon.heightAnchor constraintEqualToConstant:20.0],

        [boltButton.leadingAnchor constraintEqualToAnchor:boltCircle.leadingAnchor],
        [boltButton.trailingAnchor constraintEqualToAnchor:boltCircle.trailingAnchor],
        [boltButton.topAnchor constraintEqualToAnchor:boltCircle.topAnchor],
        [boltButton.bottomAnchor constraintEqualToAnchor:boltCircle.bottomAnchor],

        [pill.leadingAnchor constraintEqualToAnchor:boltCircle.trailingAnchor constant:6.0],
        [pill.trailingAnchor constraintEqualToAnchor:trashButton.leadingAnchor constant:-5.0],
        [pill.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [pill.heightAnchor constraintEqualToConstant:kChatBottomChipHeight],

        [pillIcon.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:12.0],
        [pillIcon.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [pillIcon.widthAnchor constraintEqualToConstant:20.0],
        [pillIcon.heightAnchor constraintEqualToConstant:18.0],

        [pillLabel.leadingAnchor constraintEqualToAnchor:pillIcon.trailingAnchor constant:7.0],
        [pillLabel.trailingAnchor constraintLessThanOrEqualToAnchor:pill.trailingAnchor constant:-12.0],
        [pillLabel.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],

        [pillButton.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor],
        [pillButton.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor],
        [pillButton.topAnchor constraintEqualToAnchor:pill.topAnchor],
        [pillButton.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor],

        [trashButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-kChatBottomBarSideInset + 1.0],
        [trashButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [trashButton.widthAnchor constraintEqualToConstant:kChatBottomCircleSize],
        [trashButton.heightAnchor constraintEqualToConstant:kChatBottomCircleSize],

        // 运行时提示条压在协作条上面（提示条本身在 setupUI 里建）
        [self.runtimeBanner.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
    ]];
}

/// 空态显隐：没有消息（也不在跑）时显示 hero + 三张卡，有消息就收起
- (id)refreshWelcomeState
{
    BOOL empty = (self.messages.count == 0) && !self.thinking;
    self.welcomeView.hidden = !empty;
    // 截图里导航栏下面没有运行状态条：空态折叠掉，有消息再让出来
    self.statusStrip.hidden = empty;
    self.statusStripHeightConstraint.constant = empty ? 0.0 : 30.0;
    [self updateConversationBottomInset];
    return @(empty);
}

/// 消息列表底部让位给固定条（协作条 + 输入卡）
- (void)updateConversationBottomInset
{
    UIView *topBar = (self.runtimeBannerHeightConstraint.constant > 0.5) ? self.runtimeBanner : self.quickActionBar;
    if (!topBar || !self.tableView) return;
    // 固定条钉在 safe area 上，这里只补“条本身”的高度（安全区那截交给系统的自动 inset）
    CGFloat inset = MAX(0.0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(topBar.frame) - self.view.safeAreaInsets.bottom);
    if (fabs(self.tableView.contentInset.bottom - inset) < 0.5) return;
    UIEdgeInsets contentInsets = self.tableView.contentInset;
    contentInsets.bottom = inset;
    self.tableView.contentInset = contentInsets;
    UIEdgeInsets indicatorInsets = self.tableView.verticalScrollIndicatorInsets;
    indicatorInsets.bottom = inset;
    self.tableView.verticalScrollIndicatorInsets = indicatorInsets;
}

/// 建议卡点按：把提示词填进输入框（不发）
- (id)handleWelcomeAction:(id)arg1
{
    NSString *prompt = nil;
    if ([arg1 isKindOfClass:UIButton.class]) {
        UIButton *card = (UIButton *)arg1;
        prompt = card.accessibilityHint;
        if (prompt.length == 0) prompt = [card titleForState:UIControlStateNormal];
    } else if ([arg1 isKindOfClass:NSString.class]) {
        prompt = arg1;
    }
    [self fillComposerWithPrompt:prompt];
    return nil;
}

/// 填输入框：走已有字段 + 高度/发送态刷新，不触发发送
- (void)fillComposerWithPrompt:(NSString *)prompt
{
    if (prompt.length == 0) return;
    self.composerField.text = prompt;
    self.composerField.selectedRange = NSMakeRange(prompt.length, 0);
    [self setComposerSlashSuppressedText:prompt];
    [self updateInputHeight];
    [self updateSendButtonState];
    self.inputPlaceholderLabel.hidden = YES;
    CALog(CALogLevelDebug, @"CHAT", @"welcome prompt filled length=%lu", (unsigned long)prompt.length);
}

#pragma mark - 底部选择器（6.1-Sol / High）

#pragma mark - 原包占位选择器实现（此前只声明未实现，点按钮即 unrecognized selector）

- (id)handleAgentStatusInfo
{
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"thread"] = [[self chatEngine] currentThreadId] ?: @"(none)";
    snapshot[@"model"] = [self currentModelChipTitle] ?: @"-";
    snapshot[@"effort"] = [self currentEffortChipTitle] ?: @"-";
    snapshot[@"workspace"] = self.workspacePath ?: @"-";
    snapshot[@"context"] = [NSString stringWithFormat:@"%lld%%", [[self chatEngine] contextUsagePercent]];

    CAAgentStatusDetailViewController *detail = [[CAAgentStatusDetailViewController alloc] initWithSnapshot:snapshot];
    if (!detail) {
        detail = [[CAAgentStatusDetailViewController alloc] init];
    }
    return [self presentPanelInNavigationController:detail];
}

- (id)handleShowUsageDetails
{
    CACodexEngine *engine = [self chatEngine];
    NSString *summary = engine.execUsageSummary;
    if (summary.length == 0) {
        summary = [NSString stringWithFormat:@"上下文占用：%lld%%\n输入 Token：%llu\n输出 Token：%llu\n深度推理 Token：%llu",
                   [engine contextUsagePercent],
                   [engine totalInputTokens], [engine totalOutputTokens], [engine totalReasoningTokens]];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"本会话实时用量"
                                                                  message:summary
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return @YES;
}

- (id)presentComposerCatalogDetail:(id)arg1
{
    NSArray *items = CAComposerCatalog.sharedCatalog.items ?: @[];
    NSMutableString *text = [NSMutableString string];
    if (items.count == 0) {
        [text appendString:@"没有可引用的 Skills、插件或 MCP。\n请在设置中检查是否已安装并启用。"];
    } else {
        for (CAComposerCatalogItem *item in items) {
            if (![item isKindOfClass:CAComposerCatalogItem.class]) continue;
            NSString *title = item.displayTitle.length > 0 ? item.displayTitle : item.name;
            [text appendFormat:@"• [%@] %@\n", [item.kindName uppercaseString], title ?: @"?"];
        }
        [text appendString:@"\n在输入框键入 / 可以直接选用这些内容。"];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"扩展与指令"
                                                                  message:text
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return @YES;
}

- (id)refreshBottomSelectors
{
    NSString *model = [self currentModelChipTitle];
    NSString *effort = [self currentEffortChipTitle];
    [self applyChipTitle:model toButton:self.bottomModelBtn];
    [self applyChipTitle:effort toButton:self.bottomEffortBtn];
    self.bottomModelBtn.accessibilityValue = model;
    self.bottomEffortBtn.accessibilityValue = effort;
    return @{ @"model": model, @"effort": effort };
}

- (NSString *)currentModelChipTitle
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[ CADefaultsActiveModelSlug, CADefaultsSelectedModel, CADefaultsThirdPartyModel ]) {
        NSString *value = [defaults stringForKey:key];
        if (value.length > 0) return [self chipLabelForModelSlug:value];
    }
    return kChatDefaultModelChipTitle;
}

/// slug → 底部 chip 短名（models.json 的 display_name 去掉 GPT- 前缀；未知 slug 原样去前缀）
- (NSString *)chipLabelForModelSlug:(NSString *)slug
{
    if (slug.length == 0) return kChatDefaultModelChipTitle;

    static NSDictionary<NSString *, NSString *> *cachedNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *names = [NSMutableDictionary dictionary];
        NSString *path = [NSBundle.mainBundle pathForResource:@"models" ofType:@"json"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (data) {
            NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSArray *models = payload[@"models"];
            if ([models isKindOfClass:NSArray.class]) {
                for (NSDictionary *entry in models) {
                    if (![entry isKindOfClass:NSDictionary.class]) continue;
                    NSString *s = entry[@"slug"];
                    NSString *d = entry[@"display_name"];
                    if ([s isKindOfClass:NSString.class] && [d isKindOfClass:NSString.class]) names[s] = d;
                }
            }
        }
        cachedNames = names;
    });

    NSString *label = cachedNames[slug] ?: slug;
    for (NSString *prefix in @[ @"GPT-", @"gpt-", @"Gpt-" ]) {
        if ([label hasPrefix:prefix]) { label = [label substringFromIndex:prefix.length]; break; }
    }
    return label.length > 0 ? label : kChatDefaultModelChipTitle;
}

- (NSString *)currentEffortChipTitle
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *level = [defaults stringForKey:CADefaultsReasoningEffort];
    if (level.length == 0) level = [defaults stringForKey:CADefaultsActiveEffort];
    if (level.length == 0) return kChatDefaultEffortChipTitle;
    return [self effortDisplayTitleForLevel:level];
}

- (NSString *)effortDisplayTitleForLevel:(NSString *)level
{
    if (level.length == 0) return kChatDefaultEffortChipTitle;
    NSString *title = [CAThirdPartyModelCatalog reasoningLevelTitle:level];
    if (title.length > 0) return title;
    if ([level isEqualToString:@"minimal"]) return @"Minimal";
    if ([level isEqualToString:@"low"]) return @"Low";
    if ([level isEqualToString:@"medium"]) return @"Medium";
    if ([level isEqualToString:@"high"]) return kChatDefaultEffortChipTitle;
    if ([level isEqualToString:@"xhigh"]) return @"XHigh";
    if ([level isEqualToString:@"max"]) return @"Max";
    return level.capitalizedString;
}

#pragma mark - 会话清理 / “/” 菜单

/// 垃圾桶：清空当前会话（用户消息 + 助手消息 + thread 绑定一起清）
- (id)handleClearCurrentConversation
{
    if (self.thinking || self.chatTurnActive) {
        [self appendNoticeText:@"这一轮还在跑：先点「停止」，再清空会话。"];
        [self conversationDidChange];
        return @NO;
    }
    [self.messages removeAllObjects];
    self.streamingAssistantMessage = nil;
    self.thinkingMessage = nil;
    self.lastUsageSummary = nil;
    self.threadId = nil;
    [self.rawTailLines removeAllObjects];
    [self.stderrTailLines removeAllObjects];
    [self.streamingMessagesByItemId removeAllObjects];
    [self.toolMessagesByItemId removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kChatActiveThreadDefaultsKey];

    // 落盘空消息（会话记录本身保留，标题清空）
    if (self.activeRecord) self.activeRecord.title = @"";
    [self saveActiveConversation];

    [self refreshWelcomeState];
    [self refreshAttachmentPlaceholder];
    [self renderStatusStrip];
    [self conversationDidChange];
    CALog(CALogLevelInfo, @"CHAT", @"cleared current conversation id=%@", self.activeRecord.conversationId ?: @"(none)");
    return @YES;
}

/// 圆形 “/” 按钮：走已有的斜杠弹出逻辑；弹不出来时至少把 “/” 落进输入框
- (id)handleSlashMenuButton
{
    NSString *before = self.composerField.text ?: @"";
    id inserted = [self insertComposerText:@"/"];
    if (![inserted respondsToSelector:@selector(boolValue)] || ![inserted boolValue]) {
        NSString *fallback = [before stringByAppendingString:@"/"];
        self.composerField.text = fallback;
        self.composerField.selectedRange = NSMakeRange(fallback.length, 0);
        [self updateInputHeight];
        [self updateSendButtonState];
    }
    // insertComposerText: 会抑制紧接着的一次菜单判断，这里放开让 “/” 菜单正常弹出
    [self setComposerSlashSuppressedText:nil];
    [self.composerField becomeFirstResponder];
    [self updateComposerSlashMenuState];
    return @YES;
}

- (void)handleComposerMenuLongPress:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self handleComposerMenu];
}

/// ⋯ 菜单：二级入口集合（计划审阅 / 审批对话框 / Git / 价格 / 扩展 / 工作区 / Agent 状态）
- (id)handleComposerMenu
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"更多入口"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    void (^appendEntry)(NSString *, void (^)(void)) = ^(NSString *title, void (^action)(void)) {
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *selected) {
            if (action) action();
        }]];
    };
    appendEntry(@"计划审阅", ^{ [weakSelf presentPendingPlanReview]; });
    appendEntry(@"审批对话框", ^{ [weakSelf presentPendingPlanDecisionIfPossible]; });
    appendEntry(@"Git 变更", ^{ [weakSelf handleOpenGitChanges]; });
    appendEntry(@"模型价格", ^{ [weakSelf handleShowUsageDetails]; });
    appendEntry(@"扩展与指令", ^{ [weakSelf presentComposerCatalogDetail:nil]; });
    appendEntry(@"工作区", ^{ [weakSelf handleOpenWorkspaceManager]; });
    appendEntry(@"Agent 状态", ^{ [weakSelf handleAgentStatusInfo]; });
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIView *anchor = self.sourceControlButton ?: self.view;
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = anchor.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
    return sheet;
}

#pragma mark - 计划审阅 / 审批对话框

- (id)presentPendingPlanReview
{
    UIViewController *panel = [CAControlCenterPanels planReviewDemoViewController];
    if (!panel) {
        return [self presentPanelPlaceholderNoticeWithTitle:@"计划审阅" detail:@"计划面板还在补全中。"];
    }
    return [self presentPanelInNavigationController:panel];
}

- (id)presentPendingPlanDecisionIfPossible
{
    UIViewController *panel = [CAControlCenterPanels planDecisionDemoViewController];
    if (!panel) {
        return [self presentPanelPlaceholderNoticeWithTitle:@"审批对话框" detail:@"审批面板还在补全中。"];
    }
    return [self presentPanelInNavigationController:panel];
}

#pragma mark - 服务端用户输入请求应答（item/tool/requestUserInput → 决策卡 → sendResult）

/// requestUserInput params 里的 questions 数组（兼容嵌套 item 形态）
static NSArray *CAChatQuestionsFromUserInputParams(NSDictionary *params)
{
    if (![params isKindOfClass:NSDictionary.class]) return @[];
    id raw = params[@"questions"];
    if (![raw isKindOfClass:NSArray.class]) {
        NSDictionary *item = [params[@"item"] isKindOfClass:NSDictionary.class] ? params[@"item"] : @{};
        raw = item[@"questions"] ?: params[@"inputs"];
    }
    return [raw isKindOfClass:NSArray.class] ? raw : @[];
}

/// 弹决策卡：completion 一定触发一次回包（选完 / 全部允许 / 稍后处理 / dismiss 未选择都算）
- (void)presentDecisionCardForUserInput:(NSDictionary *)params requestID:(NSNumber *)requestID
{
    NSArray *questions = CAChatQuestionsFromUserInputParams(params);
    CALog(CALogLevelInfo, @"CHAT", @"decision card questions=%lu requestID=%@",
          (unsigned long)questions.count, requestID ?: @"?");

    __weak typeof(self) weakSelf = self;
    UIViewController *panel = [[CAPlanDecisionViewController alloc] initWithQuestions:questions
                                                                           completion:^(BOOL approved, NSDictionary *answers, BOOL rememberChoice) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.activeDecisionPanel = nil;
        // answers schema（保守包装）：{"answers": {questionId: {...}}, "remember": BOOL}
        NSDictionary *payload = @{
            @"answers": answers ?: @{},
            @"remember": @(rememberChoice),
        };
        [strongSelf respondToPendingUserInputWithAnswers:payload remember:rememberChoice requestID:requestID];
    }];
    if (!panel) {
        // 卡弹不出来也必须回包（取消语义），否则回合挂死
        CALog(CALogLevelWarn, @"CHAT", @"decision card unavailable, answering cancel requestID=%@", requestID ?: @"?");
        [self respondToPendingUserInputWithAnswers:@{ @"answers": @{} } remember:NO requestID:requestID];
        return;
    }
    self.activeDecisionPanel = panel;
    [self presentPanelInNavigationController:panel];
}

/// 把答案送回 app-server：sendResult:forRequestID:，并清 pending 缓存
- (void)respondToPendingUserInputWithAnswers:(NSDictionary *)answers remember:(BOOL)remember requestID:(NSNumber *)requestID
{
    CACodexEngine *engine = self.chatEngine ?: [CACodexEngine sharedEngine];
    NSNumber *rid = requestID ?: self.pendingUserInputRequestID ?: engine.pendingUserInputRequestID;
    CALog(CALogLevelInfo, @"CHAT", @"respond user-input requestID=%@ answers=%@", rid ?: @"?", answers ?: @{});
    [engine respondToUserInputRequest:rid answers:answers];
    self.pendingUserInputRequestID = nil;
    self.pendingUserInputParams = nil;
}

#pragma mark - Git 角标 / 工作区

- (id)handleOpenGitChanges
{
    UIViewController *changes = [[CAGitChangesViewController alloc] initWithWorkspacePath:self.workspacePath];
    if (!changes) {
        // 面板仍在补全（-initWithWorkspacePath: 返回 nil）：给可返回的提示，别让入口点了没反应
        return [self presentPanelPlaceholderNoticeWithTitle:@"Git 变更"
                                                     detail:[NSString stringWithFormat:@"工作区：%@", self.workspacePath ?: @"(未设置)"]];
    }
    return [self presentPanelInNavigationController:changes];
}

/// 读真实变更数刷新右上角红角标（没有 git 可执行文件时按截图显示 99+）
- (id)refreshGitBadge
{
    NSString *workspace = self.workspacePath ?: @"";
    if (!self.badgeRepository || ![self.badgeWorkspace isEqualToString:workspace]) {
        self.badgeRepository = [[CAGitRepository alloc] initWithWorkspacePath:workspace];
        self.badgeWorkspace = workspace;
    }
    CAGitRepository *repository = self.badgeRepository;
    if (!repository) {
        // 仓库对象都建不出来：直接按截图给 99+
        [self applyGitBadgeChangeCount:0 available:NO];
        return nil;
    }
    self.gitBadgeGeneration += 1;
    unsigned long long generation = self.gitBadgeGeneration;
    __weak typeof(self) weakSelf = self;
    [repository readChangeCount:^(NSUInteger count, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (generation != strongSelf.gitBadgeGeneration) return;   // 过期结果丢掉
        [strongSelf applyGitBadgeChangeCount:count available:(error == nil)];
    }];
    return nil;
}

- (void)applyGitBadgeChangeCount:(NSUInteger)count available:(BOOL)available
{
    UILabel *badge = self.gitBadgeLabel;
    if (!badge) return;

    NSString *text = nil;
    if (!available) {
        text = kChatGitBadgeFallbackText;          // 截图同款：无 git 可执行文件时显示 99+
    } else if (count == 0) {
        badge.hidden = YES;                        // 干净仓库不亮角标
        return;
    } else {
        text = (count > 99) ? kChatGitBadgeFallbackText : [NSString stringWithFormat:@"%lu", (unsigned long)count];
    }

    badge.text = text;
    badge.hidden = NO;
    CGSize fitted = [badge sizeThatFits:CGSizeMake(80.0, 18.0)];
    CGFloat width = MAX(28.0, ceil(fitted.width) + 12.0);
    badge.frame = CGRectMake(52.0 - width, 0.0, width, 18.0);   // 角标贴着图标右上角，右对齐
}

/// 5 秒轮询一次变更数（viewDidDisappear / dealloc 里停）
- (id)updateGitBadgePolling
{
    [self stopGitBadgePolling];
    [self refreshGitBadge];
    self.gitBadgePollTimer = 1;
    self.gitBadgeTimer = [NSTimer scheduledTimerWithTimeInterval:kChatGitBadgePollInterval
                                                          target:self
                                                        selector:@selector(gitBadgeTimerTick:)
                                                        userInfo:nil
                                                         repeats:YES];
    return nil;
}

- (void)stopGitBadgePolling
{
    if (self.gitBadgeTimer) {
        [self.gitBadgeTimer invalidate];
        self.gitBadgeTimer = nil;
    }
    self.gitBadgePollTimer = 0;
}

- (void)gitBadgeTimerTick:(NSTimer *)timer
{
    [self refreshGitBadge];
}

- (id)handleOpenWorkspaceManager
{
    CAWorkspaceViewController *workspace = [[CAWorkspaceViewController alloc] init];
    if (!workspace) {
        return [self presentPanelPlaceholderNoticeWithTitle:@"工作区"
                                                     detail:[NSString stringWithFormat:@"当前工作区：%@", self.workspacePath ?: @"(未设置)"]];
    }
    return [self presentPanelInNavigationController:workspace];
}

#pragma mark - 底部胶囊 / Agent 状态

- (id)handleBottomModelBtnTapped
{
    CAModelPickerViewController *picker = [[CAModelPickerViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    void (^handler)(NSString *, BOOL) = ^(NSString *slug, BOOL thirdParty) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || slug.length == 0) return;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setObject:slug forKey:CADefaultsActiveModelSlug];
        [defaults setObject:slug forKey:(thirdParty ? CADefaultsThirdPartyModel : CADefaultsSelectedModel)];
        [strongSelf refreshBottomSelectors];
        CALog(CALogLevelInfo, @"CHAT", @"bottom model chip selected slug=%@ thirdParty=%@", slug, thirdParty ? @"YES" : @"NO");
    };
    [picker setOnModelSelected:[handler copy]];
    return [self presentPanelInNavigationController:picker];
}

- (id)handleBottomEffortBtnTapped
{
    NSString *slug = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveModelSlug] ?: @"";
    NSString *providerHint = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsThirdPartyProviderName];
    NSString *modelForLevels = slug.length > 0 ? slug : [self currentModelChipTitle];
    NSArray<NSString *> *levels = [CAModelPricingManager.sharedManager supportedReasoningEffortsForModel:modelForLevels providerHint:providerHint];
    if (levels.count == 0) levels = [CAThirdPartyModelCatalog reasoningLevels];
    if (levels.count == 0) levels = @[ @"auto", @"minimal", @"low", @"medium", @"high" ];

    NSString *current = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsReasoningEffort];
    if (current.length == 0) current = [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveEffort];

    CAReasoningEffortViewController *panel = [[CAReasoningEffortViewController alloc] init];
    panel.levels = levels;
    panel.selectedLevel = current;
    __weak typeof(self) weakSelf = self;
    panel.onLevelSelected = ^(NSString *level) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || level.length == 0) return;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setObject:level forKey:CADefaultsReasoningEffort];
        [defaults setObject:level forKey:CADefaultsActiveEffort];
        [strongSelf refreshBottomSelectors];
        CALog(CALogLevelInfo, @"CHAT", @"reasoning panel selected level=%@", level);
    };
    return [self presentPanelInNavigationController:panel];
}

- (id)presentPanelInNavigationController:(UIViewController *)controller
{
    if (!controller) return nil;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    __weak typeof(self) weakSelf = self;
    // 面板可能是从 actionSheet 的 action 里点出来的：等这一刻的 dismiss 落定再 present，
    // 并挂到当前最上层的页面（避免“present 被吃掉”）
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        UIViewController *presenter = strongSelf;
        while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
            presenter = presenter.presentedViewController;
        }
        if (presenter.isBeingDismissed || presenter.view.window == nil) return;
        @try {
            [presenter presentViewController:navigation animated:YES completion:nil];
        } @catch (NSException *exception) {
            CALog(CALogLevelError, @"CHAT", @"panel present exception: %@ | %@", exception.name, exception.reason);
        }
    });
    return controller;
}

/// 面板还没实装完时的可返回提示（保持入口“能点开、能返回”）
- (id)presentPanelPlaceholderNoticeWithTitle:(NSString *)title detail:(NSString *)detail
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:detail
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    return alert;
}

/// 从消息条目参数里取正文（支持 CAMessageItem / NSDictionary / NSString）
- (NSString *)textForSelectionArgument:(id)arg1
{
    if ([arg1 isKindOfClass:NSString.class]) return arg1;
    if ([arg1 isKindOfClass:CAMessageItem.class]) return ((CAMessageItem *)arg1).text;
    if ([arg1 isKindOfClass:NSDictionary.class]) return [arg1[@"text"] isKindOfClass:NSString.class] ? arg1[@"text"] : nil;
    if ([arg1 isKindOfClass:NSIndexPath.class]) {
        NSInteger row = ((NSIndexPath *)arg1).row;
        if (row >= 0 && (NSUInteger)row < self.messages.count) {
            return ((CAMessageItem *)self.messages[(NSUInteger)row]).text;
        }
    }
    return nil;
}

#pragma mark - “/” 抑制态（原包 ivar 语义：insertComposerText: / updateComposerSlashMenuState 依赖）

- (id)composerSlashSuppressedText
{
    return self.composerSuppressedToken;
}

- (id)setComposerSlashSuppressedText:(id)arg1
{
    self.composerSuppressedToken = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : nil;
    return nil;
}

@end
