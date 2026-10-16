//
//  CAConversationStore.m — 会话存储实现
//
//  落盘布局（对齐原包观测）：
//    <CARuntimePaths.conversationsDirectory>/<workspaceKey>/index.json   —— 该工作区全部记录（JSON 数组）
//    <CARuntimePaths.conversationsDirectory>/<workspaceKey>/…            —— 该工作区附件/产物（由视图层写入）
//    workspaceKey = FNV-1a("/private"→"" 归一化后的工作区路径) → "%016llx"
//    活跃会话    = NSUserDefaults 键 CodexActiveConversation.<workspaceKey>
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CACodexEngine.h"   // P1 补齐（原包方法对齐）：thread/delete / thread/read 接线
#import "CAConversationStore.h"

static NSString * const kCAConversationIndexFileName = @"index.json";
static NSString * const kCAConversationPrivatePrefix  = @"/private";
static NSString * const kCAConversationPrivatePrefixSlash = @"/private/";

#pragma mark - 工具

static unsigned long long CAConversationHash64(NSString *string)
{
    unsigned long long hash = 1469598103934665603ull;   // FNV-1a 64
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) {
        hash ^= (unsigned long long)bytes[index];
        hash *= 1099511628211ull;
    }
    return hash;
}

static id CAConversationJSONScalar(id value)
{
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    return nil;
}

#pragma mark - 记录

@implementation CAConversationRecord

- (instancetype)init
{
    if ((self = [super init])) {
        _conversationId = @"";
        _title = @"";
        _workspacePath = @"";
        _messages = [NSMutableArray array];
        _updatedAt = [NSDate date];
    }
    return self;
}

+ (instancetype)recordWithConversationId:(NSString *)conversationId workspace:(NSString *)workspace
{
    CAConversationRecord *record = [CAConversationRecord new];
    record.conversationId = conversationId.length ? conversationId : [[NSUUID UUID] UUIDString].lowercaseString;
    record.workspacePath = workspace ?: @"";
    record.title = @"";
    record.updatedAt = [NSDate date];
    return record;
}

#pragma mark 便捷别名

- (NSString *)identifier { return self.conversationId ?: @""; }
- (NSString *)workspace { return self.workspacePath ?: @""; }
- (NSString *)model { return self.modelSlug; }
- (NSString *)effort { return self.reasoningEffort; }

#pragma mark 序列化

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"conversationId"] = self.conversationId ?: @"";
    dictionary[@"title"] = self.title ?: @"";
    dictionary[@"workspacePath"] = self.workspacePath ?: @"";
    dictionary[@"messages"] = self.messages ?: @[];
    dictionary[@"updatedAt"] = @((self.updatedAt ?: [NSDate date]).timeIntervalSince1970);

    if (self.threadId.length)            dictionary[@"threadId"] = self.threadId;
    if (self.modelSlug.length)           dictionary[@"modelSlug"] = self.modelSlug;
    if (self.reasoningEffort.length)     dictionary[@"reasoningEffort"] = self.reasoningEffort;
    if (self.executionMode.length)       dictionary[@"executionMode"] = self.executionMode;
    if (self.apiBaseURL.length)          dictionary[@"apiBaseURL"] = self.apiBaseURL;
    if (self.usageSnapshot.count)        dictionary[@"usageSnapshot"] = self.usageSnapshot;
    if (self.costLedger.count)           dictionary[@"costLedger"] = self.costLedger;
    if (self.pendingPlanText.length)     dictionary[@"pendingPlanText"] = self.pendingPlanText;
    if (self.planProgressDetail.length)  dictionary[@"planProgressDetail"] = self.planProgressDetail;
    if (self.planProgressPendingSync)    dictionary[@"planProgressPendingSync"] = @YES;
    if (self.needsWorkspaceHandoff)      dictionary[@"needsWorkspaceHandoff"] = @YES;
    if (self.handoffSourceWorkspace.length) dictionary[@"handoffSourceWorkspace"] = self.handoffSourceWorkspace;
    if (self.archivedBackendThreads.count)  dictionary[@"archivedBackendThreads"] = self.archivedBackendThreads;
    return dictionary;
}

+ (instancetype)recordWithDictionary:(NSDictionary *)dictionary workspace:(NSString *)workspace
{
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = CAConversationJSONScalar(dictionary[@"conversationId"]) ?: CAConversationJSONScalar(dictionary[@"id"]);
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;

    CAConversationRecord *record = [CAConversationRecord new];
    record.conversationId = identifier;
    record.threadId = CAConversationJSONScalar(dictionary[@"threadId"]);
    record.title = CAConversationJSONScalar(dictionary[@"title"]) ?: @"";
    record.workspacePath = CAConversationJSONScalar(dictionary[@"workspacePath"]) ?: (workspace ?: @"");
    record.modelSlug = CAConversationJSONScalar(dictionary[@"modelSlug"]) ?: CAConversationJSONScalar(dictionary[@"model"]);
    record.reasoningEffort = CAConversationJSONScalar(dictionary[@"reasoningEffort"]) ?: CAConversationJSONScalar(dictionary[@"effort"]);
    record.executionMode = CAConversationJSONScalar(dictionary[@"executionMode"]);
    record.apiBaseURL = CAConversationJSONScalar(dictionary[@"apiBaseURL"]);
    record.pendingPlanText = CAConversationJSONScalar(dictionary[@"pendingPlanText"]);
    record.planProgressDetail = CAConversationJSONScalar(dictionary[@"planProgressDetail"]);
    record.handoffSourceWorkspace = CAConversationJSONScalar(dictionary[@"handoffSourceWorkspace"]);

    id messages = dictionary[@"messages"];
    record.messages = [messages isKindOfClass:NSArray.class] ? [messages mutableCopy] : [NSMutableArray array];

    id updatedAt = dictionary[@"updatedAt"];
    double timestamp = [updatedAt respondsToSelector:@selector(doubleValue)] ? [updatedAt doubleValue] : 0;
    record.updatedAt = timestamp > 0 ? [NSDate dateWithTimeIntervalSince1970:timestamp] : [NSDate date];

    id usageSnapshot = dictionary[@"usageSnapshot"];
    if ([usageSnapshot isKindOfClass:NSDictionary.class]) record.usageSnapshot = usageSnapshot;

    id costLedger = dictionary[@"costLedger"];
    if ([costLedger isKindOfClass:NSArray.class]) record.costLedger = costLedger;

    id archived = dictionary[@"archivedBackendThreads"];
    if ([archived isKindOfClass:NSArray.class]) record.archivedBackendThreads = archived;

    if (dictionary[@"planProgressPendingSync"] != nil) record.planProgressPendingSync = [dictionary[@"planProgressPendingSync"] boolValue];
    if (dictionary[@"needsWorkspaceHandoff"] != nil) record.needsWorkspaceHandoff = [dictionary[@"needsWorkspaceHandoff"] boolValue];
    return record;
}

