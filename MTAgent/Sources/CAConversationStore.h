//
//  CAConversationStore.h — 会话存储（JSONL / json，按工作区分目录）
//
//  原包符号对齐（SPEC/assets/objc_api_map.json → "CAConversationStore" / "CAConversationRecord"）：
//    +sharedStore / -initWithDirectory:defaults: / -saveConversation: / -conversationsForWorkspace: /
//    -loadConversationWithId:workspace: / -deleteConversationWithId:workspace: / -activeKey: /
//    -loadActiveConversationForWorkspace: / -setActiveConversationId:workspace: / -createConversationForWorkspace: /
//    -conversationCountForWorkspace: / -directoryForWorkspace: / -indexPath: / -dictionaryFromRecord: /
//    -recordFromDictionary:workspace: / -rawWorkspaceKey: / -workspaceKey: / -storageDirectory
//  记录 ivar（原包）：_conversationId _threadId _title _workspacePath _modelSlug _reasoningEffort _messages
//                     _updatedAt _usageSnapshot _costLedger _executionMode _apiBaseURL _pendingPlanText …
//  路径契约：CARuntimePaths.conversationsDirectory（/var/mobile/Library/Application Support/CodexApp/CodexApp/Conversations）
//  活跃会话键：CADefaultsActiveConversationFmt（CodexActiveConversation.%@）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 记录

@interface CAConversationRecord : NSObject

@property (nonatomic, copy) NSString *conversationId;
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *workspacePath;
@property (nonatomic, copy, nullable) NSString *modelSlug;
@property (nonatomic, copy, nullable) NSString *reasoningEffort;
@property (nonatomic, copy, nullable) NSString *executionMode;
@property (nonatomic, copy, nullable) NSString *apiBaseURL;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *messages;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSDictionary *usageSnapshot;
@property (nonatomic, copy, nullable) NSArray *costLedger;
@property (nonatomic, copy, nullable) NSString *pendingPlanText;
@property (nonatomic, copy, nullable) NSString *planProgressDetail;
@property (nonatomic, assign) BOOL planProgressPendingSync;
@property (nonatomic, assign) BOOL needsWorkspaceHandoff;
@property (nonatomic, copy, nullable) NSString *handoffSourceWorkspace;
@property (nonatomic, copy, nullable) NSArray<NSString *> *archivedBackendThreads;

/// 便捷别名（等价于 conversationId / workspacePath / modelSlug / reasoningEffort）
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *workspace;
@property (nonatomic, copy, readonly, nullable) NSString *model;
@property (nonatomic, copy, readonly, nullable) NSString *effort;

+ (instancetype)recordWithConversationId:(NSString *)conversationId workspace:(nullable NSString *)workspace;

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)recordWithDictionary:(NSDictionary *)dictionary workspace:(nullable NSString *)workspace;

@end

#pragma mark - 存储

@interface CAConversationStore : NSObject

@property (nonatomic, copy, readonly) NSString *storageDirectory;
@property (nonatomic, strong, readonly) NSFileManager *fileManager;
@property (nonatomic, strong, readonly) NSUserDefaults *preferences;

+ (instancetype)sharedStore;
- (instancetype)initWithDirectory:(nullable NSString *)directory defaults:(nullable NSUserDefaults *)defaults;

#pragma mark 读写

- (BOOL)saveRecord:(CAConversationRecord *)record;
- (NSArray<CAConversationRecord *> *)loadRecordsForWorkspace:(nullable NSString *)workspace;
- (NSArray<CAConversationRecord *> *)recordsForWorkspace:(nullable NSString *)workspace;
- (BOOL)deleteRecord:(CAConversationRecord *)record;
- (BOOL)deleteRecordWithId:(NSString *)conversationId workspace:(nullable NSString *)workspace;

#pragma mark 活跃会话

- (nullable NSString *)activeConversationIdForWorkspace:(nullable NSString *)workspace;
- (void)setActiveConversationId:(nullable NSString *)conversationId workspace:(nullable NSString *)workspace;
- (nullable CAConversationRecord *)loadActiveConversationForWorkspace:(nullable NSString *)workspace;

#pragma mark 便捷

- (CAConversationRecord *)createConversationForWorkspace:(nullable NSString *)workspace;
- (nullable CAConversationRecord *)loadConversationWithId:(NSString *)conversationId workspace:(nullable NSString *)workspace;
- (NSUInteger)conversationCountForWorkspace:(nullable NSString *)workspace;

#pragma mark 路径

- (NSString *)directoryForWorkspace:(nullable NSString *)workspace;
- (NSString *)indexPath:(nullable NSString *)workspace;
- (NSString *)workspaceKey:(nullable NSString *)workspace;
- (NSString *)rawWorkspaceKey:(nullable NSString *)workspace;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSMutableDictionary * resolvedWorkspaceKeys;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)absolutePathForStoredAttachment:(id)arg1;
    - (id)absolutePathForStoredToolOutput:(id)arg1;
    - (id)appendToolOutput:(id)arg1 conversationId:(id)arg2 itemId:(id)arg3;
    - (id)attachmentDirectoryForConversationId:(id)arg1;
    - (id)attachmentsRoot;
    - (id)cleanupMigrationJournal:(id)arg1;
    - (id)conversationIdReferencedInOtherWorkspace:(id)arg1 workspace:(id)arg2;
    - (id)isSafeRelativeAttachmentPath:(id)arg1;
    - (id)migrationJournalData:(id)arg1 key:(id)arg2;
    - (id)migrationJournalDirectory;
    - (id)migrationJournalPathForID:(id)arg1;
    - (id)migrationJournalReferencesConversationId:(id)arg1;
    - (id)moveConversationWithId:(id)arg1 fromWorkspace:(id)arg2 toWorkspace:(id)arg3 error:(id)arg4;
    - (id)readIndex:(id)arg1;
    - (id)recoverPendingMigrations;
    - (id)removeMigrationFileIfPresent:(id)arg1;
    - (id)removeUnreferencedDisplayAttachments:(id)arg1 remainingMessages:(id)arg2 preservingPaths:(id)arg3;
    - (id)restoreMigrationActiveValue:(id)arg1 key:(id)arg2;
    - (id)restoreMigrationIndexData:(id)arg1 existed:(id)arg2 path:(id)arg3;
    - (id)sanitizedDisplayAttachments:(id)arg1;
    - (id)sanitizedGeneratedArtifacts:(id)arg1 workspace:(id)arg2;
    - (id)storeAttachmentFileAtPath:(id)arg1 conversationId:(id)arg2;
    - (id)storeToolOutput:(id)arg1 conversationId:(id)arg2 itemId:(id)arg3;
    - (id)toolOutputDirectoryForConversationId:(id)arg1;
    - (id)toolOutputsRoot;
    - (id)transientConversationForWorkspace:(id)arg1;
    - (id)writeMigrationJournal:(id)arg1 toPath:(id)arg2;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
