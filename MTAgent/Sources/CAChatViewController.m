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
#import "CAConversationSidebarViewController.h"
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

#pragma mark - 会话页

@interface CAChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong, readwrite) CACodexEngine *chatEngine;
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

    self.title = CABundleDisplayName;
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [self setupUI];
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
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self stopRotationTimer];
    [self saveActiveConversation];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"CAWorkspaceDidChangeNotification" object:nil];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateInputHeight];
}

- (void)dealloc
{
    [self stopPulseTimer];
    [self stopRotationTimer];
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
    [self.view addSubview:self.inputBar];

    self.attachmentHintLabel = [[UILabel alloc] init];
    self.attachmentHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentHintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.attachmentHintLabel.textColor = UIColor.secondaryLabelColor;
    [self.inputBar addSubview:self.attachmentHintLabel];

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

    self.attachButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.attachButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.attachButton setTitle:@"＋" forState:UIControlStateNormal];
    self.attachButton.titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightMedium];
    [self.attachButton addTarget:self action:@selector(handleAttach) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.attachButton];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sendButton setTitle:@"发送" forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [self.sendButton addTarget:self action:@selector(handleSend) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.sendButton];

    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stopButton setTitle:@"停止" forState:UIControlStateNormal];
    self.stopButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [self.stopButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(handleStop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.hidden = YES;
    [self.inputBar addSubview:self.stopButton];

    [self setupRuntimeBanner];
    [self setupComposerPopup];

    self.inputHeightConstraint = [self.composerField.heightAnchor constraintEqualToConstant:36.0];
    self.inputBottomConstraint = [self.inputBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusStrip.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.statusStrip.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.statusStrip.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.statusStrip.heightAnchor constraintEqualToConstant:30.0],

        [self.statusDot.leadingAnchor constraintEqualToAnchor:self.statusStrip.leadingAnchor constant:12.0],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.statusStrip.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:8.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:8.0],

        [self.statusTitleLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:8.0],
        [self.statusTitleLabel.centerYAnchor constraintEqualToAnchor:self.statusStrip.centerYAnchor],

        [self.statusDetailLabel.leadingAnchor constraintEqualToAnchor:self.statusTitleLabel.trailingAnchor constant:8.0],
        [self.statusDetailLabel.trailingAnchor constraintEqualToAnchor:self.statusStrip.trailingAnchor constant:-12.0],
        [self.statusDetailLabel.centerYAnchor constraintEqualToAnchor:self.statusStrip.centerYAnchor],

        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputBottomConstraint,

        [self.attachmentHintLabel.topAnchor constraintEqualToAnchor:self.inputBar.topAnchor constant:6.0],
        [self.attachmentHintLabel.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:12.0],
        [self.attachmentHintLabel.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-12.0],

        [self.composerField.topAnchor constraintEqualToAnchor:self.attachmentHintLabel.bottomAnchor constant:4.0],
        [self.composerField.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:34.0],
        [self.composerField.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-78.0],
        self.inputHeightConstraint,

        [self.inputPlaceholderLabel.topAnchor constraintEqualToAnchor:self.composerField.topAnchor constant:8.0],
        [self.inputPlaceholderLabel.leadingAnchor constraintEqualToAnchor:self.composerField.leadingAnchor constant:5.0],
        [self.inputPlaceholderLabel.trailingAnchor constraintEqualToAnchor:self.composerField.trailingAnchor],

        [self.attachButton.leadingAnchor constraintEqualToAnchor:self.inputBar.leadingAnchor constant:4.0],
        [self.attachButton.topAnchor constraintEqualToAnchor:self.composerField.topAnchor],
        [self.attachButton.widthAnchor constraintEqualToConstant:30.0],
        [self.attachButton.heightAnchor constraintEqualToConstant:30.0],

        [self.stopButton.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-12.0],
        [self.stopButton.topAnchor constraintEqualToAnchor:self.composerField.topAnchor constant:4.0],

        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.inputBar.trailingAnchor constant:-12.0],
        [self.sendButton.topAnchor constraintEqualToAnchor:self.composerField.topAnchor constant:4.0],

        [self.inputBar.bottomAnchor constraintEqualToAnchor:self.composerField.bottomAnchor constant:10.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.statusStrip.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.runtimeBanner.topAnchor],
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
        [self.runtimeBanner.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],
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
    UIBarButtonItem *history = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"list.bullet"]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(handleShowHistory)];
    UIBarButtonItem *compose = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"square.and.pencil"]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(handleNewChat)];
    UIBarButtonItem *settings = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"gearshape"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(handleOpenSettings)];
    compose.image = [UIImage systemImageNamed:@"square.and.pencil"];
    settings.image = [UIImage systemImageNamed:@"gearshape"];
    self.navigationItem.leftBarButtonItem = history;
    self.navigationItem.rightBarButtonItems = @[ settings, compose ];
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
    self.composerField.text = @"";
    [self updateInputHeight];
    [self refreshAttachmentPlaceholder];
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

    if (self.chatTurnActive) {
        [self appendNoticeText:@"上一轮还在运行：可以先点「停止」，或等它结束后再发。"];
        [self conversationDidChange];
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

    NSString *text = nil;
    if (!runtimeOK) {
        text = @"还没装 Codex 运行时，聊天发不出去。点「安装运行时」跳到诊断页安装，或先去设置里检查。";
    } else if (!providerOK) {
        BOOL thirdParty = [NSUserDefaults.standardUserDefaults boolForKey:CADefaultsUseThirdPartyProvider];
        text = thirdParty ? @"还没填第三方供应商的 API Key：去设置 → Provider 里填完再发。"
                          : @"还没登录官方账号：去设置里登录，或改用第三方供应商 + API Key。";
    }

    self.runtimeBannerLabel.text = text ?: @"";
    self.runtimeInstallButton.hidden = runtimeOK;
    self.runtimeBanner.hidden = !needsAttention;
    self.runtimeBannerHeightConstraint.constant = needsAttention ? 46.0 : 0.0;
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
    [self applyComposerPlaceholder];
    [self updateSendButtonState];
}