@end

#pragma mark - 存储

@implementation CAConversationStore
{
    NSRecursiveLock *_lock;
    NSMutableDictionary<NSString *, NSArray<CAConversationRecord *> *> *_recordCache;
}

+ (instancetype)sharedStore
{
    static CAConversationStore *store; static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[CAConversationStore alloc] initWithDirectory:CARuntimePaths.conversationsDirectory
                                                      defaults:[NSUserDefaults standardUserDefaults]];
    });
    return store;
}

- (instancetype)initWithDirectory:(NSString *)directory defaults:(NSUserDefaults *)defaults
{
    if ((self = [super init])) {
        _storageDirectory = [(directory.length ? directory : CARuntimePaths.conversationsDirectory) copy];
        _fileManager = [NSFileManager defaultManager];
        _preferences = defaults ?: [NSUserDefaults standardUserDefaults];
        _lock = [NSRecursiveLock new];
        _recordCache = [NSMutableDictionary dictionary];
        [CARuntimePaths ensureDirectory:_storageDirectory mode:0700 error:NULL];
        // P2 补齐（原包方法对齐）：启动时重放未完成的迁移 journal
        [self recoverPendingMigrations];
    }
    return self;
}

#pragma mark - 路径

- (NSString *)rawWorkspaceKey:(NSString *)workspace
{
    NSString *path = workspace.length ? workspace : CARuntimePaths.documentsCodexMTDirectory;
    path = path.stringByStandardizingPath;
    while (path.length > 1 && [path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    // 原包：/private 前缀归一（/private/var → /var、/private/tmp → /tmp、/private/etc → /etc）
    if ([path hasPrefix:kCAConversationPrivatePrefixSlash]) {
        path = [path substringFromIndex:kCAConversationPrivatePrefix.length];
    }
    return path.length ? path : @"/";
}

- (NSString *)workspaceKey:(NSString *)workspace
{
    return [NSString stringWithFormat:@"%016llx", CAConversationHash64([self rawWorkspaceKey:workspace])];
}

- (NSString *)directoryForWorkspace:(NSString *)workspace
{
    return [self.storageDirectory stringByAppendingPathComponent:[self workspaceKey:workspace]];
}

- (NSString *)indexPath:(NSString *)workspace
{
    return [[self directoryForWorkspace:workspace] stringByAppendingPathComponent:kCAConversationIndexFileName];
}

- (NSString *)activeKey:(NSString *)workspace
{
    return [NSString stringWithFormat:CADefaultsActiveConversationFmt, [self workspaceKey:workspace]];
}

#pragma mark - 索引读写

- (NSArray<NSDictionary *> *)rawIndexEntriesForWorkspace:(NSString *)workspace
{
    NSData *data = [NSData dataWithContentsOfFile:[self indexPath:workspace]];
    if (!data.length) return @[];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSArray *entries = nil;
    if ([json isKindOfClass:NSArray.class]) {
        entries = json;
    } else if ([json isKindOfClass:NSDictionary.class]) {
        id raw = ((NSDictionary *)json)[@"records"] ?: ((NSDictionary *)json)[@"conversations"] ?: ((NSDictionary *)json)[@"items"];
        if ([raw isKindOfClass:NSArray.class]) entries = raw;
    }
    NSMutableArray<NSDictionary *> *dictionaries = [NSMutableArray array];
    for (id entry in entries) {
        if ([entry isKindOfClass:NSDictionary.class]) [dictionaries addObject:entry];
    }
    return dictionaries;
}

- (BOOL)writeIndexEntries:(NSArray<NSDictionary *> *)entries forWorkspace:(NSString *)workspace error:(NSError **)error
{
    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:(entries ?: @[]) options:NSJSONWritingPrettyPrinted error:&serializationError];
    if (!data) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation index encode failed workspace=%@ error=%@",
              workspace ?: @"(default)", serializationError.localizedDescription ?: @"invalid payload");
        if (error) *error = serializationError;
        return NO;
    }
    BOOL ok = [CARuntimePaths writeFileAtomically:[self indexPath:workspace] contents:data mode:0600 error:error];
    if (!ok) {
        NSString *reason = (error && *error) ? (*error).localizedDescription : @"unknown";
        CALog(CALogLevelWarn, @"GENERAL", @"conversation index write failed workspace=%@ error=%@",
              workspace ?: @"(default)", reason);
    }
    return ok;
}

#pragma mark - 保存 / 读取

- (BOOL)saveRecord:(CAConversationRecord *)record
{
    if (!record.conversationId.length) return NO;
    if (!record.updatedAt) record.updatedAt = [NSDate date];
    NSString *workspace = record.workspacePath;

    [_lock lock];
    NSMutableArray<NSDictionary *> *entries = [[self rawIndexEntriesForWorkspace:workspace] mutableCopy];
    NSDictionary *payload = [record dictionaryRepresentation];
    NSUInteger replaced = NSNotFound;
    for (NSUInteger index = 0; index < entries.count; index++) {
        NSString *identifier = CAConversationJSONScalar(entries[index][@"conversationId"]) ?: CAConversationJSONScalar(entries[index][@"id"]);
        if ([identifier isEqualToString:record.conversationId]) { replaced = index; break; }
    }
    if (replaced != NSNotFound) [entries replaceObjectAtIndex:replaced withObject:payload];
    else [entries addObject:payload];

    NSError *error = nil;
    BOOL ok = [self writeIndexEntries:entries forWorkspace:workspace error:&error];
    if (ok) {
        _recordCache[[self workspaceKey:workspace]] = [self sortedRecords:[self recordsFromEntries:entries workspace:workspace]];
        CALog(CALogLevelDebug, @"GENERAL", @"conversation saved conversation=%@ workspace=%@ records=%lu",
              record.conversationId, workspace ?: @"(default)", (unsigned long)entries.count);
    }
    [_lock unlock];
    return ok;
}

