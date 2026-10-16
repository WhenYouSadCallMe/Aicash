//
//  CACodexEngine.h — codex CLI 引擎（config 覆盖、app-server、exec、login、命令流式输出）
//

#import <Foundation/Foundation.h>
#import "CAAppServerSession.h"

// ==PARITY-FORWARD-DECLS-BEGIN==
@class CAMessageItem;
// ==PARITY-FORWARD-DECLS-END==


NS_ASSUME_NONNULL_BEGIN

typedef void (^CACodexTurnOutputHandler)(NSString *line, BOOL isStderr);
typedef void (^CACodexTurnCompletion)(NSInteger exitStatus, NSString * _Nullable errorMessage);

@interface CACodexEngine : NSObject <CAAppServerSessionDelegate>

@property (nonatomic, copy, nullable) NSString *apiKey;
@property (nonatomic, assign) BOOL useThirdPartyProvider;
@property (nonatomic, copy, nullable) NSString *thirdPartyProviderName;
@property (nonatomic, assign) BOOL persistsProviderPreferences;
@property (nonatomic, copy, nullable) NSString *sandboxMode;
@property (nonatomic, assign) BOOL isLoggedIn;
@property (nonatomic, copy, nullable) NSString *loginStatusText;
@property (nonatomic, strong, nullable) NSTask *loginTask;
@property (nonatomic, copy, nullable) NSString *lastReportedExecutionError;
@property (nonatomic, copy, nullable) NSString *mcpCatalogThreadId;

@property (nonatomic, strong, readonly) CAAppServerSession *persistentAppServer;
@property (nonatomic, strong, readonly) NSMutableSet<CAAppServerSession *> *retiringAppServers;

+ (instancetype)sharedEngine;

#pragma mark - 工具

- (nullable NSString *)resolveCodexExecutable;
- (NSString *)codexLogDirectory;
- (NSString *)thirdPartyModelCatalogPath;
- (NSDictionary<NSString *, NSString *> *)environmentForCodexInvocation;
- (NSArray<NSString *> *)configOverridesWithBaseURL:(nullable NSString *)baseURL
                                              model:(nullable NSString *)model
                                        catalogPath:(nullable NSString *)catalogPath
                                      contextWindow:(NSUInteger)contextWindow
                                             logDir:(nullable NSString *)logDir
                                 developerInstructions:(nullable NSString *)instructions;

#pragma mark - 会话（app-server）

- (void)preparePersistentAppServerWithCompletion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion
                          preserveCatalogSession:(BOOL)preserve;
- (void)ensureMCPCatalogThreadWithCompletion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;
- (void)invalidatePersistentServerWithReason:(NSString *)reason;
- (void)reloadMCPConfigurationWithCompletion:(nullable void (^)(BOOL ok))completion;
- (void)readConnectedMCPServerStatusesForNames:(NSArray<NSString *> *)names
                                    completion:(void (^)(NSDictionary<NSString *, NSNumber *> *statuses))completion;

#pragma mark - 执行（exec --json / app-server turn）

- (void)startExecWithPrompt:(NSString *)prompt
                  workspace:(NSString *)workspace
                      model:(nullable NSString *)model
             executionMode:(nullable NSString *)executionMode
                   sandbox:(nullable NSString *)sandbox
                  output:(CACodexTurnOutputHandler)output
              completion:(CACodexTurnCompletion)completion;

- (void)sendPromptViaPersistentAppServer:(NSString *)prompt
                                threadId:(nullable NSString *)threadId
                              completion:(CACodexTurnCompletion)completion;

#pragma mark - 登录

- (void)checkLoginStatusWithCompletion:(void (^)(BOOL loggedIn, NSString *_Nullable status))completion;
- (void)loginWithAPIKey:(NSString *)apiKey completion:(void (^)(BOOL ok, NSString *_Nullable message))completion;
- (void)loginWithAccessToken:(NSString *)token completion:(void (^)(BOOL ok, NSString *_Nullable message))completion;
- (void)startDeviceLoginWithCodeHandler:(void (^)(NSString *code))codeHandler
                             completion:(void (^)(BOOL ok, NSString *_Nullable message))completion;