- (void)applyComposerPlaceholder
{
    NSArray<NSString *> *pool = [self composerPlaceholderPool];
    if (pool.count == 0) {
        self.composerPlaceholderText = @"";
    } else {
        NSUInteger index = self.composerPlaceholderIndex % pool.count;
        self.composerPlaceholderText = pool[index];
    }
    self.inputPlaceholderLabel.text = self.composerPlaceholderText;
    self.inputPlaceholderLabel.hidden = self.composerField.text.length > 0;
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

    [self rememberThreadIdentifierFromPayload:params];
    [self consumeUsageFromPayload:params];

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
    self.inputPlaceholderLabel.hidden = self.composerField.text.length > 0;
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
    popup.headerTitle = @"命令 · 技能 · MCP";
    popup.headerHint = @"点选插入";

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
        CAComposerPopupItem *empty = [[CAComposerPopupItem alloc] init];
        empty.identifier = @"empty";
        empty.title = CAComposerCatalog.sharedCatalog.loading ? @"正在扫描技能 / MCP…" : @"没有匹配的命令或技能";
        empty.subtitle = CAComposerCatalog.sharedCatalog.loading ? @"稍候自动刷新" : @"换个关键词试试（技能需要安装到 CODEX_HOME/skills）";
        empty.symbol = @"magnifyingglass";
        [empty setEnabled:@NO];
        CAComposerPopupSection *section = [[CAComposerPopupSection alloc] init];
        section.title = @"结果";
        section.items = @[ empty ];
        [sections addObject:section];
    }
    return sections;
}

- (NSString *)titleForComposerCatalogKind:(CAComposerCatalogKind)kind
{
    switch (kind) {
        case CAComposerCatalogKindSkill:  return @"技能";
        case CAComposerCatalogKindPlugin: return @"插件";
        case CAComposerCatalogKindMCP:    return @"MCP";
        case CAComposerCatalogKindPrompt: return @"命令";
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
    sidebar.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                                style:UIBarButtonItemStylePlain
                                                                               target:self
                                                                               action:@selector(closeHistoryDrawer)];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:sidebar];
    [self addChildViewController:navigation];
    navigation.view.translatesAutoresizingMaskIntoConstraints = NO;
    [navigation didMoveToParentViewController:self];
    self.historySidebarNavigationController = navigation;
    self.conversationSidebar = sidebar;

    UIView *drawer = [[UIView alloc] init];
    drawer.translatesAutoresizingMaskIntoConstraints = NO;
    drawer.backgroundColor = UIColor.systemBackgroundColor;
    drawer.layer.shadowColor = UIColor.blackColor.CGColor;
    drawer.layer.shadowOpacity = 0.18;
    drawer.layer.shadowRadius = 8.0;
    [drawer addSubview:navigation.view];
    [self.view addSubview:drawer];
    self.historyDrawer = drawer;

    CGFloat width = MIN(320.0, MAX(260.0, self.view.bounds.size.width * 0.78));
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
    [self appendNoticeText:@"工作区管理页还没接入（CAWorkspaceViewController 仍是骨架）。"];
    [self conversationDidChange];
    return nil;
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

@end