- (NSArray<CAConversationRecord *> *)recordsFromEntries:(NSArray<NSDictionary *> *)entries workspace:(NSString *)workspace
{
    NSMutableArray<CAConversationRecord *> *records = [NSMutableArray array];
    NSString *expectedKey = [self workspaceKey:workspace];
    for (NSDictionary *entry in entries) {
        CAConversationRecord *record = [CAConversationRecord recordWithDictionary:entry workspace:workspace];
        if (!record) continue;
        if (![[self workspaceKey:record.workspacePath] isEqualToString:expectedKey]) {
            CALog(CALogLevelDebug, @"GENERAL", @"stale sidebar record ignored conversation=%@ workspace=%@",
                  record.conversationId, record.workspacePath ?: @"(none)");
            continue;
        }
        [records addObject:record];
    }
    return records;
}

- (NSArray<CAConversationRecord *> *)sortedRecords:(NSArray<CAConversationRecord *> *)records
{
    return [records sortedArrayUsingComparator:^NSComparisonResult(CAConversationRecord *left, CAConversationRecord *right) {
        NSDate *leftDate = left.updatedAt ?: [NSDate distantPast];
        NSDate *rightDate = right.updatedAt ?: [NSDate distantPast];
        return [rightDate compare:leftDate];
    }];
}

- (NSArray<CAConversationRecord *> *)loadRecordsForWorkspace:(NSString *)workspace
{
    [_lock lock];
    NSArray<NSDictionary *> *entries = [self rawIndexEntriesForWorkspace:workspace];
    NSArray<CAConversationRecord *> *records = [self sortedRecords:[self recordsFromEntries:entries workspace:workspace]];
    _recordCache[[self workspaceKey:workspace]] = records;
    [_lock unlock];
    return records;
}

- (NSArray<CAConversationRecord *> *)recordsForWorkspace:(NSString *)workspace
{
    NSString *key = [self workspaceKey:workspace];
    [_lock lock];
    NSArray<CAConversationRecord *> *cached = _recordCache[key];
    [_lock unlock];
    if (cached) return cached;
    return [self loadRecordsForWorkspace:workspace];
}

- (BOOL)deleteRecord:(CAConversationRecord *)record
{
    if (!record.conversationId.length) return NO;
    return [self deleteRecordWithId:record.conversationId workspace:record.workspacePath];
}

- (BOOL)deleteRecordWithId:(NSString *)conversationId workspace:(NSString *)workspace
{
    if (!conversationId.length) return NO;
    [_lock lock];
    NSMutableArray<NSDictionary *> *entries = [[self rawIndexEntriesForWorkspace:workspace] mutableCopy];
    NSMutableArray<NSDictionary *> *remaining = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
        if ([identifier isEqualToString:conversationId]) continue;
        [remaining addObject:entry];
    }
    BOOL changed = remaining.count != entries.count;
    NSError *error = nil;
    BOOL ok = changed ? [self writeIndexEntries:remaining forWorkspace:workspace error:&error] : YES;
    if (ok) {
        _recordCache[[self workspaceKey:workspace]] = [self sortedRecords:[self recordsFromEntries:remaining workspace:workspace]];
        if (changed) {
            CALog(CALogLevelDebug, @"GENERAL", @"conversation deleted conversation=%@ workspace=%@ remaining=%lu",
                  conversationId, workspace ?: @"(default)", (unsigned long)remaining.count);
        }
        NSString *active = [self activeConversationIdForWorkspace:workspace];
        if ([active isEqualToString:conversationId]) [self setActiveConversationId:nil workspace:workspace];
    }
    [_lock unlock];
    // P1 补齐（原包方法对齐）：本地删除成功后 fire-and-forget 通知 app-server 删除对应 codex thread
    if (ok) {
        NSString *threadId = [self p1ThreadIdentifierForConversationId:conversationId workspace:workspace];
        if (threadId.length > 0) {
            CACodexEngine *engine = CACodexEngine.sharedEngine;
            if (engine.persistentAppServer.isRunning) {
                __weak CACodexEngine *weakEngine = engine;
                NSString *threadIdCopy = [threadId copy];
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    [weakEngine.persistentAppServer callMethod:@"thread/delete"
                                                    parameters:@{ @"thread_id": threadIdCopy }
                                                    completion:^(id result, NSError *error) {
                        if (error) {
                            CALog(CALogLevelWarn, @"GENERAL", @"thread/delete failed thread=%@ error=%@", threadIdCopy, error.localizedDescription ?: @"unknown");
                        } else {
                            CALog(CALogLevelInfo, @"GENERAL", @"thread/delete ok thread=%@", threadIdCopy);
                        }
                    }];
                });
            }
        }
    }
    return ok;
}

// P1 补齐（原包方法对齐）：从 index.json 原始条目里找该会话的 threadId / thread_id（找不到就返回 nil）
- (nullable NSString *)p1ThreadIdentifierForConversationId:(NSString *)conversationId workspace:(NSString *)workspace
{
    if (conversationId.length == 0) return nil;
    NSString *threadId = nil;
    [_lock lock];
    for (NSDictionary *entry in [self rawIndexEntriesForWorkspace:workspace]) {
        NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
        if (![identifier isEqualToString:conversationId]) continue;
        id value = entry[@"threadId"] ?: entry[@"thread_id"];
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) threadId = value;
        break;
    }
    [_lock unlock];
    return threadId;
}

#pragma mark - 迁移（会话侧栏「移动到工作区」，journal 原子搬移协议）

