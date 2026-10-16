//
//  CAChatViewController.m
//
//  会话页外壳：消息表格 + 输入框 + 运行状态条。
//
//  引擎接线（原包行为）：
//    · 默认走 CACodexEngine -startExecWithPrompt:workspace:model:executionMode:sandbox:output:completion:
//      逐行 JSON（--json）解析成消息；thread_id 记住后供下一轮复用。
//    · defaults 键 CodexUsePersistentAppServerChat 为真时改走
//      -sendPromptViaPersistentAppServer:threadId:completion:（常驻 app-server turn）。
//    · 后台保活：UIBackgroundModes=audio + 静音音频 + renewBackgroundTask（原包同款做法）。
//

#import "CAChatViewController.h"
#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CACodexEngine.h"
#import "CARemoteOperations.h"
#import "CAExecutionEnvironment.h"
#import "CARuntimeCatalog.h"
#import "CASettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString * const kChatExecutionModeDefaultsKey = @"CodexExecutionMode";
static NSString * const kChatActiveThreadDefaultsKey   = @"CodexActiveThreadID";
static NSString * const kChatPlaceholderPoolKey        = @"CodexComposerPlaceholderPool";
static NSString * const kChatCellReuseIdentifier       = @"CAChatShellCell";
static const NSTimeInterval kChatPlaceholderRotateInterval = 12.0;
static const NSTimeInterval kChatSilentAudioSeconds        = 3.0;
static const NSUInteger kChatRawTailLimit                  = 40;

typedef NS_ENUM(NSInteger, CAChatShellRole) {
    CAChatShellRoleUser      = 0,
    CAChatShellRoleAssistant = 1,
    CAChatShellRoleSystem    = 2,
};

#pragma mark - 消息模型（私有）

@interface CAChatShellMessage : NSObject
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, assign) CAChatShellRole role;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, assign, getter=isStreaming) BOOL streaming;
@property (nonatomic, assign, getter=isFailed) BOOL failed;
@property (nonatomic, strong) NSDate *createdAt;
@end

@implementation CAChatShellMessage

- (instancetype)init
{
    if ((self = [super init])) {
        _messageId = NSUUID.UUID.UUIDString;
        _text = @"";
        _createdAt = [NSDate date];
    }
    return self;
}

@end

#pragma mark - 消息 Cell（私有）

@interface CAChatShellCell : UITableViewCell

@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UILabel *bubbleLabel;
@property (nonatomic, strong, nullable) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *trailingConstraint;

- (void)configureWithRole:(CAChatShellRole)role text:(NSString *)text streaming:(BOOL)streaming failed:(BOOL)failed;

@end