- (void)startBrowserOAuthLoginWithUrlHandler:(void (^)(NSURL *url))urlHandler
                                  completion:(void (^)(BOOL ok, NSString *_Nullable message))completion;
- (void)logoutWithCompletion:(void (^)(BOOL ok))completion;

#pragma mark - provider 密钥 / 目录

- (BOOL)saveThirdPartyAPIKey:(NSString *)key error:(NSError **)error;
- (BOOL)hasThirdPartyAPIKey;
- (NSString *)thirdPartyAPIKeyForInternalUse;
- (BOOL)writeCatalogForModels:(NSArray<NSDictionary *> *)models
                selectedModel:(nullable NSString *)slug
                contextWindow:(NSUInteger)contextWindow
                        error:(NSError **)error;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSMutableDictionary * activityCardsById;
    @property (nonatomic, strong, nullable) NSMutableDictionary * activityItemAliases;
    @property (nonatomic, strong, nullable) NSMutableDictionary * activityItemMetadataById;
    @property (nonatomic, strong, nullable) NSString * activityProbeRequestID;
    @property (nonatomic, strong, nullable) NSString * activityProbeScheduleID;
    @property (nonatomic, strong, nullable) CAAppServerSession * activityProbeUnsupportedServer;
    @property (nonatomic, strong, nullable) NSString * apiBaseURL;
    @property (nonatomic, strong, nullable) NSString * appServerAnnouncedExecutionID;
    @property (nonatomic, strong, nullable) NSString * appServerEnvironmentExecutionID;
    @property (nonatomic, strong, nullable) NSString * appServerExecutionID;
    @property (nonatomic, strong, nullable) NSMutableDictionary * appServerMessageBuffers;
    @property (nonatomic, strong, nullable) NSMutableSet * appServerQueuedSpawnItemIds;
    @property (nonatomic, strong, nullable) NSMutableDictionary * appServerReasoningBuffers;
    @property (nonatomic, strong, nullable) NSMutableArray * appServerShutdownWaiters;
    @property (nonatomic, strong, nullable) NSString * codexHomePath;
    @property (nonatomic, strong, nullable) NSString * compactionItemId;
    @property (nonatomic, strong, nullable) NSMutableSet * completedActivityItemIds;
    @property (nonatomic, strong, nullable) NSString * confirmedCollaborationSettingsSignature;
    @property (nonatomic, strong, nullable) NSString * contextReadID;
    @property (nonatomic, assign) BOOL contextUsageIsEstimated;
    @property (nonatomic, assign) long long contextUsagePercent;
    @property (nonatomic, strong, nullable) NSString * currentConversationId;
    @property (nonatomic, strong, nullable) NSString * currentExecID;
    @property (nonatomic, strong, nullable) NSString * currentWorkspacePath;
    @property (nonatomic, strong, nullable) NSMutableSet * deliveredImageItemIds;
    @property (nonatomic, assign) BOOL enableWebSearch;
    @property (nonatomic, assign) BOOL enableWorktree;
    @property (nonatomic, assign) BOOL execReceivedAgentMessage;
    @property (nonatomic, strong, nullable) NSString * execUsageSummary;
    @property (nonatomic, strong, nullable) NSMutableDictionary * fileChangeSnapshotsById;
    @property (nonatomic, assign) BOOL forcingExecFallback;
    @property (nonatomic, assign) BOOL hasStableCacheHitPercent;
    @property (nonatomic, assign) BOOL isRunning;
    @property (nonatomic, strong, nullable) NSDate * lastActivityProbeAt;
    @property (nonatomic, strong, nullable) NSString * lastExecutionError;
    @property (nonatomic, assign) double lastParentActivityEventAt;
    @property (nonatomic, assign) int lastSubagentCardUpdateTime;
    @property (nonatomic, strong, nullable) NSString * latestSubagentWaitItemId;
    @property (nonatomic, strong, nullable) NSMutableData * lineBuffer;
    @property (nonatomic, assign) unsigned long long nextSubagentOrdinal;
    @property (nonatomic, strong, nullable) NSMutableSet * observedSubagentWaitItemIds;
    @property (nonatomic, strong, nullable) NSString * pendingCollaborationSettingsMode;
    @property (nonatomic, strong, nullable) NSString * pendingCollaborationSettingsPolicy;
    @property (nonatomic, strong, nullable) NSString * pendingCollaborationSettingsSignature;
    @property (nonatomic, strong, nullable) NSString * persistentAppServerSignature;
    @property (nonatomic, strong, nullable) NSString * reasoningEffort;
    @property (nonatomic, strong, nullable) NSString * sessionGeneration;
    @property (nonatomic, assign) BOOL shellEventProbeCommandCompleted;
    @property (nonatomic, assign) BOOL shellEventProbeCommandStarted;
    @property (nonatomic, strong, nullable) NSString * shellEventProbeCommandStatus;
    @property (nonatomic, strong, nullable) NSString * shellEventProbeCompletedError;
    @property (nonatomic, strong, nullable) NSString * shellEventProbeCompletedOutput;
    @property (nonatomic, assign) unsigned long long shellEventProbeCompletedOutputChars;
    @property (nonatomic, copy, nullable) id shellEventProbeCompletion;
    @property (nonatomic, strong, nullable) NSNumber * shellEventProbeExitCode;
    @property (nonatomic, strong, nullable) NSString * shellEventProbeItemId;
    @property (nonatomic, strong, nullable) NSMutableString * shellEventProbeOutput;
    @property (nonatomic, assign) BOOL shellEventProbeOutputDeltaReceived;
    @property (nonatomic, assign) BOOL shellEventProbeRPCAcknowledged;
    @property (nonatomic, assign) double stableCacheHitPercent;
    @property (nonatomic, assign) double subagentIntentStartedAt;
    @property (nonatomic, assign) BOOL subagentRequestedByPrompt;
    @property (nonatomic, strong, nullable) CAMessageItem * thinkingActivityCard;
    @property (nonatomic, strong, nullable) NSArray * thirdPartyAvailableModels;
    @property (nonatomic, strong, nullable) NSString * thirdPartyModel;
    @property (nonatomic, strong, nullable) NSString * thirdPartyReasoningEffort;
    @property (nonatomic, assign) unsigned long long totalInputTokens;
    @property (nonatomic, assign) unsigned long long totalOutputTokens;
    @property (nonatomic, assign) unsigned long long totalReasoningTokens;
    @property (nonatomic, strong, nullable) NSDictionary * usageAccountingState;
    @property (nonatomic, assign) BOOL usePersistentAppServerChat;