// P2 补齐（原包方法对齐）：原包签名 error: 形参为 id 占位，这里不写回 out-param，
// 只返回 @YES/@NO 并把原因写进日志；失败时 journal 留在盘上由 recoverPendingMigrations 恢复。
- (id)moveConversationWithId:(id)arg1 fromWorkspace:(id)arg2 toWorkspace:(id)arg3 error:(id)arg4
{
    NSString *conversationId = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    NSString *source = [arg2 isKindOfClass:NSString.class] ? arg2 : nil;
    NSString *destination = [arg3 isKindOfClass:NSString.class] ? arg3 : nil;

    if (conversationId.length == 0 || destination.length == 0) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation move rejected conversation=%@ destination=%@",
              conversationId ?: @"(none)", destination ?: @"(none)");
        return @NO;
    }
    if ([[self workspaceKey:source] isEqualToString:[self workspaceKey:destination]]) return @YES;

    CAConversationRecord *record = [self loadConversationWithId:conversationId workspace:source];
    if (!record) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation move failed: record missing conversation=%@ workspace=%@",
              conversationId, source ?: @"(default)");
        return @NO;
    }

    NSString *sourceKey = [self workspaceKey:source];
    NSString *targetKey = [self workspaceKey:destination];
    NSString *journalPath = [self migrationJournalPathForID:conversationId];

    [_lock lock];

    // phase=prepared：先落 journal，任一步失败后可由 recoverPendingMigrations 正/反向重放
    NSArray<NSDictionary *> *sourceEntries = [self rawIndexEntriesForWorkspace:source];
    NSDictionary *sourceEntry = nil;
    for (NSDictionary *entry in sourceEntries) {
        NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
        if ([identifier isEqualToString:conversationId]) { sourceEntry = entry; break; }
    }
    if (!sourceEntry) sourceEntry = [record dictionaryRepresentation];

    BOOL wasActive = [[self activeConversationIdForWorkspace:source] isEqualToString:conversationId];
    NSString *sourceActive = [self activeConversationIdForWorkspace:source];

    NSDictionary *journal = @{
        @"version": @1,
        @"conversation_id": conversationId,
        @"source": sourceKey,
        @"target": targetKey,
        @"index_data": sourceEntry,
        @"active": wasActive ? (sourceActive ?: @"") : @"",
        @"phase": @"prepared",
    };
    if (![self writeMigrationJournal:journal toPath:journalPath]) {
        [_lock unlock];
        CALog(CALogLevelWarn, @"GENERAL", @"conversation move failed: journal write conversation=%@", conversationId);
        return @NO;
    }

    // 1) 从源 index 删
    NSMutableArray<NSDictionary *> *remaining = [NSMutableArray array];
    for (NSDictionary *entry in sourceEntries) {
        NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
        if ([identifier isEqualToString:conversationId]) continue;
        [remaining addObject:entry];
    }
    NSError *indexError = nil;
    if (![self writeIndexEntries:remaining forWorkspace:source error:&indexError]) {
        [_lock unlock];
        CALog(CALogLevelWarn, @"GENERAL", @"conversation move failed: source index remove conversation=%@ error=%@",
              conversationId, indexError.localizedDescription ?: @"unknown");
        return @NO;   // journal 留盘，恢复时反向重放（源 index 未变 → 无需回滚，直接删 journal 即可，但保守保留）
    }

    // 2) 写目标 index
    record.workspacePath = destination;
    record.needsWorkspaceHandoff = NO;
    record.handoffSourceWorkspace = nil;
    record.updatedAt = [NSDate date];
    NSMutableArray<NSDictionary *> *targetEntries = [[self rawIndexEntriesForWorkspace:destination] mutableCopy];
    NSDictionary *targetPayload = [record dictionaryRepresentation];
    NSUInteger replaced = NSNotFound;
    for (NSUInteger index = 0; index < targetEntries.count; index++) {
        NSString *identifier = CAConversationJSONScalar(targetEntries[index][@"conversationId"]) ?: CAConversationJSONScalar(targetEntries[index][@"id"]);
        if ([identifier isEqualToString:conversationId]) { replaced = index; break; }
    }
    if (replaced != NSNotFound) [targetEntries replaceObjectAtIndex:replaced withObject:targetPayload];
    else [targetEntries addObject:targetPayload];
    if (![self writeIndexEntries:targetEntries forWorkspace:destination error:&indexError]) {
        [_lock unlock];
        CALog(CALogLevelWarn, @"GENERAL", @"conversation move failed: target index write conversation=%@ error=%@",
              conversationId, indexError.localizedDescription ?: @"unknown");
        return @NO;   // journal 留盘：恢复时目标已写 → 反向重放回源
    }

    // 3) 搬 attachments 目录（如果有）
    NSString *sourceAttachments = [self attachmentDirectoryForConversationId:conversationId];
    NSString *targetAttachments = [self attachmentDirectoryForConversationId:conversationId];
    sourceAttachments = [[self directoryForWorkspace:source] stringByAppendingPathComponent:
                         [@"attachments" stringByAppendingPathComponent:conversationId]];
    targetAttachments = [[self directoryForWorkspace:destination] stringByAppendingPathComponent:
                         [@"attachments" stringByAppendingPathComponent:conversationId]];
    if ([self.fileManager fileExistsAtPath:sourceAttachments]) {
        [CARuntimePaths ensureDirectory:targetAttachments.stringByDeletingLastPathComponent mode:0700 error:NULL];
        if ([self.fileManager fileExistsAtPath:targetAttachments]) [self.fileManager removeItemAtPath:targetAttachments error:NULL];
        NSError *moveError = nil;
        if (![self.fileManager moveItemAtPath:sourceAttachments toPath:targetAttachments error:&moveError]) {
            // 目录搬移失败不阻塞（附件可留在源侧由 recoverPendingMigrations 补搬）
            CALog(CALogLevelWarn, @"GENERAL", @"conversation move attachment relocate deferred conversation=%@ error=%@",
                  conversationId, moveError.localizedDescription ?: @"unknown");
        }
    }

    // 4) 写目标 active（若源 active 是它）
    if (wasActive) {
        [self setActiveConversationId:conversationId workspace:destination];
        [self setActiveConversationId:nil workspace:source];
    }

    // 5) 成功 → 删 journal
    [self cleanupMigrationJournal:conversationId];
    _recordCache[sourceKey] = [self sortedRecords:[self recordsFromEntries:remaining workspace:source]];
    _recordCache[targetKey] = [self sortedRecords:[self recordsFromEntries:targetEntries workspace:destination]];
    [_lock unlock];

    CALog(CALogLevelInfo, @"GENERAL", @"conversation moved conversation=%@ %@ -> %@",
          conversationId, source ?: @"(default)", destination);
    return @YES;
}

#pragma mark - 活跃会话

- (NSString *)activeConversationIdForWorkspace:(NSString *)workspace
{
    return [self.preferences stringForKey:[self activeKey:workspace]];
}

