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
    return ok;
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
        if ([record.conversationId isEqualToString:conversationId]) return record;
    }
    return nil;
}

- (NSUInteger)conversationCountForWorkspace:(NSString *)workspace
{
    return [self loadRecordsForWorkspace:workspace].count;
}

@end