@implementation CAChatShellCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _bubbleView = [[UIView alloc] init];
        _bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
        _bubbleView.layer.cornerRadius = 14.0;
        _bubbleView.layer.masksToBounds = YES;
        [self.contentView addSubview:_bubbleView];

        _bubbleLabel = [[UILabel alloc] init];
        _bubbleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bubbleLabel.numberOfLines = 0;
        _bubbleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _bubbleLabel.textColor = UIColor.labelColor;
        [_bubbleView addSubview:_bubbleLabel];

        _leadingConstraint  = [_bubbleView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor];
        _trailingConstraint = [_bubbleView.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor];

        [NSLayoutConstraint activateConstraints:@[
            [_bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],
            [_bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82],
            [_bubbleLabel.topAnchor constraintEqualToAnchor:_bubbleView.topAnchor constant:10.0],
            [_bubbleLabel.bottomAnchor constraintEqualToAnchor:_bubbleView.bottomAnchor constant:-10.0],
            [_bubbleLabel.leadingAnchor constraintEqualToAnchor:_bubbleView.leadingAnchor constant:12.0],
            [_bubbleLabel.trailingAnchor constraintEqualToAnchor:_bubbleView.trailingAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)configureWithRole:(CAChatShellRole)role text:(NSString *)text streaming:(BOOL)streaming failed:(BOOL)failed
{
    self.bubbleLabel.text = text;
    self.bubbleLabel.textColor = (role == CAChatShellRoleUser) ? UIColor.whiteColor : UIColor.labelColor;

    if (role == CAChatShellRoleUser) {
        self.bubbleView.backgroundColor = [UIColor colorWithRed:0.06 green:0.45 blue:0.98 alpha:1.0];
        self.trailingConstraint.active = YES;
        self.leadingConstraint.active = NO;
        self.bubbleLabel.textAlignment = NSTextAlignmentRight;
    } else if (role == CAChatShellRoleSystem) {
        self.bubbleView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
        self.leadingConstraint.active = YES;
        self.trailingConstraint.active = NO;
        self.bubbleLabel.textAlignment = NSTextAlignmentLeft;
        self.bubbleLabel.textColor = failed ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    } else {
        self.bubbleView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.leadingConstraint.active = YES;
        self.trailingConstraint.active = NO;
        self.bubbleLabel.textAlignment = NSTextAlignmentLeft;
    }

    if (streaming) {
        self.bubbleLabel.text = [text stringByAppendingString:@"▍"];
    }
}

@end

#pragma mark - 会话页

@interface CAChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UIDocumentPickerDelegate>

@property (nonatomic, strong, readwrite) CACodexEngine *chatEngine;
@property (nonatomic, strong, readwrite) NSMutableArray *messages;

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

@property (nonatomic, strong) NSMutableArray<NSString *> *pendingAttachments;
@property (nonatomic, strong) NSMutableArray<NSString *> *rawTailLines;

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

- (void)appendMessageWithRole:(CAChatShellRole)role text:(NSString *)text detail:(nullable NSString *)detail;
- (void)appendAssistantDelta:(NSString *)delta;
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

- (NSString *)conversationFilePath;
- (void)loadActiveConversation;

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
    [self loadActiveConversation];
    [self refreshAttachmentPlaceholder];
    [self renderStatusStrip];
    [self setHistorySidebar:[self buildHistorySidebar]];

    CALog(CALogLevelInfo, @"CHAT", @"chat view loaded workspace=%@ thread=%@", self.workspacePath, self.threadId ?: @"(none)");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshAttachmentPlaceholder];
    [self startRotationTimer];
    if (self.thinking) {
        [self startPulseTimer];
    }
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
    [self.tableView registerClass:CAChatShellCell.class forCellReuseIdentifier:kChatCellReuseIdentifier];
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
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],
    ]];
}

- (void)setupNavigationItems
{
    UIBarButtonItem *history = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"list.bullet"]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(handleShowHistory)];
    UIBarButtonItem *compose = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.pencil"]
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(handleNewChat)];
    UIBarButtonItem *settings = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(handleOpenSettings)];
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
    UIView *sidebar = [[UIView alloc] init];
    sidebar.backgroundColor = UIColor.secondarySystemBackgroundColor;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"历史会话";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.numberOfLines = 0;
    hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    hint.textColor = UIColor.secondaryLabelColor;
    hint.text = [NSString stringWithFormat:@"会话目录：\n%@", CARuntimePaths.conversationsDirectory];

    [sidebar addSubview:title];
    [sidebar addSubview:hint];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:sidebar.safeAreaLayoutGuide.topAnchor constant:16.0],
        [title.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16.0],
        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [hint.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16.0],
        [hint.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-16.0],
    ]];
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

    NSArray<NSString *> *attachments = [self.pendingAttachments copy];
    [self.pendingAttachments removeAllObjects];
    self.composerField.text = @"";
    [self updateInputHeight];
    [self refreshAttachmentPlaceholder];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:CADefaultsUsePersistentAppServer]) {
        [self sendPromptViaPersistentAppServer:text attachments:attachments];
        return;
    }

    NSString *composed = [self composedPromptWithText:text attachments:attachments];
    [self appendMessageWithRole:CAChatShellRoleUser text:composed detail:nil];
    self.thinking = YES;
    [self startPulseTimer];
    [self renderStatusStrip];
    [self conversationDidChange];

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
            strongSelf.thinking = NO;
            [strongSelf stopPulseTimer];
            if (errorMessage.length > 0 || exitStatus != 0) {
                NSString *note = errorMessage.length > 0 ? errorMessage : [NSString stringWithFormat:@"运行结束（退出码 %ld）", (long)exitStatus];
                [strongSelf appendMessageWithRole:CAChatShellRoleSystem text:note detail:nil];
            }
            [strongSelf flushStreamingMessages];
            [strongSelf saveActiveConversation];
        });
    }];
}