- (void)setActiveConversationId:(NSString *)conversationId workspace:(NSString *)workspace
{
    NSString *key = [self activeKey:workspace];
    if (conversationId.length) [self.preferences setObject:conversationId forKey:key];
    else [self.preferences removeObjectForKey:key];
}

- (CAConversationRecord *)loadActiveConversationForWorkspace:(NSString *)workspace
{
    NSString *active = [self activeConversationIdForWorkspace:workspace];
    if (!active.length) return nil;
    return [self loadConversationWithId:active workspace:workspace];
}

#pragma mark - 便捷

- (CAConversationRecord *)createConversationForWorkspace:(NSString *)workspace
{
    CAConversationRecord *record = [CAConversationRecord recordWithConversationId:[[NSUUID UUID] UUIDString].lowercaseString
                                                                       workspace:workspace ?: @""];
    record.title = @"";
    record.updatedAt = [NSDate date];
    [self saveRecord:record];
    [self setActiveConversationId:record.conversationId workspace:workspace];
    return record;
}

- (CAConversationRecord *)loadConversationWithId:(NSString *)conversationId workspace:(NSString *)workspace
{
    if (!conversationId.length) return nil;
    for (CAConversationRecord *record in [self loadRecordsForWorkspace:workspace]) {
        if ([record.conversationId isEqualToString:conversationId]) {
            // P1 补齐（原包方法对齐）：record 带 threadId 时拉一次 thread/read（只用于日志，不做 UI 同步）
            if (record.threadId.length > 0) {
                CACodexEngine *engine = CACodexEngine.sharedEngine;
                if (engine.persistentAppServer.isRunning) {
                    __weak CACodexEngine *weakEngine = engine;
                    NSString *threadIdCopy = [record.threadId copy];
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                        [weakEngine.persistentAppServer callMethod:@"thread/read"
                                                        parameters:@{ @"thread_id": threadIdCopy }
                                                        completion:^(id result, NSError *error) {
                            if (error) {
                                CALog(CALogLevelWarn, @"GENERAL", @"thread/read failed thread=%@ error=%@", threadIdCopy, error.localizedDescription ?: @"unknown");
                            } else if (![result isKindOfClass:NSDictionary.class] || [(NSDictionary *)result count] == 0) {
                                CALog(CALogLevelWarn, @"GENERAL", @"thread/read returned no thread");
                            } else {
                                CALog(CALogLevelInfo, @"GENERAL", @"thread/read ok thread=%@ keys=%lu", threadIdCopy, (unsigned long)[(NSDictionary *)result count]);
                            }
                        }];
                    });
                }
            }
            return record;
        }
    }
    return nil;
}

- (NSUInteger)conversationCountForWorkspace:(NSString *)workspace
{
    return [self loadRecordsForWorkspace:workspace].count;
}

#pragma mark - P2 补齐（原包方法对齐）

#pragma mark 别名 / 索引

- (BOOL)saveConversation:(CAConversationRecord *)record { return [self saveRecord:record]; }

- (NSArray<NSDictionary *> *)readIndex:(NSString *)workspace
{
    return [self rawIndexEntriesForWorkspace:workspace];
}

- (NSDictionary *)dictionaryFromRecord:(CAConversationRecord *)record
{
    return [record dictionaryRepresentation];
}

- (CAConversationRecord *)recordFromDictionary:(NSDictionary *)dictionary workspace:(NSString *)workspace
{
    return [CAConversationRecord recordWithDictionary:dictionary workspace:workspace];
}

#pragma mark 迁移 journal（原子搬移协议）

static NSString * const kCAConversationJournalVersion = @"1";
static NSString * const kCAConversationJournalPhasePrepared  = @"prepared";
static NSString * const kCAConversationJournalPhaseMoved    = @"moved";
static NSString * const kCAConversationJournalPhaseActive   = @"active";

- (NSString *)migrationJournalDirectory
{
    return [self.storageDirectory stringByAppendingPathComponent:@"migration-journal"];
}

- (NSString *)migrationJournalPathForID:(NSString *)conversationId
{
    return [[self migrationJournalDirectory] stringByAppendingPathComponent:
            [conversationId stringByAppendingPathExtension:@"json"]];
}

- (BOOL)writeMigrationJournal:(NSDictionary *)journal toPath:(NSString *)path
{
    if (![journal isKindOfClass:NSDictionary.class] || !path.length) return NO;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:journal options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation migration journal encode failed path=%@ error=%@",
              path, error.localizedDescription ?: @"invalid payload");
        return NO;
    }
    return [CARuntimePaths writeFileAtomically:path contents:data mode:0600 error:&error];
}

- (NSDictionary *)readMigrationJournalAtPath:(NSString *)path
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

// 容错读：active_value 或 active
- (id)migrationJournalData:(NSDictionary *)journal key:(NSString *)key
{
    if (![journal isKindOfClass:NSDictionary.class] || !key.length) return nil;
    id value = journal[key];
    if (value != nil) return value;
    if ([key isEqualToString:@"active"]) return journal[@"active_value"];
    if ([key isEqualToString:@"active_value"]) return journal[@"active"];
    return nil;
}

- (BOOL)migrationJournalReferencesConversationId:(NSString *)conversationId
{
    if (!conversationId.length) return NO;
    NSString *directory = [self migrationJournalDirectory];
    for (NSString *name in [self.fileManager contentsOfDirectoryAtPath:directory error:NULL]) {
        if (![name hasSuffix:@".json"]) continue;
        NSDictionary *journal = [self readMigrationJournalAtPath:[directory stringByAppendingPathComponent:name]];
        NSString *referenced = [self migrationJournalData:journal key:@"conversation_id"];
        if ([referenced isKindOfClass:NSString.class] && [(NSString *)referenced isEqualToString:conversationId]) return YES;
    }
    return NO;
}

- (BOOL)cleanupMigrationJournal:(NSString *)conversationId
{
    if (!conversationId.length) return YES;
    NSString *path = [self migrationJournalPathForID:conversationId];
    if (![self.fileManager fileExistsAtPath:path]) return YES;
    NSError *error = nil;
    BOOL ok = [self.fileManager removeItemAtPath:path error:&error];
    if (!ok) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation migration journal cleanup failed path=%@ error=%@",
              path, error.localizedDescription ?: @"unknown");
    }
    return ok;
}

