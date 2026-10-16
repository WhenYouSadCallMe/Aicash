//
//  CAChatViewController.h — 会话页（消息表格 + 输入框 + 运行状态条）
//
//  原包符号对齐（选择器逐字一致，用于符号对照）：
//    -sendPromptViaPersistentAppServer:attachments:  -handleStop  -saveActiveConversation
//    -flushStreamingMessages  -refreshAttachmentPlaceholder  -setThinkingSummaryCard:
//    -setComposerPlaceholderIndex:  -setHistorySidebar:  -installAudioObserversIfNeeded
//    -configureAudioSession  -startSilentAudio  -renewBackgroundTask
//    -startPulseTimer  -stopPulseTimer
//

#import <UIKit/UIKit.h>

@class CACodexEngine;

NS_ASSUME_NONNULL_BEGIN


// ==PARITY-FORWARD-DECLS-BEGIN==
@class CAAgentStatusViewController, CAComposerAttachmentGridView, CAComposerCameraCoordinator, CAComposerPopupView;
@class CAComposerTextView, CAContextUsageViewController, CAConversationRecord, CADisplayLink, CAGitRepository;
@class CAGradientLayer, CAMessageItem, CAPlanProgressViewController, CAShapeLayer, CATodoProgressButton;
// ==PARITY-FORWARD-DECLS-END==

@interface CAChatViewController : UIViewController

/// 会话引擎（默认取 CACodexEngine +sharedEngine）
@property (nonatomic, strong, readonly) CACodexEngine *chatEngine;

/// 消息模型数组（元素为私有实现类 CAChatShellMessage）
@property (nonatomic, strong, readonly) NSMutableArray *messages;

/// codex 侧 thread / conversation 标识（app-server turn 复用）
@property (nonatomic, copy, nullable) NSString *threadId;

/// 当前工作区路径（默认取 CodexActiveWorkspace，缺省为 Documents/Codex）
@property (nonatomic, copy, nullable) NSString *workspacePath;

/// 输入框占位文案
@property (nonatomic, copy, nullable) NSString *composerPlaceholderText;

/// 占位文案在占位池中的下标（原包 ivar: _composerPlaceholderIndex）
@property (nonatomic, assign) NSUInteger composerPlaceholderIndex;

/// 是否正在运行一轮（原包 ivar: _isThinking）
@property (nonatomic, assign, getter=isThinking) BOOL thinking;

/// 思考中卡片摘要文案（原包 ivar: _thinkingSummaryCard）
@property (nonatomic, strong, nullable) NSString *thinkingSummaryCard;

/// 历史会话抽屉视图（原包 ivar: _historySidebar）
@property (nonatomic, strong, nullable) UIView *historySidebar;

/// 是否自动跟随最新消息（原包 ivar: _autoFollowLatest）
@property (nonatomic, assign) BOOL autoFollowLatest;

#pragma mark - 发送 / 停止

/// 通过常驻 app-server 发一轮（附件为本地文件路径数组）
- (void)sendPromptViaPersistentAppServer:(NSString *)prompt attachments:(nullable NSArray *)attachments;

/// 停止当前运行
- (void)handleStop;

#pragma mark - 会话持久化 / 刷新

- (void)saveActiveConversation;
- (void)flushStreamingMessages;
- (void)refreshAttachmentPlaceholder;

#pragma mark - 后台保活（沿用原包 audio 后台模式 + 静音音频）

- (void)installAudioObserversIfNeeded;
- (void)configureAudioSession;
- (void)startSilentAudio;
- (void)renewBackgroundTask;

#pragma mark - 运行状态脉冲