- (void)sendPromptViaPersistentAppServer:(NSString *)prompt attachments:(NSArray *)attachments
{
    NSString *text = [self trimmedText:prompt];
    if (text.length == 0 && attachments.count == 0) return;

    NSString *composed = [self composedPromptWithText:text attachments:attachments];
    [self appendMessageWithRole:CAChatShellRoleUser text:composed detail:nil];
    self.thinking = YES;
    [self startPulseTimer];
    [self renderStatusStrip];
    [self conversationDidChange];

    NSString *threadId = self.threadId;
    CALog(CALogLevelInfo, @"CHAT", @"turn via app-server thread=%@ chars=%lu", threadId ?: @"(new)", (unsigned long)composed.length);

    __weak typeof(self) weakSelf = self;
    [[CACodexEngine sharedEngine] sendPromptViaPersistentAppServer:composed
                                                          threadId:threadId
                                                        completion:^(NSInteger exitStatus, NSString *errorMessage) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.thinking = NO;
            [strongSelf stopPulseTimer];
            if (errorMessage.length > 0 || exitStatus != 0) {
                NSString *note = errorMessage.length > 0 ? errorMessage : [NSString stringWithFormat:@"运行结束（退出码 %ld）", (long)exitStatus];
                [strongSelf appendMessageWithRole:CAChatShellRoleSystem text:note detail:nil];
            }
            [strongSelf flushStreamingMessages];
            [strongSelf saveActiveConversation];
        });
    }];
}

- (void)handleStop
{
    CALog(CALogLevelInfo, @"CHAT", @"stop requested thread=%@", self.threadId ?: @"(none)");
    [[CACodexEngine sharedEngine] invalidatePersistentServerWithReason:@"user-stop"];
    self.thinking = NO;
    [self stopPulseTimer];
    [self appendMessageWithRole:CAChatShellRoleSystem text:@"已停止当前运行" detail:nil];
    [self flushStreamingMessages];
    [self renderStatusStrip];
    [self saveActiveConversation];
}

- (void)handleNewChat
{
    [self saveActiveConversation];
    self.threadId = nil;
    [self.messages removeAllObjects];
    self.lastUsageSummary = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kChatActiveThreadDefaultsKey];
    [self conversationDidChange];
    [self renderStatusStrip];
    CALog(CALogLevelInfo, @"CHAT", @"new conversation");
}

- (void)handleShowHistory
{
    if (!self.historySidebar) return;
    BOOL hidden = self.historySidebar.hidden;
    self.historySidebar.hidden = NO;
    self.historySidebar.alpha = hidden ? 0.0 : 1.0;
    [UIView animateWithDuration:0.2 animations:^{
        self.historySidebar.alpha = hidden ? 1.0 : 0.0;
    } completion:^(BOOL finished) {
        self.historySidebar.hidden = !hidden;
    }];
}

- (void)closeHistorySidebar
{
    if (!self.historySidebar || self.historySidebar.hidden) return;
    [UIView animateWithDuration:0.2 animations:^{
        self.historySidebar.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.historySidebar.hidden = YES;
        self.historySidebar.alpha = 1.0;
    }];
}