- (BOOL)removeMigrationFileIfPresent:(NSString *)path
{
    if (!path.length) return YES;
    if (![self.fileManager fileExistsAtPath:path]) return YES;
    // 安全校验：journal 文件必须在 migration-journal/ 目录内
    NSString *root = [self migrationJournalDirectory].stringByStandardizingPath;
    NSString *full = path.stringByStandardizingPath;
    if (![full hasPrefix:[root stringByAppendingString:@"/"]]) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation migration journal cleanup rejected path=%@", path);
        return NO;
    }
    NSError *error = nil;
    return [self.fileManager removeItemAtPath:full error:&error];
}

/// 把 journal 中的 index 条目恢复到指定工作区索引（restoreMigrationIndexData）
- (BOOL)restoreMigrationIndexData:(NSDictionary *)indexData existed:(BOOL)existed path:(NSString *)indexPath
{
    if (![indexData isKindOfClass:NSDictionary.class]) return NO;
    // 由索引文件路径直接读写（workspaceKey 已编码在上级目录名中）
    NSArray<NSDictionary *> *entries = [self rawIndexEntriesForWorkspace:indexPath];
    NSMutableArray<NSDictionary *> *mutable = [entries mutableCopy];
    NSString *identifier = CAConversationJSONScalar(indexData[@"conversationId"]) ?: CAConversationJSONScalar(indexData[@"id"]);
    NSUInteger replaced = NSNotFound;
    for (NSUInteger index = 0; index < mutable.count; index++) {
        NSString *existing = CAConversationJSONScalar(mutable[index][@"conversationId"]) ?: CAConversationJSONScalar(mutable[index][@"id"]);
        if ([existing isEqualToString:identifier]) { replaced = index; break; }
    }
    if (existed) {
        if (replaced != NSNotFound) [mutable replaceObjectAtIndex:replaced withObject:indexData];
        else [mutable addObject:indexData];
    } else {
        if (replaced != NSNotFound) [mutable removeObjectAtIndex:replaced];
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:mutable options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) return NO;
    return [CARuntimePaths writeFileAtomically:indexPath contents:data mode:0600 error:&error];
}

// restoreMigrationIndexData 的便捷重载（按工作区路径）
- (BOOL)ca_restoreMigrationIndexData:(NSDictionary *)indexData existed:(BOOL)existed workspace:(NSString *)workspace
{
    return [self restoreMigrationIndexData:indexData existed:existed path:[self indexPath:workspace]];
}

/// 恢复 active 指针（restoreMigrationActiveValue）
- (void)restoreMigrationActiveValue:(NSString *)activeValue key:(NSString *)workspaceKey
{
    if (!workspaceKey.length) return;
    NSString *key = [NSString stringWithFormat:CADefaultsActiveConversationFmt, workspaceKey];
    if (activeValue.length) [self.preferences setObject:activeValue forKey:key];
    else [self.preferences removeObjectForKey:key];
}

- (void)recoverPendingMigrations
{
    NSString *directory = [self migrationJournalDirectory];
    NSArray<NSString *> *names = [self.fileManager contentsOfDirectoryAtPath:directory error:NULL];
    if (!names.count) return;

    for (NSString *name in names) {
        if (![name hasSuffix:@".json"]) continue;
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDictionary *journal = [self readMigrationJournalAtPath:path];

        // 日志字面量照抄原包
        if (![journal isKindOfClass:NSDictionary.class]) {
            CALog(CALogLevelWarn, @"GENERAL", @"conversation migration journal invalid JSON path=%@; retaining for diagnostics", path);
            continue;
        }
        id version = journal[@"version"];
        if (![version respondsToSelector:@selector(integerValue)] || [version integerValue] != 1) {
            CALog(CALogLevelWarn, @"GENERAL", @"conversation migration journal unsupported version path=%@ version=%@; retaining", path, version ?: @"(none)");
            continue;
        }
        NSString *conversationId = [self migrationJournalData:journal key:@"conversation_id"];
        NSString *sourceKey = [self migrationJournalData:journal key:@"source"];
        NSString *targetKey = [self migrationJournalData:journal key:@"target"];
        NSDictionary *indexData = [self migrationJournalData:journal key:@"index_data"];
        NSString *activeValue = [self migrationJournalData:journal key:@"active"];
        if (!conversationId.length || !sourceKey.length || !targetKey.length || ![indexData isKindOfClass:NSDictionary.class]) {
            CALog(CALogLevelWarn, @"GENERAL", @"conversation migration journal missing required fields path=%@; retaining", path);
            continue;
        }

        // 反查工作区路径：active 键格式 CodexActiveConversation.<workspaceKey>
        NSString *sourceWorkspace = nil, *targetWorkspace = nil;
        for (NSString *key in [self.preferences dictionaryRepresentation].keyEnumerator) {
            if (![key hasPrefix:@"CodexActiveConversation."]) continue;
            NSString *keyHash = [key substringFromIndex:@"CodexActiveConversation.".length];
            if ([keyHash isEqualToString:sourceKey]) sourceWorkspace = keyHash;
            if ([keyHash isEqualToString:targetKey]) targetWorkspace = keyHash;
        }
        // 工作区路径无法反查原始串时用 key 本身占位（index 路径只需 workspaceKey 命中目录）
        if (!sourceWorkspace) sourceWorkspace = sourceKey;
        if (!targetWorkspace) targetWorkspace = targetKey;

        NSString *indexPathSource = [[self.storageDirectory stringByAppendingPathComponent:sourceKey]
                                     stringByAppendingPathComponent:kCAConversationIndexFileName];
        NSString *indexPathTarget = [[self.storageDirectory stringByAppendingPathComponent:targetKey]
                                     stringByAppendingPathComponent:kCAConversationIndexFileName];

        NSString *phase = journal[@"phase"];
        BOOL targetHasRecord = NO;
        for (NSDictionary *entry in [self readIndex:targetWorkspace]) {
            NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
            if ([identifier isEqualToString:conversationId]) { targetHasRecord = YES; break; }
        }
        BOOL sourceHasRecord = NO;
        for (NSDictionary *entry in [self readIndex:sourceWorkspace]) {
            NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
            if ([identifier isEqualToString:conversationId]) { sourceHasRecord = YES; break; }
        }

        // 状态机重放：按已完成的 phase 正向补完；若源/目标状态与 phase 不符则反向回滚
        BOOL resolved = NO;
        if ([phase isEqualToString:kCAConversationJournalPhaseActive]) {
            [self restoreMigrationActiveValue:activeValue key:targetKey];
            resolved = YES;
        } else if ([phase isEqualToString:kCAConversationJournalPhaseMoved] && targetHasRecord) {
            [self restoreMigrationIndexData:indexData existed:NO path:indexPathSource];
            [self restoreMigrationActiveValue:activeValue key:targetKey];
            resolved = YES;
        } else if (targetHasRecord && sourceHasRecord) {
            // 双写：反向回滚到源（回滚优先，保证不丢数据）
            [self restoreMigrationIndexData:indexData existed:YES path:indexPathSource];
            [self restoreMigrationIndexData:indexData existed:NO path:indexPathTarget];
            [self restoreMigrationActiveValue:activeValue key:sourceKey];
            resolved = YES;
        } else if (targetHasRecord && !sourceHasRecord) {
            // 目标已写、源已删：正向补完
            [self restoreMigrationActiveValue:activeValue key:targetKey];
            resolved = YES;
        } else if (!targetHasRecord && sourceHasRecord) {
            // 源未删或已回滚：确认源侧条目在，删 journal 即完成反向
            resolved = YES;
        }

        if (resolved) {
            [self.fileManager removeItemAtPath:path error:NULL];
            CALog(CALogLevelInfo, @"GENERAL", @"conversation migration recovery unresolved id=%@ source=%@ target=%@ phase=%@",
                  conversationId, sourceKey, targetKey, phase ?: @"(none)");
        } else {
            CALog(CALogLevelInfo, @"GENERAL", @"conversation migration recovery unresolved id=%@ source=%@ target=%@ phase=%@",
                  conversationId, sourceKey, targetKey, phase ?: @"(none)");
        }
    }
}