- (void)startPulseTimer;
- (void)stopPulseTimer;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) CAConversationRecord * activeRecord;
    @property (nonatomic, strong, nullable) CAAgentStatusViewController * agentStatusController;
    @property (nonatomic, strong, nullable) UIImageView * agentStatusIcon;
    @property (nonatomic, assign) unsigned long long agentStatusRotationIndex;
    @property (nonatomic, assign) int agentStatusRotationTimer;
    @property (nonatomic, strong, nullable) NSString * approvedPlanDispatchConversationId;
    @property (nonatomic, strong, nullable) NSString * approvedPlanExecutionConversationId;
    @property (nonatomic, strong, nullable) UIButton * attachButton;
    @property (nonatomic, strong, nullable) CAComposerAttachmentGridView * attachmentGridView;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * attachmentStripHeightConstraint;
    @property (nonatomic, strong, nullable) NSMutableDictionary * backgroundRuns;
    @property (nonatomic, strong, nullable) CAGitRepository * badgeRepository;
    @property (nonatomic, strong, nullable) NSString * badgeWorkspace;
    @property (nonatomic, strong, nullable) NSDictionary * blockByID;
    @property (nonatomic, strong, nullable) UIButton * bottomEffortBtn;
    @property (nonatomic, strong, nullable) UIButton * bottomModelBtn;
    @property (nonatomic, strong, nullable) UICollectionViewDiffableDataSource * chatDataSource;
    @property (nonatomic, assign) unsigned long long chatViewportGeneration;
    @property (nonatomic, strong, nullable) UIButton * clearChatButton;
    @property (nonatomic, strong, nullable) NSDictionary * compactGroupByMessageID;
    @property (nonatomic, strong, nullable) CAComposerCameraCoordinator * composerCameraCoordinator;
    @property (nonatomic, strong, nullable) CAShapeLayer * composerContextGlowLayer;
    @property (nonatomic, strong, nullable) NSArray * composerFilteredMentionPaths;
    @property (nonatomic, assign) BOOL composerHasFocusedOnce;
    @property (nonatomic, assign) long long composerMentionAnchor;
    @property (nonatomic, strong, nullable) NSArray * composerMentionPaths;
    @property (nonatomic, assign) unsigned long long composerMentionScanGeneration;
    @property (nonatomic, strong, nullable) NSDate * composerMentionScannedAt;
    @property (nonatomic, strong, nullable) NSString * composerMentionWorkspacePath;
    @property (nonatomic, strong, nullable) UIButton * composerMenuButton;
    @property (nonatomic, assign) long long composerNextPasteID;
    @property (nonatomic, strong, nullable) NSArray * composerPlaceholderPool;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * composerPopupHeightConstraint;
    @property (nonatomic, assign) long long composerPopupMode;
    @property (nonatomic, strong, nullable) CAComposerPopupView * composerPopupView;
    @property (nonatomic, assign) BOOL composerPopupVisible;
    @property (nonatomic, strong, nullable) UIButton * composerResizeHandleButton;
    @property (nonatomic, assign) double composerResizeLiveHeight;
    @property (nonatomic, assign) double composerResizeStartHeight;
    @property (nonatomic, strong, nullable) NSString * composerSlashFilter;
    @property (nonatomic, assign) BOOL composerSwipeArmed;
    @property (nonatomic, strong, nullable) UIPanGestureRecognizer * composerSwipeGesture;
    @property (nonatomic, assign) BOOL composerSwipeHasAnchor;
    @property (nonatomic, strong, nullable) UIImageView * composerSwipeHintIcon;
    @property (nonatomic, strong, nullable) UILabel * composerSwipeHintLabel;
    @property (nonatomic, strong, nullable) UIView * composerSwipeHintView;
    @property (nonatomic, assign) long long composerUsageHintGeneration;
    @property (nonatomic, assign) BOOL composerUsageHintUnconsumed;
    @property (nonatomic, strong, nullable) UILabel * contextCaption;
    @property (nonatomic, strong, nullable) UIButton * contextPillBtn;
    @property (nonatomic, strong, nullable) CAContextUsageViewController * contextUsageController;
    @property (nonatomic, assign) int conversationSaveTimer;
    @property (nonatomic, assign) unsigned long long conversationSelectionGeneration;
    @property (nonatomic, assign) BOOL deferredMarkdownLayoutScheduled;
    @property (nonatomic, strong, nullable) UIButton * executionModeButton;
    @property (nonatomic, strong, nullable) UIImageView * executionModeIcon;
    @property (nonatomic, strong, nullable) UILabel * executionModeLabel;
    @property (nonatomic, strong, nullable) NSMutableSet * expandedCompactOperationGroupIDs;
    @property (nonatomic, strong, nullable) CAMessageItem * generatedArtifactMessage;
    @property (nonatomic, strong, nullable) NSMutableOrderedSet * generatedArtifactPaths;
    @property (nonatomic, assign) unsigned long long gitBadgeGeneration;
    @property (nonatomic, strong, nullable) UILabel * gitBadgeLabel;
    @property (nonatomic, assign) int gitBadgePollTimer;
    @property (nonatomic, copy, nullable) id historyCloseCompletion;
    @property (nonatomic, strong, nullable) UIPanGestureRecognizer * historyDismissGesture;
    @property (nonatomic, strong, nullable) UIView * historyDrawer;
    @property (nonatomic, assign) BOOL historyDrawerAnimating;
    @property (nonatomic, assign) BOOL historyDrawerClosing;
    @property (nonatomic, assign) BOOL historyDrawerInteracting;
    @property (nonatomic, strong, nullable) UIControl * historyDrawerOverlay;
    @property (nonatomic, assign) double historyDrawerProgress;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * historyDrawerWidthConstraint;
    @property (nonatomic, strong, nullable) UIScreenEdgePanGestureRecognizer * historyOpenGesture;
    @property (nonatomic, assign) double historyPanStartProgress;
    @property (nonatomic, strong, nullable) UINavigationController * historySidebarNavigationController;
    @property (nonatomic, strong, nullable) NSArray * inFlightAttachments;
    @property (nonatomic, strong, nullable) UIView * inputBar;
    @property (nonatomic, strong, nullable) CAGradientLayer * inputBarGradientLayer;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * inputBarHeightConstraint;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * inputBottomConstraint;
    @property (nonatomic, strong, nullable) UIView * inputContainer;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * inputContainerHeightConstraint;
    @property (nonatomic, strong, nullable) CAComposerTextView * inputField;
    @property (nonatomic, strong, nullable) UILabel * inputPlaceholderLabel;
    @property (nonatomic, strong, nullable) UIButton * jumpBottomButton;
    @property (nonatomic, assign) double lastComposerAvailableHeight;
    @property (nonatomic, assign) double lastComposerWidth;
    @property (nonatomic, assign) double lastStreamRateUpdateAt;
    @property (nonatomic, assign) double lastStreamingLayoutAt;
    @property (nonatomic, assign) double legacyKeyboardOverlap;
    @property (nonatomic, strong, nullable) NSString * markdownFinalizeID;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * metadataHeightConstraint;
    @property (nonatomic, strong, nullable) UILabel * navigationStatusLabel;
    @property (nonatomic, assign) BOOL needsInitialBottomPosition;
    @property (nonatomic, strong, nullable) NSMutableSet * pendingActivityLayoutMessageIDs;
    @property (nonatomic, strong, nullable) NSString * pendingAnimatedMessageID;
    @property (nonatomic, copy, nullable) id pendingPlanDecisionAbort;
    @property (nonatomic, strong, nullable) NSString * pendingPlanDecisionConversationID;
    @property (nonatomic, strong, nullable) UINavigationController * pendingPlanDecisionNavigation;
    @property (nonatomic, strong, nullable) NSString * pendingProviderContextBridge;
    @property (nonatomic, strong, nullable) NSString * pendingReconfiguredMessageID;
    @property (nonatomic, strong, nullable) CATodoProgressButton * planProgressButton;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * planProgressButtonWidth;
    @property (nonatomic, strong, nullable) CAPlanProgressViewController * planProgressController;
    @property (nonatomic, assign) BOOL planProgressEditWithoutUpdateLogged;
    @property (nonatomic, strong, nullable) NSLayoutConstraint * planProgressLeadingGap;
    @property (nonatomic, strong, nullable) NSMutableSet * prefetchingBlockIDs;
    @property (nonatomic, assign) BOOL queueDrainPaused;
    @property (nonatomic, strong, nullable) UIView * quickActionBar;
    @property (nonatomic, strong, nullable) UIStackView * scrollJumpStack;
    @property (nonatomic, strong, nullable) NSString * selectionConversationKey;
    @property (nonatomic, strong, nullable) NSString * selectionWorkspaceKey;
    @property (nonatomic, strong, nullable) UIButton * sendButton;
    @property (nonatomic, assign) long long sendButtonVisualMode;
    @property (nonatomic, assign) BOOL sendButtonVisualStateInitialized;
    @property (nonatomic, assign) BOOL shareInboxImportPendingRetry;
    @property (nonatomic, strong, nullable) UIButton * sourceControlButton;
    @property (nonatomic, strong, nullable) NSString * stagedEntranceMessageID;
    @property (nonatomic, strong, nullable) NSMutableSet * steeringQueuedMessageIDs;
    @property (nonatomic, strong, nullable) CADisplayLink * streamDisplayLink;
    @property (nonatomic, assign) double streamDisplayPreferredFPS;
    @property (nonatomic, assign) BOOL subagentCostHintRefreshPending;
    @property (nonatomic, assign) BOOL suppressWorkspaceChangeNotification;
    @property (nonatomic, assign) BOOL terminalAssistantPresentationPending;
    @property (nonatomic, strong, nullable) NSDate * thinkingStartedAt;
    @property (nonatomic, strong, nullable) UIStackView * welcomeActions;
    @property (nonatomic, strong, nullable) UIImageView * welcomeIcon;
    @property (nonatomic, strong, nullable) UILabel * welcomeSubtitle;
    @property (nonatomic, strong, nullable) UIView * welcomeView;