- (void)handleOpenSettings
{
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[CASettingsViewController alloc] init]];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)workspaceDidChange:(NSNotification *)notification
{
    NSString *workspace = notification.userInfo[@"workspacePath"];
    if (workspace.length > 0) {
        self.workspacePath = workspace;
        CALog(CALogLevelInfo, @"CHAT", @"workspace changed path=%@", workspace);
        [self refreshAttachmentPlaceholder];
        [self renderStatusStrip];
    }
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

- (void)appendMessageWithRole:(CAChatShellRole)role text:(NSString *)text detail:(NSString *)detail
{
    CAChatShellMessage *message = [[CAChatShellMessage alloc] init];
    message.role = role;
    message.text = text ?: @"";
    message.detail = detail;
    [self.messages addObject:message];
    [self conversationDidChange];
}

- (void)appendAssistantDelta:(NSString *)delta
{
    CAChatShellMessage *last = self.messages.lastObject;
    if (![last isKindOfClass:CAChatShellMessage.class] || last.role != CAChatShellRoleAssistant || !last.streaming) {
        CAChatShellMessage *message = [[CAChatShellMessage alloc] init];
        message.role = CAChatShellRoleAssistant;
        message.streaming = YES;
        message.text = delta ?: @"";
        [self.messages addObject:message];
        [self conversationDidChange];
        return;
    }
    last.text = [last.text stringByAppendingString:delta ?: @""];
    [self refreshStreamingRow];
}

- (void)flushStreamingMessages
{
    [self finalizeStreamingMessages];
    [self.tableView reloadData];
    if (self.autoFollowLatest) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)finalizeStreamingMessages
{
    for (CAChatShellMessage *message in self.messages) {
        if (message.streaming) {
            message.streaming = NO;
            [self conversationDidChange];
            return;
        }
    }
}

- (void)refreshStreamingRow
{
    if (self.messages.count == 0) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)self.messages.count - 1 inSection:0];
    CAChatShellCell *cell = (CAChatShellCell *)[self.tableView cellForRowAtIndexPath:path];
    if (!cell) return;
    CAChatShellMessage *message = self.messages.lastObject;
    [cell configureWithRole:message.role text:message.text streaming:message.streaming failed:message.failed];
    if (self.autoFollowLatest) {
        [self scrollToBottomAnimated:NO];
    }
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
    if (self.messages.count == 0) return;
    NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - 引擎输出解析（--json 逐行）

- (void)handleEngineOutputLine:(NSString *)line isStderr:(BOOL)isStderr
{
    if (line.length == 0) return;

    if (isStderr) {
        [self renderStreamTail:[NSString stringWithFormat:@"stderr %@", line]];
        return;
    }

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![object isKindOfClass:NSDictionary.class]) {
        [self renderStreamTail:line];
        return;
    }

    NSDictionary *event = object;
    NSDictionary *payload = [event[@"msg"] isKindOfClass:NSDictionary.class] ? event[@"msg"] : event;
    [self rememberThreadIdentifierFromPayload:payload];
    [self consumeUsageFromPayload:payload];

    NSString *type = [payload[@"type"] isKindOfClass:NSString.class] ? payload[@"type"] : @"";
    NSString *text = [self textFromPayload:payload];

    if ([type containsString:@"error"] || payload[@"error"]) {
        NSString *errorText = text.length > 0 ? text : [NSString stringWithFormat:@"%@", payload[@"error"] ?: type];
        [self appendMessageWithRole:CAChatShellRoleSystem text:errorText detail:nil];
        [self conversationDidChange];
        return;
    }

    if (text.length == 0) {
        [self renderStreamTail:type.length > 0 ? type : line];
        return;
    }

    BOOL delta = [type containsString:@"delta"] || [payload[@"delta"] isKindOfClass:NSString.class];
    if (delta) {
        [self appendAssistantDelta:text];
    } else {
        [self appendMessageWithRole:CAChatShellRoleAssistant text:text detail:type.length > 0 ? type : nil];
        [self conversationDidChange];
    }
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
    return (NSInteger)self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CAChatShellCell *cell = (CAChatShellCell *)[tableView dequeueReusableCellWithIdentifier:kChatCellReuseIdentifier forIndexPath:indexPath];
    CAChatShellMessage *message = self.messages[(NSUInteger)indexPath.row];
    [cell configureWithRole:message.role text:message.text streaming:message.streaming failed:message.failed];
    return cell;
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    [self updateInputHeight];
    [self updateSendButtonState];
    self.inputPlaceholderLabel.hidden = textView.text.length > 0;
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@"\n"]) {
        [self submitCurrentComposerText];
        return NO;
    }
    return YES;
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

#pragma mark - 会话持久化