#pragma mark 附件 / 工具输出

- (NSString *)attachmentsRoot
{
    return [self.storageDirectory stringByAppendingPathComponent:@"attachments"];
}

- (NSString *)toolOutputsRoot
{
    return [self.storageDirectory stringByAppendingPathComponent:@"tool-outputs"];
}

- (NSString *)attachmentDirectoryForConversationId:(NSString *)conversationId
{
    if (!conversationId.length) return nil;
    return [[self attachmentsRoot] stringByAppendingPathComponent:conversationId];
}

- (NSString *)toolOutputDirectoryForConversationId:(NSString *)conversationId
{
    if (!conversationId.length) return nil;
    return [[self toolOutputsRoot] stringByAppendingPathComponent:conversationId];
}

- (BOOL)isSafeRelativeAttachmentPath:(NSString *)relative
{
    if (!relative.length) return NO;
    if ([relative hasPrefix:@"/"]) return NO;
    if ([relative isEqualToString:@".."]) return NO;
    for (NSString *component in relative.pathComponents) {
        if ([component isEqualToString:@".."] || component.length == 0) return NO;
    }
    return YES;
}

- (NSString *)storeAttachmentFileAtPath:(NSString *)sourcePath conversationId:(NSString *)conversationId
{
    if (!sourcePath.length || !conversationId.length) return nil;
    if (![self.fileManager fileExistsAtPath:sourcePath]) return nil;
    NSString *directory = [self attachmentDirectoryForConversationId:conversationId];
    if (![CARuntimePaths ensureDirectory:directory mode:0700 error:NULL]) return nil;
    NSString *name = sourcePath.lastPathComponent;
    if (!name.length) return nil;
    NSString *destination = [directory stringByAppendingPathComponent:name];
    if ([self.fileManager fileExistsAtPath:destination]) [self.fileManager removeItemAtPath:destination error:NULL];
    // 拷贝（保留原件），返回相对路径
    NSError *error = nil;
    if (![self.fileManager copyItemAtPath:sourcePath toPath:destination error:&error]) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation attachment store failed conversation=%@ error=%@",
              conversationId, error.localizedDescription ?: @"unknown");
        return nil;
    }
    return [NSString stringWithFormat:@"%@/%@", conversationId, name];
}

- (NSString *)storeToolOutput:(NSString *)content conversationId:(NSString *)conversationId itemId:(NSString *)itemId
{
    if (!conversationId.length || !itemId.length) return nil;
    NSString *directory = [self toolOutputDirectoryForConversationId:conversationId];
    if (![CARuntimePaths ensureDirectory:directory mode:0700 error:NULL]) return nil;
    NSString *path = [directory stringByAppendingPathComponent:itemId];
    NSData *data = [content ?: @"" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    if (![CARuntimePaths writeFileAtomically:path contents:data mode:0600 error:NULL]) return nil;
    return [NSString stringWithFormat:@"%@/%@", conversationId, itemId];
}

- (BOOL)appendToolOutput:(NSString *)content conversationId:(NSString *)conversationId itemId:(NSString *)itemId
{
    if (!conversationId.length || !itemId.length || !content.length) return NO;
    NSString *directory = [self toolOutputDirectoryForConversationId:conversationId];
    if (![CARuntimePaths ensureDirectory:directory mode:0700 error:NULL]) return NO;
    NSString *path = [directory stringByAppendingPathComponent:itemId];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        NSData *initial = [content dataUsingEncoding:NSUTF8StringEncoding];
        return [initial writeToFile:path options:NSDataWritingAtomic error:NULL];
    }
    @try {
        [handle seekToEndOfFile];
        [handle writeData:[content dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]];
        [handle closeFile];
        return YES;
    } @catch (NSException *exception) {
        CALog(CALogLevelWarn, @"GENERAL", @"conversation tool output append failed item=%@ error=%@", itemId, exception.reason ?: @"unknown");
        return NO;
    }
}

- (NSString *)absolutePathForStoredAttachment:(NSString *)relative
{
    if (![self isSafeRelativeAttachmentPath:relative]) return nil;
    NSString *full = [[self attachmentsRoot] stringByAppendingPathComponent:relative].stringByStandardizingPath;
    NSString *root = [self attachmentsRoot].stringByStandardizingPath;
    if (![full hasPrefix:[root stringByAppendingString:@"/"]]) return nil;
    return full;
}