// ==PARITY-PROPERTIES-END==






// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)conversationSidebarDidRequestClose:(id)arg1;
    - (id)conversationSidebarDidRequestNewConversation:(id)arg1;
    - (id)conversationSidebarDidRequestSettings:(id)arg1;
    - (id)conversationSidebarDidRequestUsage:(id)arg1;
    - (id)conversationSidebarDidRequestWorkspaces:(id)arg1;
    - (id)deleteWorkspaceConversationRecords:(id)arg1 index:(id)arg2 completion:(id)arg3;
    - (id)detachActiveConversationRunIfNeeded;
    - (id)didReceiveMemoryWarning;
    - (id)discardPendingComposerAttachments;
    - (id)dismissComposerPastedTextPreview;
    - (id)dismissHistorySidebarThen:(id)arg1;
    - (id)dismissKeyboardFromConversation:(id)arg1;
    - (id)dismissKeyboardTap;
    - (id)displayTextForPrompt:(id)arg1 attachments:(id)arg2 storedImages:(id)arg3;
    - (id)drainQueuedPromptIfPossible;
    - (id)editQueuedUserMessageInComposer:(id)arg1;
    - (id)enqueueComposerPromptWithText:(id)arg1 displayText:(id)arg2;
    - (id)ensureStreamDisplayLink;
    - (id)executePendingApprovedPlan;
    - (id)filteredComposerMentionPaths:(id)arg1;
    - (id)finalizeStreamingRenderAndSave;
    - (id)finishPermanentConversationDeletion:(id)arg1 sidebar:(id)arg2 background:(id)arg3 deletingActive:(id)arg4;
    - (id)finishStreamingAfterTurn;
    - (id)finishThinkingStatusWithTitle:(id)arg1 detail:(id)arg2;
    - (id)frameForItemAtIndexPath:(id)arg1;
    - (id)freshSidebarRecord:(id)arg1 sidebar:(id)arg2;
    - (id)gestureRecognizerShouldBegin:(id)arg1;
    - (id)handleAgentStatusInfo;
    - (id)handleBottomEffortBtnTapped;
    - (id)handleBottomModelBtnTapped;
    - (id)handleClearCurrentConversation;
    - (id)handleComposerFocusTap:(id)arg1;
    - (id)handleComposerMenu;
    - (id)handleComposerPopupItem:(id)arg1;
    - (id)handleComposerResizeDoubleTap:(id)arg1;
    - (id)handleComposerResizePan:(id)arg1;
    - (id)handleComposerSwipe:(id)arg1;
    - (id)handleContextInfo;
    - (id)handleExecutionModeTap;
    - (id)handleHistoryDismissPan:(id)arg1;
    - (id)handleHistoryEdgePan:(id)arg1;
    - (id)handleJumpToTop;
    - (id)handleOpenGitChanges;
    - (id)handleOpenWorkspaceManager;
    - (id)handleShowUsageDetails;
    - (id)handleWelcomeAction:(id)arg1;
    - (id)historyDrawerContainerController;
    - (id)historyDrawerTransition;
    - (id)importPendingSharedDocuments;
    - (id)indexPathForMessage:(id)arg1;
    - (id)inputFieldTopConstraint;
    - (id)inputTextHeightConstraint;
    - (id)insertComposerMentionPath:(id)arg1;
    - (id)insertComposerReference:(id)arg1;
    - (id)insertComposerText:(id)arg1;
    - (id)installHistoryEdgeGesture;
    - (id)invalidateLayoutForIndexPath:(id)arg1;
    - (id)isCurrentConversationSelection:(id)arg1 conversationId:(id)arg2 workspacePath:(id)arg3;
    - (id)isNearConversationBottom;
    - (id)setDismissKeyboardTap:(id)arg1;
    - (id)setHistoryDrawerTransition:(id)arg1;
    - (id)setInputFieldTopConstraint:(id)arg1;
    - (id)setInputTextHeightConstraint:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)acceptComposerCameraImage:(id)arg1;
    - (id)activateConversation:(id)arg1;
    - (id)activeSubagentSnapshots;
    - (id)addAttachmentURL:(id)arg1 image:(id)arg2;
    - (id)adoptThinkingMessage:(id)arg1;
    - (id)advanceConversationSelectionForRecord:(id)arg1;
    - (id)advanceStreamingMessages;
    - (id)agentIdentityDidChange;
    - (id)agentTurns;
    - (id)applyChatSnapshotAnimating:(id)arg1 completion:(id)arg2;
    - (id)applyRecordSelection:(id)arg1 resetEngine:(id)arg2;
    - (id)assistantMessageForID:(id)arg1;
    - (id)assistantTurnInsertionIndex;
    - (id)attachEngineForRecord:(id)arg1;
    - (id)backgroundRunKeyForConversationId:(id)arg1 workspacePath:(id)arg2;
    - (id)beginPromptText:(id)arg1 displayText:(id)arg2 attachments:(id)arg3 existingUserMessage:(id)arg4 dismissKeyboard:(id)arg5;
    - (id)bestEffortDeleteCodexThread:(id)arg1 workspacePath:(id)arg2 afterRetiringEngine:(id)arg3;
    - (id)captureCompletedPlanIfNeeded;
    - (id)chatAppDidBecomeActive:(id)arg1;
    - (id)chatCollectionLayout;
    - (id)chatDisplayModeDidChange;
    - (id)chipWithTitle:(id)arg1 action:(id)arg2;
    - (id)cleanupInFlightAttachments;
    - (id)closeHistoryDrawer;
    - (id)closeHistoryDrawerWithCompletion:(id)arg1;
    - (id)codexEngineDidClearPlan;
    - (id)codexEngineDidReceiveError:(id)arg1;
    - (id)codexEngineDidRequestPlanInput:(id)arg1 completion:(id)arg2;
    - (id)codexEngineDidUpdateSubagentUsage;
    - (id)commitTerminalAssistantPresentation;
    - (id)compactAgentModel:(id)arg1;
    - (id)composerAvailableHeight;
    - (id)composerChipValue:(id)arg1 fallback:(id)arg2;
    - (id)composerFileSymbolAndTintForPath:(id)arg1;
    - (id)composerFocusTap;
    - (id)composerInputAtScrollBottom;
    - (id)composerMaxResizableTextHeight;
    - (id)composerMentionContext;
    - (id)composerPastedTextDescriptors;
    - (id)composerPastedTexts;
    - (id)composerPersistedTextHeight;
    - (id)composerPopupItemForCatalogEntry:(id)arg1;
    - (id)composerResolvedResizeHeight;
    - (id)composerSlashContext;
    - (id)composerSlashSuppressedText;
    - (id)composerSlashTextDriven;
    - (id)composerSwipeAnchorTranslation;
    - (id)composerTopShadowLayer;
    - (id)composerUsageHintText;
    - (id)composerWorkspaceRoot;
    - (id)configuredCellForBlock:(id)arg1 indexPath:(id)arg2;
    - (id)consumeComposerUsageHintIfNeeded;
    - (id)consumeTextDrivenComposerSlash;
    - (id)conversationHasRunningWork:(id)arg1;
    - (id)isNearConversationTop;
    - (id)isPlanExecutionActive;
    - (id)isRetryableConversationDeleteTransportError:(id)arg1;
    - (id)isThreadNotFoundDeleteError:(id)arg1;
    - (id)jumpTopButton;
    - (id)latestPlanProgressDetail;
    - (id)makeConversationEngine;
    - (id)maximumConversationOffset;
    - (id)minimumConversationOffset;
    - (id)modelPricingDidChange:(id)arg1;
    - (id)nextQueuedUserMessage;
    - (id)openComposerPastedTextID:(id)arg1;
    - (id)openMarkdownTarget:(id)arg1;
    - (id)openPendingAttachmentAtIndex:(id)arg1;
    - (id)openSlashComposerPopupTextDriven:(id)arg1;
    - (id)persistActiveConversation;
    - (id)persistComposerTextHeight:(id)arg1;
    - (id)picker:(id)arg1 didFinishPicking:(id)arg2;
    - (id)positionInitialConversationAtBottomIfNeeded;
    - (id)preferredStreamingDisplayFPS;
    - (id)prepareEntranceForCell:(id)arg1 message:(id)arg2;
    - (id)prepareHistoryDrawer;
    - (id)presentCompactOperationMessage:(id)arg1;
    - (id)presentComposerCamera;
    - (id)presentComposerCatalogDetail:(id)arg1;
    - (id)presentComposerDocumentPicker;
    - (id)presentComposerPhotoPicker;
    - (id)presentConversationDeleteFailure:(id)arg1 fromSidebar:(id)arg2;
    - (id)presentMessageTextSelection:(id)arg1;
    - (id)presentPendingPlanDecisionIfPossible;
    - (id)presentPendingPlanReview;
    - (id)presentPreparedFinalMarkdownMessage:(id)arg1;
    - (id)presentRuntimeDiagnostics;
    - (id)presentSettingsFocusingRequiredRuntimes:(id)arg1;
    - (id)presentSettingsForRequiredRuntimes;
    - (id)presentWorkspaceDeleteFailure:(id)arg1 fromSidebar:(id)arg2;
    - (id)previewAttachmentAtPath:(id)arg1;
    - (id)promoteTransientConversationIfNeeded;
    - (id)providerContextBridgeForEngine:(id)arg1;
    - (id)rebuildAgentTurns;
    - (id)receiveExternalDocumentURL:(id)arg1;
    - (id)receivePendingSharedFiles;
    - (id)recordPlanQuestionChoice:(id)arg1 forQuestion:(id)arg2 conversationID:(id)arg3;
    - (id)refreshAgentStatusPillAnimated:(id)arg1;
    - (id)refreshBottomSelectors;
    - (id)refreshCollapsedCardWithoutRelayout:(id)arg1;
    - (id)refreshComposerPopupHeight;
    - (id)refreshComposerUsagePlaceholderWithContext:(id)arg1 cache:(id)arg2;
    - (id)refreshGitBadge;
    - (id)refreshLayoutForMessage:(id)arg1;
    - (id)refreshLayoutForMessage:(id)arg1 animated:(id)arg2;
    - (id)refreshLayoutForMessage:(id)arg1 animated:(id)arg2 preserveViewportAnchor:(id)arg3;
    - (id)refreshNavigationSubtitle;
    - (id)refreshOfficialQuota;
    - (id)refreshPlanProgressPill;
    - (id)refreshScrollJumpButtons;
    - (id)refreshSidebarRunningState;
    - (id)refreshStreamingMessage:(id)arg1;
    - (id)refreshUsageBadge;
    - (id)refreshUsageBadgeHintOnly:(id)arg1;
    - (id)refreshWelcomeState;
    - (id)reloadMentionComposerPopupScanning:(id)arg1 filter:(id)arg2;
    - (id)reloadMessagesFollowingBottom:(id)arg1;
    - (id)reloadSlashComposerPopupPreserving:(id)arg1;
    - (id)removeComposerPastedTextID:(id)arg1;
    - (id)removeHistoryDrawer;
    - (id)removePendingAttachmentAtIndex:(id)arg1;
    - (id)replaceGenericWaitingTitle:(id)arg1;
    - (id)requestPermanentThreadDeletion:(id)arg1 engine:(id)arg2 transientEngine:(id)arg3 retryCleanExit:(id)arg4 completion:(id)arg5;
    - (id)resetComposerSwipeVisuals;
    - (id)resolveComposerPastedTextInPrompt:(id)arg1 displayMode:(id)arg2;
    - (id)restorePlanPreferenceAfterApprovedExecution;
    - (id)rolloverBackendThreadForProviderChangeFromThirdParty:(id)arg1 oldBaseURL:(id)arg2 oldProviderName:(id)arg3 oldModel:(id)arg4 oldAPIKey:(id)arg5;
    - (id)rotateAgentStatusPill;
    - (id)scanComposerMentionFilesIfNeededForContext:(id)arg1;
    - (id)scheduleConversationSave;
    - (id)scheduleDeferredMarkdownLayoutForMessage:(id)arg1 followBottom:(id)arg2 immediate:(id)arg3;
    - (id)scheduleLiveActivityLayoutForMessage:(id)arg1;
    - (id)scheduleQueuedPromptDrain;
    - (id)scrollJumpButtonWithSystemName:(id)arg1 action:(id)arg2 accessibilityLabel:(id)arg3;
    - (id)selectHighlightedComposerPopupItem;
    - (id)setAgentTurns:(id)arg1;
    - (id)setComposerFocusTap:(id)arg1;
    - (id)setComposerPastedTexts:(id)arg1;
    - (id)setComposerPopupVisible:(id)arg1 animated:(id)arg2;
    - (id)setComposerSlashSuppressedText:(id)arg1;
    - (id)setComposerSlashTextDriven:(id)arg1;
    - (id)setComposerSwipeAnchorTranslation:(id)arg1;
    - (id)setComposerTopShadowLayer:(id)arg1;
    - (id)setComposerUsageHintText:(id)arg1;
    - (id)setConversationOffset:(id)arg1;
    - (id)setJumpTopButton:(id)arg1;
    - (id)setShareInboxImportInProgress:(id)arg1;
    - (id)setStreamTurnFinalizing:(id)arg1;
    - (id)settleHistoryDrawerOpen:(id)arg1;
    - (id)setupComposerPopup;
    - (id)setupWelcomeView;
    - (id)shareInboxImportInProgress;
    - (id)shortComposerTokenCount:(id)arg1;
    - (id)shouldFollowConversationBottom;
    - (id)shouldGroupBlockInCompactMode:(id)arg1;
    - (id)showCameraAttachmentFailure:(id)arg1;
    - (id)showComposerUsageHintAfterTurn;
    - (id)showPlanProgressPanel;
    - (id)showPlanQuestionTransitionAwaitingDecision:(id)arg1;
    - (id)startThinkingStatus;
    - (id)stashComposerPastedText:(id)arg1;
    - (id)steerQueuedUserMessage:(id)arg1;
    - (id)stopCurrentAgentAndPauseQueue;
    - (id)streamDisplayLinkTick:(id)arg1;
    - (id)streamTurnFinalizing;
    - (id)switchToWorkspacePath:(id)arg1;
    - (id)syncGlobalCapabilitiesToChatEngine;
    - (id)syncGlobalProviderSelectionToChatEngineApplyingProviderSource:(id)arg1 thirdPartyEndpoint:(id)arg2 thirdPartyModel:(id)arg3 reasoningEffort:(id)arg4 officialModel:(id)arg5 officialEffort:(id)arg6;
    - (id)syncSelectionToActiveRecord;
    - (id)textViewDidChangeSelection:(id)arg1;
    - (id)thirdPartyReasoningLabel:(id)arg1;
    - (id)updateBlockReferenceForMessage:(id)arg1;
    - (id)updateComposerContextGlowForPercent:(id)arg1;
    - (id)updateComposerMentionMenuState;
    - (id)updateComposerSlashMenuState;
    - (id)updateExecutionModeUIAnimated:(id)arg1;
    - (id)updateGitBadgePolling;
    - (id)updateStreamDisplayLinkRate:(id)arg1 force:(id)arg2;
    - (id)validQueuedAttachments:(id)arg1;
    - (id)verifiedThirdPartyReasoningEffortsForEngine:(id)arg1;
    - (id)verifyPermanentThreadDeletion:(id)arg1 allowRetryDelete:(id)arg2 completion:(id)arg3;
    - (id)workspaceHandoffContextForRecord:(id)arg1;
    - (id)workspaceHasRunningConversation:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