- (void)saveActiveConversation
{
    if (self.messages.count == 0) return;

    NSMutableArray<NSDictionary *> *payload = [NSMutableArray array];
    for (CAChatShellMessage *message in self.messages) {
        [payload addObject:@{
            @"message_id": message.messageId ?: @"",
            @"role": @(message.role),
            @"text": message.text ?: @"",
            @"created_at": @(message.createdAt.timeIntervalSince1970),
        }];
    }

    NSDictionary *document = @{
        @"thread_id": self.threadId ?: @"",
        @"workspace": self.workspacePath ?: @"",
        @"updated_at": @([NSDate date].timeIntervalSince1970),
        @"messages": payload,
    };

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) {
        CALog(CALogLevelWarn, @"CHAT", @"conversation encode failed: %@", error);
        return;
    }

    NSString *path = [self conversationFilePath];
    if (![CARuntimePaths ensureDirectory:path.stringByDeletingLastPathComponent mode:0700 error:&error]) {
        CALog(CALogLevelWarn, @"CHAT", @"conversation directory failed: %@", error);
        return;
    }
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        CALog(CALogLevelWarn, @"CHAT", @"conversation save failed: %@", error);
        return;
    }

    NSString *key = [NSString stringWithFormat:CADefaultsActiveConversationFmt, self.workspacePath.lastPathComponent ?: @"default"];
    [NSUserDefaults.standardUserDefaults setObject:path forKey:key];
    CALog(CALogLevelDebug, @"CHAT", @"conversation saved messages=%lu path=%@", (unsigned long)self.messages.count, path);
}

- (NSString *)conversationFilePath
{
    NSString *identifier = self.threadId.length > 0 ? self.threadId : @"active";
    NSString *name = [identifier stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [CARuntimePaths.conversationsDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"] ?: @"conversation.json"];
}

- (void)loadActiveConversation
{
    NSString *key = [NSString stringWithFormat:CADefaultsActiveConversationFmt, self.workspacePath.lastPathComponent ?: @"default"];
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:key];
    if (path.length == 0) return;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    id document = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![document isKindOfClass:NSDictionary.class]) return;

    NSArray *stored = document[@"messages"];
    if (![stored isKindOfClass:NSArray.class]) return;

    [self.messages removeAllObjects];
    for (NSDictionary *item in stored) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        CAChatShellMessage *message = [[CAChatShellMessage alloc] init];
        message.messageId = [item[@"message_id"] isKindOfClass:NSString.class] ? item[@"message_id"] : NSUUID.UUID.UUIDString;
        message.role = (CAChatShellRole)[item[@"role"] integerValue];
        message.text = [item[@"text"] isKindOfClass:NSString.class] ? item[@"text"] : @"";
        [self.messages addObject:message];
    }
    [self conversationDidChange];
    CALog(CALogLevelInfo, @"CHAT", @"conversation restored messages=%lu path=%@", (unsigned long)self.messages.count, path);
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

    historySidebar.translatesAutoresizingMaskIntoConstraints = NO;
    historySidebar.hidden = YES;
    [self.view addSubview:historySidebar];
    [NSLayoutConstraint activateConstraints:@[
        [historySidebar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [historySidebar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [historySidebar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [historySidebar.widthAnchor constraintEqualToConstant:280.0],
    ]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeHistorySidebar)];
    [historySidebar addGestureRecognizer:tap];
}

// ==PARITY-METHOD-STUBS-BEGIN==
- (void)conversationSidebar:(id)arg1 didDeleteRecord:(id)arg2
{
    // TODO(parity): 行为按原包实现补全
}

- (void)conversationSidebar:(id)arg1 didMoveRecord:(id)arg2 toWorkspace:(id)arg3
{
    // TODO(parity): 行为按原包实现补全
}

- (void)conversationSidebar:(id)arg1 didRenameRecord:(id)arg2 title:(id)arg3
{
    // TODO(parity): 行为按原包实现补全
}

- (void)conversationSidebar:(id)arg1 didRequestNewConversationForWorkspace:(id)arg2
{
    // TODO(parity): 行为按原包实现补全
}

- (void)conversationSidebar:(id)arg1 didRequestPermanentDeleteWorkspaceAtPath:(id)arg2
{
    // TODO(parity): 行为按原包实现补全
}

- (void)conversationSidebar:(id)arg1 didSelectRecord:(id)arg2
{
    // TODO(parity): 行为按原包实现补全
}

// ==PARITY-METHOD-STUBS-END==
@end