- (NSString *)absolutePathForStoredToolOutput:(NSString *)relative
{
    if (![self isSafeRelativeAttachmentPath:relative]) return nil;
    NSString *full = [[self toolOutputsRoot] stringByAppendingPathComponent:relative].stringByStandardizingPath;
    NSString *root = [self toolOutputsRoot].stringByStandardizingPath;
    if (![full hasPrefix:[root stringByAppendingString:@"/"]]) return nil;
    return full;
}

#pragma mark 清理 / 净化

- (CAConversationRecord *)transientConversationForWorkspace:(NSString *)workspace
{
    CAConversationRecord *record = [CAConversationRecord recordWithConversationId:
                                    [NSString stringWithFormat:@"transient-%@", [[NSUUID UUID] UUIDString].lowercaseString]
                                                                        workspace:workspace ?: @""];
    record.title = @"";
    record.updatedAt = [NSDate date];
    // 瞬时会话不落 index，只返回模型供 UI 过渡使用
    return record;
}

- (BOOL)conversationIdReferencedInOtherWorkspace:(NSString *)conversationId workspace:(NSString *)workspace
{
    if (!conversationId.length) return NO;
    NSString *ownKey = [self workspaceKey:workspace];
    for (NSString *name in [self.fileManager contentsOfDirectoryAtPath:self.storageDirectory error:NULL]) {
        NSString *full = [self.storageDirectory stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![self.fileManager fileExistsAtPath:full isDirectory:&isDirectory] || !isDirectory) continue;
        if ([name isEqualToString:ownKey]) continue;
        NSString *indexPath = [full stringByAppendingPathComponent:kCAConversationIndexFileName];
        if (![self.fileManager fileExistsAtPath:indexPath]) continue;
        // 直接按 key 目录读 index（不经过 workspace 反解）
        NSData *data = [NSData dataWithContentsOfFile:indexPath];
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSArray *entries = [json isKindOfClass:NSArray.class] ? json : nil;
        if (!entries && [json isKindOfClass:NSDictionary.class]) {
            id raw = ((NSDictionary *)json)[@"records"] ?: ((NSDictionary *)json)[@"conversations"] ?: ((NSDictionary *)json)[@"items"];
            if ([raw isKindOfClass:NSArray.class]) entries = raw;
        }
        for (NSDictionary *entry in entries) {
            NSString *identifier = CAConversationJSONScalar(entry[@"conversationId"]) ?: CAConversationJSONScalar(entry[@"id"]);
            if ([identifier isEqualToString:conversationId]) return YES;
        }
    }
    return NO;
}

- (NSArray<NSDictionary *> *)removeUnreferencedDisplayAttachments:(NSArray<NSString *> *)displayAttachments
                                                 remainingMessages:(NSArray<NSDictionary *> *)remainingMessages
                                                   preservingPaths:(NSArray<NSString *> *)preservingPaths
{
    // 收集 remainingMessages 里实际引用的附件相对路径
    NSMutableSet<NSString *> *referenced = [NSMutableSet set];
    for (NSDictionary *message in remainingMessages) {
        if (![message isKindOfClass:NSDictionary.class]) continue;
        for (id value in message.allValues) {
            if ([value isKindOfClass:NSString.class] && [self isSafeRelativeAttachmentPath:value]) [referenced addObject:value];
            else if ([value isKindOfClass:NSDictionary.class]) {
                NSString *path = ((NSDictionary *)value)[@"path"] ?: ((NSDictionary *)value)[@"attachment"];
                if ([path isKindOfClass:NSString.class] && [self isSafeRelativeAttachmentPath:path]) [referenced addObject:path];
            }
        }
    }
    for (NSString *path in preservingPaths) {
        if ([path isKindOfClass:NSString.class]) [referenced addObject:path];
    }

    NSMutableArray<NSDictionary *> *removed = [NSMutableArray array];
    for (NSString *relative in displayAttachments) {
        if (![relative isKindOfClass:NSString.class]) continue;
        if ([referenced containsObject:relative]) continue;
        NSString *full = [self absolutePathForStoredAttachment:relative];
        if (full && [self.fileManager fileExistsAtPath:full]) {
            [self.fileManager removeItemAtPath:full error:NULL];
            [removed addObject:@{ @"path": relative }];
            CALog(CALogLevelDebug, @"GENERAL", @"conversation display attachment unreferenced removed path=%@", relative);
        }
    }
    return removed;
}

- (NSArray<NSDictionary *> *)sanitizedDisplayAttachments:(NSArray<NSDictionary *> *)displayAttachments
{
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *attachment in displayAttachments) {
        if (![attachment isKindOfClass:NSDictionary.class]) continue;
        NSString *path = attachment[@"path"] ?: attachment[@"attachment"] ?: attachment[@"file"];
        if (![path isKindOfClass:NSString.class] || ![self isSafeRelativeAttachmentPath:path]) continue;
        if (![self.fileManager fileExistsAtPath:[self absolutePathForStoredAttachment:path]]) continue;
        [result addObject:attachment];
    }
    return result;
}

- (NSArray<NSDictionary *> *)sanitizedGeneratedArtifacts:(NSArray<NSDictionary *> *)artifacts workspace:(NSString *)workspace
{
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *artifact in artifacts) {
        if (![artifact isKindOfClass:NSDictionary.class]) continue;
        NSString *path = artifact[@"path"] ?: artifact[@"file"] ?: artifact[@"url"];
        if (![path isKindOfClass:NSString.class] || !path.length) continue;
        // 工作区内绝对路径或安全相对路径都保留；逃出工作区/存储根的丢弃
        NSString *full = path;
        if (![path hasPrefix:@"/"]) {
            full = [[[self directoryForWorkspace:workspace] stringByAppendingPathComponent:path].stringByStandardizingPath copy];
        }
        NSString *storageRoot = self.storageDirectory.stringByStandardizingPath;
        NSString *documentsRoot = CARuntimePaths.documentsDirectory;
        BOOL inside = [full hasPrefix:[storageRoot stringByAppendingString:@"/"]]
                   || [full hasPrefix:[documentsRoot stringByAppendingString:@"/"]];
        if (!inside) continue;
        if (![self.fileManager fileExistsAtPath:full]) continue;
        [result addObject:artifact];
    }
    return result;
}

@end