// ==PARITY-PROPERTIES-END==






// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)isRecoverableTransportNotice:(id)arg1;
    - (id)isTerminalSubagentStatus:(id)arg1;
    - (id)isTrackedActivityType:(id)arg1;
    - (id)isTransientWorkspaceRoutingRetry:(id)arg1;
    - (id)knownSkills;
    - (id)lastKnownTurnUsage;
    - (id)latestCacheWriteInputTokens;
    - (id)latestCachedInputTokens;
    - (id)latestCompletedTurnIdentifier;
    - (id)latestContextTokenCount;
    - (id)latestInputTokens;
    - (id)locateCodexExecutable;
    - (id)markThinkingCardCompletedWithDetail:(id)arg1;
    - (id)mcpCatalogThreadStarting;
    - (id)mcpCatalogThreadWaiters;
    - (id)mergedNormalizedUsage:(id)arg1;
    - (id)mobileDeveloperInstructionArguments;
    - (id)mobileDeveloperInstructions;
    - (id)mutableSubagentMetadataForThreadId:(id)arg1;
    - (id)nativeCollaborationModeForModel:(id)arg1 effort:(id)arg2;
    - (id)normalizedExecItemFromAppServerItem:(id)arg1;
    - (id)normalizedTurnUsage:(id)arg1;
    - (id)parentTurnStartedAt;
    - (id)parseJSONLine:(id)arg1;
    - (id)pendingActivityDiagnosticSummary;
    - (id)pendingCollaborationSettingsThreadId;
    - (id)pendingCollaborationTurnStart;
    - (id)pendingTrackedActivityItemIDs;
    - (id)pendingTransportNotice;
    - (id)persistentAppServerArgumentsWithEnvironment:(id)arg1;
    - (id)persistentAppServerConfigurationSignature;
    - (id)persistentAppServerConfigurationSignatureForEnvironment:(id)arg1;
    - (id)persistentAppServerDiagnosticSnapshot;
    - (id)probeSubagentThreadsAfterCompletedWait;
    - (id)processRawData:(id)arg1;
    - (id)provisionallyAdoptSubagentThreadId:(id)arg1 method:(id)arg2 params:(id)arg3;
    - (id)reasoningSummaryFromItem:(id)arg1;
    - (id)reasoningSummarySuggestsSubagentDelegation:(id)arg1;
    - (id)receivedContextUsageThisTurn;
    - (id)reconcileEarlyOfficialSubagentEvidence;
    - (id)reconcilePendingActivitiesForModelResume:(id)arg1;
    - (id)recoverProvisionalCommandResultsForTurn:(id)arg1;
    - (id)refreshContextUsageForCurrentThread;
    - (id)refreshLatestSubagentWaitCard;
    - (id)refreshOfficialRateLimitsOnMainQueueWithCompletion:(id)arg1;
    - (id)refreshOfficialRateLimitsWithCompletion:(id)arg1;
    - (id)registerSubagentActivityFromParams:(id)arg1;
    - (id)requestActivityStateProbe;
    - (id)requestAppServerMethod:(id)arg1 params:(id)arg2 timeout:(id)arg3 completion:(id)arg4;
    - (id)requestConnectedMCPStatusForName:(id)arg1 threadId:(id)arg2 attempt:(id)arg3 completion:(id)arg4;
    - (id)requestContextMatchesServer:(id)arg1 session:(id)arg2 execution:(id)arg3 conversation:(id)arg4 workspace:(id)arg5;
    - (id)requestSubagentThreadMetadataForThreadId:(id)arg1 attempt:(id)arg2;
    - (id)resetActivityItemTracking;
    - (id)resolvedActivityItemIdForIncomingId:(id)arg1 item:(id)arg2 type:(id)arg3 allowRunningMatch:(id)arg4 reason:(id)arg5;
    - (id)resolvedCodexHomePath;
    - (id)resolvedFileChangePath:(id)arg1;
    - (id)restoreSessionWithThreadId:(id)arg1 workspacePath:(id)arg2;
    - (id)restoreSessionWithThreadId:(id)arg1 workspacePath:(id)arg2 modelSlug:(id)arg3 reasoningEffort:(id)arg4;
    - (id)restoreUsageSnapshot:(id)arg1;
    - (id)setKnownSkills:(id)arg1;
    - (id)setLastKnownTurnUsage:(id)arg1;
    - (id)setLatestCompletedTurnIdentifier:(id)arg1;
    - (id)setLatestContextTokenCount:(id)arg1;
    - (id)setMcpCatalogThreadStarting:(id)arg1;
    - (id)setMcpCatalogThreadWaiters:(id)arg1;
    - (id)setParentTurnStartedAt:(id)arg1;
    - (id)setPendingCollaborationSettingsThreadId:(id)arg1;
    - (id)setPendingCollaborationTurnStart:(id)arg1;
    - (id)setPendingTransportNotice:(id)arg1;
    - (id)setReceivedContextUsageThisTurn:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)activeToolItems;
    - (id)activityCard:(id)arg1 stillBelongsToConversation:(id)arg2 workspace:(id)arg3 session:(id)arg4 itemId:(id)arg5;
    - (id)activityCardForId:(id)arg1 kind:(id)arg2 title:(id)arg3 detail:(id)arg4 running:(id)arg5;
    - (id)activityKindForCommand:(id)arg1;
    - (id)activityMetadata:(id)arg1 matchesItem:(id)arg2 type:(id)arg3 matchedFields:(id)arg4;
    - (id)activityProbeItemDictionary:(id)arg1;
    - (id)activitySnapshotIsTerminal:(id)arg1 type:(id)arg2;
    - (id)adoptSubagentThreadDescriptor:(id)arg1 expectedThreadId:(id)arg2 source:(id)arg3;
    - (id)afterPersistentAppServersStop:(id)arg1;
    - (id)anyEngineRunning;
    - (id)appServerActiveTurnId;
    - (id)appServerAnnouncedItemTypes;
    - (id)appServerInputForPrompt:(id)arg1 attachments:(id)arg2 error:(id)arg3;
    - (id)appServerItemFromNotificationParams:(id)arg1;
    - (id)appServerLoadedThreadIds;
    - (id)appendFileChangeDiff:(id)arg1 toCard:(id)arg2;
    - (id)associateVerifiedSubagentThreadId:(id)arg1 source:(id)arg2;
    - (id)bindConversationId:(id)arg1;
    - (id)buildEnvironment;
    - (id)canSteerActiveTurn;
    - (id)cancelExecution;
    - (id)canonicalActivityItemId:(id)arg1;
    - (id)captureFileChangeSnapshotForId:(id)arg1 changes:(id)arg2;
    - (id)cleanupAllFileChangeSnapshots;
    - (id)cleanupFileChangeSnapshotForId:(id)arg1;
    - (id)collectActivityProbeTurnsFromObject:(id)arg1 turnID:(id)arg2 into:(id)arg3 depth:(id)arg4;
    - (id)collectSnapshotDiffsForPaths:(id)arg1 index:(id)arg2 snapshotFiles:(id)arg3 parts:(id)arg4 completion:(id)arg5;
    - (id)commandRequiresTheosRuntime:(id)arg1;
    - (id)commitStableCacheFromNormalizedUsage:(id)arg1 source:(id)arg2;
    - (id)confirmedCollaborationSettingsThreadId;
    - (id)consumePersistentShellEventProbeNotification:(id)arg1 params:(id)arg2;
    - (id)contextTokenCountFromEvent:(id)arg1;
    - (id)contextWindowLimitTokens;
    - (id)currentTask;
    - (id)currentThreadId;
    - (id)currentUsageSummary;
    - (id)detailedUsageReport;
    - (id)effectiveModelSlug;
    - (id)effectiveReasoningEffort;
    - (id)enrichFileChangeCardFromRepository:(id)arg1 paths:(id)arg2;
    - (id)enrichFileChangeCardWithGitDiff:(id)arg1 itemId:(id)arg2 paths:(id)arg3;
    - (id)ensurePersistentThreadWithCompletion:(id)arg1;
    - (id)execTerminalType;
    - (id)externalizeActivityDetailIfNeeded:(id)arg1 itemId:(id)arg2;
    - (id)fallbackToExecForPrompt:(id)arg1 attachments:(id)arg2 reason:(id)arg3;
    - (id)feedSyntheticExecEvent:(id)arg1;
    - (id)finishActivityCard:(id)arg1 title:(id)arg2 detail:(id)arg3;
    - (id)finishCurrentThinkingWithTitle:(id)arg1 detail:(id)arg2;
    - (id)finishExecWithID:(id)arg1 status:(id)arg2 diagnostics:(id)arg3;
    - (id)finishPendingActivitiesForTerminal:(id)arg1;
    - (id)finishPersistentShellEventProbeTimedOut:(id)arg1 error:(id)arg2;
    - (id)flushThrottledSubagentActivityCardUpdateForThreadId:(id)arg1;
    - (id)handleKnownSubagentNotification:(id)arg1 params:(id)arg2 threadId:(id)arg3;
    - (id)handlePersistentAppServerNotification:(id)arg1 params:(id)arg2;
    - (id)hasCacheWriteInputTokens;
    - (id)hasCachedInputTokens;
    - (id)hasConfirmedCollaborationSettingsForThread:(id)arg1 collaborationMode:(id)arg2 sandboxPolicy:(id)arg3;
    - (id)interruptTrackedSubagentsBeforeParentTurn;
    - (id)invalidatePersistentAppServer:(id)arg1;
    - (id)retireConversationEngine;
    - (id)retireConversationEngineWithCompletion:(id)arg1;
    - (id)reverseToolsEnvironmentIdentityDidChange:(id)arg1;
    - (id)runBundledGitArguments:(id)arg1 completion:(id)arg2;
    - (id)runDoctorWithCompletion:(id)arg1;
    - (id)runPersistentAppServerShellEventProbeWithCompletion:(id)arg1;
    - (id)runPersistentShellEventProbeWithCompletion:(id)arg1;
    - (id)scheduleActivityStateProbe;
    - (id)schedulePostReasoningContinuationFromEventTime:(id)arg1;
    - (id)scheduleThrottledSubagentActivityCardUpdateForThreadId:(id)arg1;
    - (id)sendInterruptForSubagentThread:(id)arg1 turnId:(id)arg2 server:(id)arg3;
    - (id)sendPrompt:(id)arg1 attachments:(id)arg2;
    - (id)setActiveToolItems:(id)arg1;
    - (id)setAppServerActiveTurnId:(id)arg1;
    - (id)setAppServerAnnouncedItemTypes:(id)arg1;
    - (id)setAppServerLoadedThreadIds:(id)arg1;
    - (id)setConfirmedCollaborationSettingsThreadId:(id)arg1;
    - (id)setContextWindowLimitTokens:(id)arg1;
    - (id)setCurrentTask:(id)arg1;
    - (id)setCurrentThreadId:(id)arg1;
    - (id)setExecTerminalType:(id)arg1;
    - (id)setShellEventProbeThreadId:(id)arg1;
    - (id)setShellEventProbeToken:(id)arg1;
    - (id)setShellEventProbeTurnStarted:(id)arg1;
    - (id)setSubagentCardThrottleTimer:(id)arg1;
    - (id)setSubagentMetadataByThreadId:(id)arg1;
    - (id)setThirdPartyAPIKey:(id)arg1;
    - (id)setThirdPartyContextWindowTokens:(id)arg1;
    - (id)setUsageTurnModel:(id)arg1;
    - (id)setUsageTurnProvider:(id)arg1;
    - (id)shellEventProbeThreadId;
    - (id)shellEventProbeToken;
    - (id)shellEventProbeTurnStarted;
    - (id)skillInputsForText:(id)arg1;
    - (id)startCodeReview;
    - (id)startThinkingActivityWithTitle:(id)arg1 detail:(id)arg2;
    - (id)steerPrompt:(id)arg1 attachments:(id)arg2 completion:(id)arg3;
    - (id)stopIdleAppServersForStorageMaintenanceWithCompletion:(id)arg1;
    - (id)subagentCardThrottleTimer;
    - (id)subagentConfiguration;
    - (id)subagentLabelForMetadata:(id)arg1;
    - (id)subagentMetadataBelongsToCurrentConversation:(id)arg1;
    - (id)subagentMetadataByThreadId;
    - (id)subagentProgressLineForMethod:(id)arg1 params:(id)arg2;
    - (id)subagentStatusSnapshots;
    - (id)subagentUsageSnapshots;
    - (id)theosRuntimeIdentityDidChange:(id)arg1;
    - (id)thinkingTitleForReasoningSummary:(id)arg1;
    - (id)thirdPartyContextWindowTokens;
    - (id)uniqueRunningActivityItemIdMatchingItem:(id)arg1 type:(id)arg2 reason:(id)arg3;
    - (id)updateActivityCard:(id)arg1;
    - (id)updateContextFromEvent:(id)arg1;
    - (id)updateSubagentActivityCardForThreadId:(id)arg1;
    - (id)usageTurnModel;
    - (id)usageTurnProvider;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
