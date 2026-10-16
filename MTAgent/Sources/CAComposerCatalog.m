//
//  CAComposerCatalog.m — 输入框目录扫描 / 缓存 / 开关
//
//  扫描位置（原包契约 contracts.json files + strings_full.txt）：
//    技能：~/.codex/skills、~/.codex/skills/.system、<workspace>/.codex/skills、<workspace>/.agents/skills、
//          $CODEXAPP_MANAGED_SKILLS_PATH（SKILL.md / skill.md，front matter 可选）
//    插件：~/.codex/plugins、~/.plugins、<workspace>/.agents/plugins、<workspace>/.codex/plugins、
//          .agents/plugins/marketplace.json、plugin.json
//    MCP ：config.toml 的 [mcp_servers.NAME] / [mcp_servers."NAME"] / mcp_servers.NAME.enabled（纯文本解析）
//    提示：~/.codex/prompts/*.md
//    记忆：AGENTS.md、AGENTS.override.md、~/.codex/memories
//  缓存：CARuntimePaths.composerCatalogCacheDirectory（每工作区一个 <hash16>.json）
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CALogger.h"
#import "CAComposerCatalog.h"
#import "CACodexEngine.h"

NSNotificationName const CAComposerCatalogDidChangeNotification = @"CAComposerCatalogDidChangeNotification";

static NSString * const kCASkillManifestName      = @"SKILL.md";
static NSString * const kCASkillManifestNameLower = @"skill.md";
static NSString * const kCAPluginManifestName     = @"plugin.json";
static NSString * const kCAMarketplaceName        = @"marketplace.json";
static NSString * const kCAConfigTOMLLeafName     = @"config.toml";
static NSString * const kCASkillStateFileName     = @"skill-state.json";
static NSString * const kCALegacySnapshotName     = @"composer-catalog.json";
static NSString * const kCASystemSkillDirectory   = @".system";

static const NSUInteger kCASummaryCharacterLimit = 280;
static const NSUInteger kCACatalogCacheTTL       = 10 * 60;   // 10 分钟以内视为新鲜

typedef void (^CAComposerCatalogCompletion)(NSError *_Nullable error);
typedef void (^CAComposerCatalogActionCompletion)(BOOL ok, NSError *_Nullable error);

#pragma mark - 小工具

static unsigned long long CAComposerHash64(NSString *string)
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

static NSString *CAComposerTrim(NSString *string)
{
    return [(string ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *CAComposerUnquote(NSString *string)
{
    NSString *trimmed = CAComposerTrim(string);
    if (trimmed.length >= 2) {
        NSString *first = [trimmed substringToIndex:1];
        NSString *last = [trimmed substringFromIndex:trimmed.length - 1];
        BOOL doubleQuoted = [first isEqualToString:@"\""] && [last isEqualToString:@"\""];
        BOOL singleQuoted = [first isEqualToString:@"'"] && [last isEqualToString:@"'"];
        if (doubleQuoted || singleQuoted) {
            return [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
        }
    }
    return trimmed;
}

static NSString *CAComposerTruncate(NSString *string, NSUInteger limit)
{
    NSString *trimmed = CAComposerTrim(string);
    if (trimmed.length <= limit) return trimmed;
    return [[trimmed substringToIndex:limit] stringByAppendingString:@"…"];
}

static NSArray<NSString *> *CAComposerLines(NSString *text)
{
    return [(text ?: @"") componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

static NSString *CAComposerFirstMatch(NSString *pattern, NSString *text, NSUInteger group)
{
    if (!text.length) return nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match || match.numberOfRanges <= group) return nil;
    NSRange range = [match rangeAtIndex:group];
    if (range.location == NSNotFound) return nil;
    return [text substringWithRange:range];
}

#pragma mark - 条目

@implementation CAComposerCatalogItem

- (instancetype)init
{
    if ((self = [super init])) {
        _kind = CAComposerCatalogKindUnknown;
        _identifier = @"";
        _name = @"";
        _title = @"";
        _summary = @"";
        _scope = @"";
        _path = @"";
        _body = @"";
        _detail = @"";
        _enabled = YES;
        _installed = YES;
    }
    return self;
}

+ (instancetype)itemWithKind:(CAComposerCatalogKind)kind identifier:(NSString *)identifier
{
    CAComposerCatalogItem *item = [CAComposerCatalogItem new];
    item.kind = kind;
    item.identifier = identifier ?: @"";
    return item;
}

+ (NSString *)kindNameForKind:(CAComposerCatalogKind)kind
{
    switch (kind) {
        case CAComposerCatalogKindSkill:  return @"skill";
        case CAComposerCatalogKindPlugin: return @"plugin";
        case CAComposerCatalogKindMCP:    return @"mcp";
        case CAComposerCatalogKindPrompt: return @"prompt";
        case CAComposerCatalogKindMemory: return @"memory";
        default:                          return @"unknown";
    }
}

+ (CAComposerCatalogKind)kindForName:(NSString *)name
{
    NSString *normalized = name.lowercaseString;
    if ([normalized isEqualToString:@"skill"] || [normalized isEqualToString:@"skills"]) return CAComposerCatalogKindSkill;
    if ([normalized isEqualToString:@"plugin"] || [normalized isEqualToString:@"plugins"]) return CAComposerCatalogKindPlugin;
    if ([normalized isEqualToString:@"mcp"] || [normalized isEqualToString:@"server"]) return CAComposerCatalogKindMCP;
    if ([normalized isEqualToString:@"prompt"] || [normalized isEqualToString:@"prompts"]) return CAComposerCatalogKindPrompt;
    if ([normalized isEqualToString:@"memory"] || [normalized isEqualToString:@"memories"]) return CAComposerCatalogKindMemory;
    return CAComposerCatalogKindUnknown;
}

- (NSString *)kindName
{
    return [CAComposerCatalogItem kindNameForKind:self.kind];
}

- (NSString *)displayTitle
{
    if (self.title.length) return self.title;
    if (self.name.length) return self.name;
    return self.identifier ?: @"";
}

- (NSDictionary *)dictionaryRepresentation
{
    return @{
        @"kind": self.kindName,
        @"identifier": self.identifier ?: @"",
        @"name": self.name ?: @"",
        @"title": self.title ?: @"",
        @"summary": self.summary ?: @"",
        @"scope": self.scope ?: @"",
        @"path": self.path ?: @"",
        @"body": self.body ?: @"",
        @"detail": self.detail ?: @"",
        @"enabled": @(self.enabled),
        @"installed": @(self.installed),
    };
}

+ (instancetype)itemWithDictionary:(NSDictionary *)dictionary
{
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = dictionary[@"identifier"];
    if (!identifier.length) return nil;
    CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:[self kindForName:dictionary[@"kind"]] identifier:identifier];
    item.name = dictionary[@"name"] ?: item.name;
    item.title = dictionary[@"title"] ?: item.title;
    item.summary = dictionary[@"summary"] ?: item.summary;
    item.scope = dictionary[@"scope"] ?: item.scope;
    item.path = dictionary[@"path"] ?: item.path;
    item.body = dictionary[@"body"] ?: item.body;
    item.detail = dictionary[@"detail"] ?: item.detail;
    if (dictionary[@"enabled"] != nil) item.enabled = [dictionary[@"enabled"] boolValue];
    if (dictionary[@"installed"] != nil) item.installed = [dictionary[@"installed"] boolValue];
    return item;
}

@end

#pragma mark - 目录

@interface CAComposerCatalog ()

@property (nonatomic, copy, readwrite) NSArray<CAComposerCatalogItem *> *items;
@property (nonatomic, copy, readwrite, nullable) NSString *workspacePath;
@property (nonatomic, assign, readwrite) BOOL loading;
@property (nonatomic, strong, readwrite, nullable) NSDate *loadedAt;
@property (nonatomic, copy, readwrite, nullable) NSString *lastError;
@property (nonatomic, copy, readwrite, nullable) NSString *lastMCPError;
@property (nonatomic, copy, readwrite, nullable) NSString *lastPluginError;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *skillState;

@end

@implementation CAComposerCatalog
{
    dispatch_queue_t _queue;
    dispatch_queue_t _ioQueue;
    NSMutableArray<CAComposerCatalogCompletion> *_waiters;
}

+ (instancetype)sharedCatalog
{
    static CAComposerCatalog *catalog; static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [CAComposerCatalog new]; });
    return catalog;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _items = @[];
        _loading = NO;
        _generation = 0;
        _waiters = [NSMutableArray array];
        _skillState = [[[self class] loadSkillState] mutableCopy] ?: [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("app.codex.composercatalog", DISPATCH_QUEUE_SERIAL);
        _ioQueue = dispatch_queue_create("app.codex.composercatalog.io", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - 基础解析

+ (NSString *)defaultWorkspacePath
{
    NSString *envWorkspace = NSProcessInfo.processInfo.environment[CAEnvWorkspacePath];
    if (envWorkspace.length) return envWorkspace;
    return CARuntimePaths.documentsCodexMTDirectory;
}

+ (NSString *)resolvedHome
{
    return CARuntimePaths.codexHome;
}

+ (NSString *)textAtPath:(NSString *)path
{
    if (!path.length) return @"";
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"";
}

+ (BOOL)isDirectory:(NSString *)path
{
    BOOL isDirectory = NO;
    if (!path.length) return NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) return NO;
    return isDirectory;
}

+ (NSArray<NSString *> *)sortedDirectoryEntries:(NSString *)directory
{
    if (![self isDirectory:directory]) return @[];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL] ?: @[];
    return [entries sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

/// front matter（--- key: value ---）解析；返回元数据并把正文写回 outBody
+ (NSDictionary<NSString *, NSString *> *)metadataFrontMatterFromText:(NSString *)text
                                                          body:(NSString * _Nullable * _Nullable)outBody
{
    NSMutableDictionary<NSString *, NSString *> *metadata = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *lines = [CAComposerLines(text) mutableCopy];
    if (lines.count && [lines.firstObject hasPrefix:@"\uFEFF"]) {
        lines[0] = [lines.firstObject substringFromIndex:1];
    }
    NSUInteger bodyStart = 0;
    if (lines.count && [CAComposerTrim(lines.firstObject) isEqualToString:@"---"]) {
        NSUInteger index = 1;
        for (; index < lines.count; index++) {
            NSString *trimmed = CAComposerTrim(lines[index]);
            if ([trimmed isEqualToString:@"---"]) { index += 1; break; }
            NSRange colon = [lines[index] rangeOfString:@":"];
            if (colon.location == NSNotFound) continue;
            NSString *key = CAComposerTrim([lines[index] substringToIndex:colon.location]).lowercaseString;
            NSString *value = CAComposerUnquote([lines[index] substringFromIndex:colon.location + 1]);
            if (key.length && value.length) metadata[key] = value;
        }
        bodyStart = index;
    }
    if (outBody) {
        NSArray<NSString *> *rest = bodyStart < lines.count ? [lines subarrayWithRange:NSMakeRange(bodyStart, lines.count - bodyStart)] : @[];
        *outBody = [rest componentsJoinedByString:@"\n"];
    }
    return metadata;
}

+ (NSString *)firstHeadingInText:(NSString *)text
{
    for (NSString *line in CAComposerLines(text)) {
        NSString *trimmed = CAComposerTrim(line);
        if ([trimmed hasPrefix:@"#"]) {
            return CAComposerTrim([trimmed stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#"]]);
        }
    }
    return nil;
}

+ (NSString *)firstParagraphInText:(NSString *)text
{
    for (NSString *line in CAComposerLines(text)) {
        NSString *trimmed = CAComposerTrim(line);
        if (!trimmed.length) continue;
        if ([trimmed hasPrefix:@"#"] || [trimmed hasPrefix:@"---"] || [trimmed hasPrefix:@"```"]) continue;
        return CAComposerTruncate(trimmed, kCASummaryCharacterLimit);
    }
    return nil;
}

#pragma mark - 启用状态（skills/config/write 的本地等价实现）

+ (NSString *)skillStatePath
{
    return [CARuntimePaths.composerCatalogCacheDirectory stringByAppendingPathComponent:kCASkillStateFileName];
}

+ (NSDictionary<NSString *, NSNumber *> *)loadSkillState
{
    NSData *data = [NSData dataWithContentsOfFile:[self skillStatePath]];
    if (!data.length) return @{};
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary<NSString *, NSNumber *> *state = [NSMutableDictionary dictionary];
    [(NSDictionary *)json enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value respondsToSelector:@selector(boolValue)]) {
            state[key] = @([value boolValue]);
        }
    }];
    return state;
}

- (BOOL)persistSkillStateWithError:(NSError **)error
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.skillState ?: @{} options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    return [CARuntimePaths writeFileAtomically:[CAComposerCatalog skillStatePath] contents:data mode:0600 error:error];
}

- (BOOL)enabledStateForSkillIdentifier:(NSString *)identifier
{
    NSNumber *value = self.skillState[identifier];
    return value ? value.boolValue : YES;
}

#pragma mark - 扫描：技能

+ (NSString *)skillManifestPathInDirectory:(NSString *)directory
{
    for (NSString *candidate in @[ kCASkillManifestName, kCASkillManifestNameLower ]) {
        NSString *path = [directory stringByAppendingPathComponent:candidate];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) return path;
    }
    return nil;
}

+ (CAComposerCatalogItem *)skillItemAtManifestPath:(NSString *)manifestPath
                                              name:(NSString *)name
                                             scope:(NSString *)scope
{
    NSString *text = [self textAtPath:manifestPath];
    NSString *body = nil;
    NSDictionary<NSString *, NSString *> *metadata = [self metadataFrontMatterFromText:text body:&body];

    CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindSkill
                                                          identifier:[NSString stringWithFormat:@"skill:%@", name]];
    item.name = name;
    item.title = metadata[@"title"] ?: metadata[@"name"] ?: [self firstHeadingInText:body] ?: name;
    item.summary = metadata[@"description"] ?: metadata[@"summary"] ?: [self firstParagraphInText:body] ?: @"";
    item.scope = scope;
    item.path = manifestPath;
    item.body = body ?: @"";
    item.detail = manifestPath;
    item.installed = YES;
    item.enabled = [[self sharedCatalog] enabledStateForSkillIdentifier:item.identifier];
    return item;
}

+ (NSArray<CAComposerCatalogItem *> *)scanSkillsWithHome:(NSString *)home workspace:(NSString *)workspace
{
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *roots = [NSMutableArray array];
    if (home.length) {
        [roots addObject:@[ [home stringByAppendingPathComponent:@"skills"], @"user" ]];
        [roots addObject:@[ [[home stringByAppendingPathComponent:@"skills"] stringByAppendingPathComponent:kCASystemSkillDirectory], @"system" ]];
    }
    if (workspace.length) {
        [roots addObject:@[ [workspace stringByAppendingPathComponent:@".codex/skills"], @"project" ]];
        [roots addObject:@[ [workspace stringByAppendingPathComponent:@".agents/skills"], @"workspace" ]];
    }
    NSString *managed = NSProcessInfo.processInfo.environment[CAEnvManagedSkillsPath];
    if (managed.length) [roots addObject:@[ managed, @"system" ]];

    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    for (NSArray<NSString *> *root in roots) {
        NSString *directory = root.firstObject;
        NSString *scope = root.lastObject;
        if (![self isDirectory:directory]) continue;
        if ([visited containsObject:directory]) continue;
        [visited addObject:directory];

        for (NSString *entry in [self sortedDirectoryEntries:directory]) {
            if ([entry hasPrefix:@"."]) continue;                       // .system 已单独枚举
            NSString *child = [directory stringByAppendingPathComponent:entry];
            if (![self isDirectory:child]) continue;
            NSString *manifest = [self skillManifestPathInDirectory:child];
            if (!manifest) continue;
            CAComposerCatalogItem *item = [self skillItemAtManifestPath:manifest name:entry scope:scope];
            if (!item) continue;
            [items addObject:item];
            CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"skill provenance name=%@ scope=%@ path=%@ enabled=%d",
                  item.name, item.scope, item.path, (int)(item.enabled ? 1 : 0));
        }
    }
    return [self sortedSkills:items];
}

- (NSArray<CAComposerCatalogItem *> *)scanSkillsWithHome:(NSString *)home workspace:(NSString *)workspace
{
    return [CAComposerCatalog scanSkillsWithHome:home workspace:workspace];
}

+ (NSArray<CAComposerCatalogItem *> *)sortedSkills:(NSArray<CAComposerCatalogItem *> *)items
{
    return [items sortedArrayUsingComparator:^NSComparisonResult(CAComposerCatalogItem *left, CAComposerCatalogItem *right) {
        NSInteger leftKind = (NSInteger)left.kind;
        NSInteger rightKind = (NSInteger)right.kind;
        if (leftKind != rightKind) return leftKind < rightKind ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult scope = [left.scope ?: @"" caseInsensitiveCompare:right.scope ?: @""];
        if (scope != NSOrderedSame) return scope;
        return [left.displayTitle caseInsensitiveCompare:right.displayTitle];
    }];
}

#pragma mark - 扫描：插件

+ (NSArray<CAComposerCatalogItem *> *)pluginItemsFromMarketplacePayload:(id)payload
                                                                   path:(NSString *)path
                                                                  scope:(NSString *)scope
{
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];
    NSArray *entries = nil;
    if ([payload isKindOfClass:NSArray.class]) {
        entries = payload;
    } else if ([payload isKindOfClass:NSDictionary.class]) {
        id plugins = ((NSDictionary *)payload)[@"plugins"];
        if ([plugins isKindOfClass:NSArray.class]) entries = plugins;
        else if ([plugins isKindOfClass:NSDictionary.class]) entries = [(NSDictionary *)plugins allValues];
    }
    for (id entry in entries) {
        NSString *name = nil;
        NSString *title = nil;
        NSString *summary = nil;
        BOOL installed = YES;
        BOOL enabled = YES;
        if ([entry isKindOfClass:NSDictionary.class]) {
            NSDictionary *plugin = entry;
            name = plugin[@"name"] ?: plugin[@"id"] ?: plugin[@"identifier"] ?: plugin[@"slug"];
            title = plugin[@"title"] ?: plugin[@"displayName"] ?: plugin[@"display_name"];
            summary = plugin[@"description"] ?: plugin[@"summary"] ?: plugin[@"shortDescription"];
            if (plugin[@"installed"] != nil) installed = [plugin[@"installed"] boolValue];
            if (plugin[@"enabled"] != nil) enabled = [plugin[@"enabled"] boolValue];
        } else if ([entry isKindOfClass:NSString.class]) {
            name = entry;
        }
        if (!name.length) continue;

        CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindPlugin
                                                              identifier:[NSString stringWithFormat:@"plugin:%@", name]];
        item.name = name;
        item.title = title.length ? title : name;
        item.summary = summary ?: @"";
        item.scope = scope;
        item.path = path;
        item.detail = path;
        item.enabled = enabled;
        item.installed = installed;
        [items addObject:item];
    }
    return items;
}

+ (NSArray<CAComposerCatalogItem *> *)scanLocalPluginsWithHome:(NSString *)home workspace:(NSString *)workspace
{
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *roots = [NSMutableArray array];
    if (home.length) {
        [roots addObject:@[ [home stringByAppendingPathComponent:@"plugins"], @"user" ]];
        [roots addObject:@[ [home stringByAppendingPathComponent:@".codex/plugins"], @"user" ]];
        [roots addObject:@[ [home stringByAppendingPathComponent:@".agents/plugins"], @"user" ]];
    }
    if (workspace.length) {
        [roots addObject:@[ [workspace stringByAppendingPathComponent:@".agents/plugins"], @"workspace" ]];
        [roots addObject:@[ [workspace stringByAppendingPathComponent:@".codex/plugins"], @"project" ]];
    }

    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    for (NSArray<NSString *> *root in roots) {
        NSString *directory = root.firstObject;
        NSString *scope = root.lastObject;
        if (![self isDirectory:directory]) continue;
        if ([visited containsObject:directory]) continue;
        [visited addObject:directory];

        // marketplace.json（.agents/plugins/marketplace.json）
        NSString *marketplacePath = [directory stringByAppendingPathComponent:kCAMarketplaceName];
        if ([NSFileManager.defaultManager fileExistsAtPath:marketplacePath]) {
            NSData *data = [NSData dataWithContentsOfFile:marketplacePath];
            id payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if (payload) {
                [items addObjectsFromArray:[self pluginItemsFromMarketplacePayload:payload path:marketplacePath scope:scope]];
            } else {
                CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"plugin catalog partial/unavailable: %@", marketplacePath);
            }
            [self logPluginMarketplaceResult:payload source:marketplacePath];
        }

        // 本地插件目录（plugin.json）
        for (NSString *entry in [self sortedDirectoryEntries:directory]) {
            if ([entry hasPrefix:@"."]) continue;
            NSString *child = [directory stringByAppendingPathComponent:entry];
            if (![self isDirectory:child]) continue;
            NSString *manifest = [child stringByAppendingPathComponent:kCAPluginManifestName];
            if (![NSFileManager.defaultManager fileExistsAtPath:manifest]) continue;

            NSData *data = [NSData dataWithContentsOfFile:manifest];
            NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSString *name = payload[@"name"] ?: payload[@"id"] ?: entry;
            CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindPlugin
                                                                  identifier:[NSString stringWithFormat:@"plugin-local:%@", name]];
            item.name = name;
            item.title = payload[@"title"] ?: payload[@"displayName"] ?: name;
            item.summary = payload[@"description"] ?: payload[@"summary"] ?: @"";
            item.scope = scope;
            item.path = manifest;
            item.detail = manifest;
            item.enabled = payload[@"enabled"] ? [payload[@"enabled"] boolValue] : YES;
            item.installed = YES;
            [items addObject:item];
        }
    }
    return items;
}

- (NSArray<CAComposerCatalogItem *> *)scanLocalPluginsWithHome:(NSString *)home workspace:(NSString *)workspace
{
    return [CAComposerCatalog scanLocalPluginsWithHome:home workspace:workspace];
}

+ (void)logPluginMarketplaceResult:(id)result source:(NSString *)source
{
    NSArray *plugins = nil;
    NSString *market = source ?: @"local";
    if ([result isKindOfClass:NSArray.class]) {
        plugins = result;
    } else if ([result isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = result;
        id raw = dictionary[@"plugins"] ?: dictionary[@"entries"];
        if ([raw isKindOfClass:NSArray.class]) plugins = raw;
        else if ([raw isKindOfClass:NSDictionary.class]) plugins = [(NSDictionary *)raw allValues];
        market = dictionary[@"marketplace"] ?: dictionary[@"marketplaceId"] ?: market;
    }
    NSUInteger installed = 0;
    NSUInteger enabled = 0;
    NSUInteger total = 0;
    NSMutableArray<NSString *> *installedNames = [NSMutableArray array];
    for (id entry in plugins) {
        total += 1;
        if ([entry isKindOfClass:NSDictionary.class]) {
            NSDictionary *plugin = entry;
            id rawName = plugin[@"name"] ?: plugin[@"id"] ?: plugin[@"slug"];
            NSString *name = [rawName isKindOfClass:NSString.class] ? rawName : nil;
            BOOL isInstalled = plugin[@"installed"] != nil ? [plugin[@"installed"] boolValue] : YES;
            BOOL isEnabled = plugin[@"enabled"] != nil ? [plugin[@"enabled"] boolValue] : YES;
            if (isInstalled) installed += 1;
            if (isEnabled) enabled += 1;
            if (isInstalled && name.length) [installedNames addObject:name];
        }
    }
    CALog(CALogLevelInfo, @"CHAT-PLUGIN",
          @"source=%@ market=%@ count=%lu installed=%lu enabled=%lu missingInstalled=%lu installedNames=%@",
          source ?: @"local", market, (unsigned long)total, (unsigned long)installed, (unsigned long)enabled,
          (unsigned long)(total - installed), [installedNames componentsJoinedByString:@","]);
}

#pragma mark - 扫描：MCP（config.toml 纯文本解析）

+ (NSString *)mcpSectionHeaderNameFromLine:(NSString *)line
{
    NSString *pattern = @"^\\s*\\[\\s*mcp_servers\\.(\"[^\"]+\"|'[^']+'|[A-Za-z0-9_-]+)\\s*\\]\\s*(?:#.*)?$";
    NSString *match = CAComposerFirstMatch(pattern, line ?: @"" , 1);
    if (!match.length) return nil;
    return CAComposerUnquote(match);
}

+ (BOOL)lineIsSubtableOfMCPServer:(NSString *)line name:(NSString *)name
{
    NSString *trimmed = CAComposerTrim(line);
    if (![trimmed hasPrefix:@"["]) return NO;
    NSArray<NSString *> *variants = @[
        [NSString stringWithFormat:@"[mcp_servers.%@.", name ?: @""],
        [NSString stringWithFormat:@"[mcp_servers.\"%@\".", name ?: @""],
        [NSString stringWithFormat:@"[mcp_servers.'%@'.", name ?: @""],
    ];
    for (NSString *variant in variants) {
        if ([trimmed hasPrefix:variant]) return YES;
    }
    return NO;
}

/// -1 表示该行不是 enabled 行；0/1 为解析结果
+ (NSInteger)enabledValueFromLine:(NSString *)line
{
    NSString *pattern = @"^\\s*enabled\\s*=\\s*(true|false)\\s*(?:#.*)?$";
    NSString *match = CAComposerFirstMatch(pattern, line ?: @"", 1);
    if (!match.length) return -1;
    return [match isEqualToString:@"true"] ? 1 : 0;
}

+ (NSString *)mcpCommandDetailFromLines:(NSArray<NSString *> *)lines
{
    NSString *command = nil;
    NSString *url = nil;
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (NSString *line in lines) {
        if (!command.length) {
            NSString *value = CAComposerFirstMatch(@"^\\s*command\\s*=\\s*\"([^\"]*)\"", line, 1);
            if (value.length) command = value;
        }
        if (!url.length) {
            NSString *value = CAComposerFirstMatch(@"^\\s*url\\s*=\\s*\"([^\"]*)\"", line, 1);
            if (value.length) url = value;
        }
        if (arguments.count < 3) {
            NSString *value = CAComposerFirstMatch(@"^\\s*args\\s*=\\s*\\[(.*)\\]\\s*(?:#.*)?$", line, 1);
            if (value.length) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\"([^\"]*)\"|'([^']*)'" options:0 error:NULL];
                for (NSTextCheckingResult *match in [regex matchesInString:value options:0 range:NSMakeRange(0, value.length)]) {
                    for (NSUInteger group = 1; group < match.numberOfRanges; group++) {
                        NSRange range = [match rangeAtIndex:group];
                        if (range.location == NSNotFound) continue;
                        [arguments addObject:[value substringWithRange:range]];
                        break;
                    }
                    if (arguments.count >= 3) break;
                }
            }
        }
    }
    if (url.length) return url;
    if (command.length) {
        if (!arguments.count) return command;
        return [[@[ command ] arrayByAddingObjectsFromArray:arguments] componentsJoinedByString:@" "];
    }
    return nil;
}

+ (NSArray<CAComposerCatalogItem *> *)scanConfiguredMCPWithHome:(NSString *)home
{
    NSString *configPath = [home stringByAppendingPathComponent:kCAConfigTOMLLeafName];
    NSString *text = [self textAtPath:configPath];
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];

    NSMutableDictionary<NSString *, NSMutableDictionary *> *servers = [NSMutableDictionary dictionary];
    NSArray<NSString *> *lines = CAComposerLines(text);

    // 1) [mcp_servers.NAME] 段
    NSUInteger index = 0;
    while (index < lines.count) {
        NSString *name = [self mcpSectionHeaderNameFromLine:lines[index]];
        if (!name.length) { index += 1; continue; }

        NSMutableArray<NSString *> *body = [NSMutableArray array];
        NSUInteger cursor = index + 1;
        for (; cursor < lines.count; cursor++) {
            NSString *line = lines[cursor];
            NSString *trimmed = CAComposerTrim(line);
            if ([trimmed hasPrefix:@"["]) {
                if (![self lineIsSubtableOfMCPServer:line name:name]) break;
            }
            [body addObject:line];
        }
        NSInteger enabled = -1;
        for (NSString *bodyLine in body) {
            NSInteger value = [self enabledValueFromLine:bodyLine];
            if (value >= 0) { enabled = value; break; }
        }
        NSMutableDictionary *record = servers[name] ?: [NSMutableDictionary dictionary];
        record[@"name"] = name;
        record[@"enabled"] = @(enabled >= 0 ? (enabled == 1) : YES);
        record[@"detail"] = [self mcpCommandDetailFromLines:body] ?: kCAConfigTOMLLeafName;
        servers[name] = record;
        index = cursor;
    }

    // 2) mcp_servers.NAME = … / mcp_servers.NAME.enabled = … / mcp_servers."NAME".key = …
    NSString *dottedPattern = @"^\\s*mcp_servers\\.(\"[^\"]+\"|'[^']+'|[A-Za-z0-9_-]+)(?:\\.([A-Za-z0-9_-]+))?\\s*=\\s*(.*)$";
    NSRegularExpression *dotted = [NSRegularExpression regularExpressionWithPattern:dottedPattern options:0 error:NULL];
    for (NSString *line in lines) {
        NSTextCheckingResult *match = [dotted firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!match || match.numberOfRanges < 4) continue;
        NSString *name = CAComposerUnquote([line substringWithRange:[match rangeAtIndex:1]]);
        NSString *key = [match rangeAtIndex:2].location == NSNotFound ? @"" : [line substringWithRange:[match rangeAtIndex:2]];
        NSString *value = CAComposerTrim([line substringWithRange:[match rangeAtIndex:3]]);
        if (!name.length) continue;
        NSMutableDictionary *record = servers[name] ?: [NSMutableDictionary dictionary];
        record[@"name"] = name;
        if (!record[@"detail"] && value.length) record[@"detail"] = CAComposerTruncate(value, 120);
        if (!record[@"enabled"]) record[@"enabled"] = @YES;
        if ([key isEqualToString:@"enabled"]) {
            NSInteger enabled = [self enabledValueFromLine:[NSString stringWithFormat:@"enabled = %@", value]];
            if (enabled >= 0) record[@"enabled"] = @(enabled == 1);
        }
        servers[name] = record;
    }

    for (NSString *name in [servers.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSDictionary *record = servers[name];
        BOOL internal = [self isInternalMCPName:name];
        CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindMCP
                                                              identifier:[NSString stringWithFormat:@"mcp:%@", name]];
        item.name = name;
        item.title = name;
        item.summary = record[@"detail"] ?: @"";
        item.detail = record[@"detail"] ?: @"";
        item.scope = internal ? @"internal" : @"user";
        item.path = configPath;
        item.enabled = [record[@"enabled"] boolValue];
        item.installed = YES;
        [items addObject:item];
        CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"MCP provenance name=%@ layer=%@ scope=%@ path=%@",
              name, internal ? @"internal" : @"user", item.scope, configPath);
    }
    return items;
}

- (NSArray<CAComposerCatalogItem *> *)scanConfiguredMCPWithHome:(NSString *)home
{
    return [CAComposerCatalog scanConfiguredMCPWithHome:home];
}

+ (BOOL)isInternalMCPName:(NSString *)name
{
    if (!name.length) return NO;
    NSString *normalized = [name.lowercaseString stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSSet<NSString *> *internalNames = [NSSet setWithArray:@[
        CABundleIdentifier.lowercaseString,
        @"codexapp",
        @"codex-app",
        @"codexapps",
        @"mtagent",
        @"mt-agent",
        @"codexapp-native-tools",
        @"ca-native-tools",
        @"native-tools",
        @"internal",
    ]];
    if ([internalNames containsObject:normalized]) return YES;
    return [normalized hasPrefix:@"codexapp-native"] || [normalized hasPrefix:@"ca-native"];
}

#pragma mark - 扫描：提示 / 记忆

+ (NSArray<CAComposerCatalogItem *> *)scanPromptsWithHome:(NSString *)home
{
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];
    NSString *root = [home stringByAppendingPathComponent:@"prompts"];
    if (![self isDirectory:root]) return items;

    for (NSString *entry in [self sortedDirectoryEntries:root]) {
        if ([entry hasPrefix:@"."]) continue;
        NSString *child = [root stringByAppendingPathComponent:entry];
        BOOL childIsDirectory = [self isDirectory:child];
        if (childIsDirectory) {
            for (NSString *nested in [self sortedDirectoryEntries:child]) {
                if (![nested.lowercaseString hasSuffix:@".md"]) continue;
                NSString *path = [child stringByAppendingPathComponent:nested];
                CAComposerCatalogItem *item = [self promptItemAtPath:path
                                                          identifier:[NSString stringWithFormat:@"prompts:%@/%@", entry, nested.stringByDeletingPathExtension]
                                                               scope:@"user"];
                if (item) [items addObject:item];
            }
            continue;
        }
        if (![entry.lowercaseString hasSuffix:@".md"]) continue;
        CAComposerCatalogItem *item = [self promptItemAtPath:child
                                                  identifier:[NSString stringWithFormat:@"prompt:%@", entry.stringByDeletingPathExtension]
                                                       scope:@"user"];
        if (item) [items addObject:item];
    }
    return items;
}

+ (CAComposerCatalogItem *)promptItemAtPath:(NSString *)path identifier:(NSString *)identifier scope:(NSString *)scope
{
    NSString *text = [self textAtPath:path];
    NSString *body = nil;
    NSDictionary<NSString *, NSString *> *metadata = [self metadataFrontMatterFromText:text body:&body];
    CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindPrompt identifier:identifier];
    item.name = path.lastPathComponent.stringByDeletingPathExtension;
    item.title = metadata[@"title"] ?: metadata[@"name"] ?: [self firstHeadingInText:body] ?: item.name;
    item.summary = metadata[@"description"] ?: [self firstParagraphInText:body] ?: @"";
    item.scope = scope;
    item.path = path;
    item.body = body ?: @"";
    item.detail = metadata[@"argument-hint"] ?: path;
    item.enabled = YES;
    item.installed = YES;
    return item;
}

- (NSArray<CAComposerCatalogItem *> *)scanPromptsWithHome:(NSString *)home
{
    return [CAComposerCatalog scanPromptsWithHome:home];
}

+ (NSArray<CAComposerCatalogItem *> *)scanMemoryWithHome:(NSString *)home workspace:(NSString *)workspace
{
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *candidates = [NSMutableArray array];
    if (workspace.length) {
        [candidates addObject:@[ [workspace stringByAppendingPathComponent:@"AGENTS.md"], @"workspace" ]];
        [candidates addObject:@[ [workspace stringByAppendingPathComponent:@"AGENTS.override.md"], @"workspace" ]];
    }
    if (home.length) {
        [candidates addObject:@[ [home stringByAppendingPathComponent:@"AGENTS.md"], @"user" ]];
        [candidates addObject:@[ [home stringByAppendingPathComponent:@"AGENTS.override.md"], @"user" ]];
    }
    for (NSArray<NSString *> *candidate in candidates) {
        NSString *path = candidate.firstObject;
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        CAComposerCatalogItem *item = [self memoryItemAtPath:path
                                                  identifier:[NSString stringWithFormat:@"memory:%@", path.lastPathComponent]
                                                       scope:candidate.lastObject];
        if (item) [items addObject:item];
    }
    NSString *memories = [home stringByAppendingPathComponent:@"memories"];
    for (NSString *entry in [self sortedDirectoryEntries:memories]) {
        if ([entry hasPrefix:@"."]) continue;
        NSString *path = [memories stringByAppendingPathComponent:entry];
        if ([self isDirectory:path]) continue;
        CAComposerCatalogItem *item = [self memoryItemAtPath:path
                                                  identifier:[NSString stringWithFormat:@"memory:%@", entry]
                                                       scope:@"user"];
        if (item) [items addObject:item];
    }
    return items;
}

+ (CAComposerCatalogItem *)memoryItemAtPath:(NSString *)path identifier:(NSString *)identifier scope:(NSString *)scope
{
    NSString *text = [self textAtPath:path];
    if (!text.length) return nil;
    CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithKind:CAComposerCatalogKindMemory identifier:identifier];
    item.name = path.lastPathComponent;
    item.title = [self firstHeadingInText:text] ?: path.lastPathComponent;
    item.summary = [self firstParagraphInText:text] ?: @"";
    item.scope = scope;
    item.path = path;
    item.body = text;
    item.detail = path;
    item.enabled = YES;
    item.installed = YES;
    return item;
}

- (NSArray<CAComposerCatalogItem *> *)scanMemoryWithHome:(NSString *)home workspace:(NSString *)workspace
{
    return [CAComposerCatalog scanMemoryWithHome:home workspace:workspace];
}

+ (NSArray<CAComposerCatalogItem *> *)scanFilesWithHome:(NSString *)home workspace:(NSString *)workspace
{
    NSMutableArray<CAComposerCatalogItem *> *items = [NSMutableArray array];
    [items addObjectsFromArray:[self scanSkillsWithHome:home workspace:workspace]];
    [items addObjectsFromArray:[self scanLocalPluginsWithHome:home workspace:workspace]];
    [items addObjectsFromArray:[self scanPromptsWithHome:home]];
    [items addObjectsFromArray:[self scanMemoryWithHome:home workspace:workspace]];

    NSMutableArray<CAComposerCatalogItem *> *deduplicated = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (CAComposerCatalogItem *item in items) {
        if (!item.identifier.length || [seen containsObject:item.identifier]) continue;
        [seen addObject:item.identifier];
        [deduplicated addObject:item];
    }
    return deduplicated;
}

- (NSArray<CAComposerCatalogItem *> *)scanFilesWithHome:(NSString *)home workspace:(NSString *)workspace
{
    return [CAComposerCatalog scanFilesWithHome:home workspace:workspace];
}

#pragma mark - 缓存

+ (NSString *)cachePathForWorkspace:(NSString *)workspace
{
    NSString *directory = CARuntimePaths.composerCatalogCacheDirectory;
    [CARuntimePaths ensureDirectory:directory mode:0700 error:NULL];
    NSString *name = [NSString stringWithFormat:@"%016llx", CAComposerHash64(workspace ?: @"")];
    return [[directory stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"json"];
}

- (NSArray<CAComposerCatalogItem *> *)itemsOfKind:(CAComposerCatalogKind)kind
{
    NSMutableArray<CAComposerCatalogItem *> *result = [NSMutableArray array];
    for (CAComposerCatalogItem *item in self.items) {
        if (item.kind == kind) [result addObject:item];
    }
    return result;
}

- (BOOL)restorePersistentCacheForWorkspace:(NSString *)workspace
{
    NSString *normalized = workspace.length ? workspace : [CAComposerCatalog defaultWorkspacePath];
    NSString *path = [CAComposerCatalog cachePathForWorkspace:normalized];
    NSData *data = [NSData dataWithContentsOfFile:path];

    if (!data.length) {
        // 原包：composer catalog legacy snapshot migration %@ bytes=%lu
        NSString *legacy = [CARuntimePaths.composerCatalogCacheDirectory stringByAppendingPathComponent:kCALegacySnapshotName];
        NSData *legacyData = [NSData dataWithContentsOfFile:legacy];
        if (legacyData.length) {
            CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"composer catalog legacy snapshot migration %@ bytes=%lu",
                  legacy, (unsigned long)legacyData.length);
            [CARuntimePaths writeFileAtomically:path contents:legacyData mode:0600 error:NULL];
            data = legacyData;
        }
    }
    if (!data.length) return NO;

    id snapshot = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![snapshot isKindOfClass:NSDictionary.class]) return NO;

    NSMutableArray<CAComposerCatalogItem *> *restored = [NSMutableArray array];
    for (id entry in ((NSDictionary *)snapshot)[@"items"]) {
        CAComposerCatalogItem *item = [CAComposerCatalogItem itemWithDictionary:entry];
        if (item) [restored addObject:item];
    }
    if (!restored.count) return NO;

    self.workspacePath = normalized;
    self.items = restored;
    NSNumber *savedAt = ((NSDictionary *)snapshot)[@"savedAt"];
    self.loadedAt = [savedAt isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:savedAt.doubleValue] : nil;
    NSTimeInterval age = self.loadedAt ? -self.loadedAt.timeIntervalSinceNow : 0;

    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"composer catalog cache restored items=%lu skills=%lu plugins=%lu mcp=%lu age=%.1fs workspace=%@",
          (unsigned long)restored.count,
          (unsigned long)[self itemsOfKind:CAComposerCatalogKindSkill].count,
          (unsigned long)[self itemsOfKind:CAComposerCatalogKindPlugin].count,
          (unsigned long)[self itemsOfKind:CAComposerCatalogKindMCP].count,
          age, normalized);
    return YES;
}

- (BOOL)persistCacheForWorkspace:(NSString *)workspace
{
    NSString *normalized = workspace.length ? workspace : [CAComposerCatalog defaultWorkspacePath];
    NSMutableArray<NSDictionary *> *payloadItems = [NSMutableArray array];
    for (CAComposerCatalogItem *item in self.items) {
        [payloadItems addObject:[item dictionaryRepresentation]];
    }
    NSDictionary *snapshot = @{
        @"savedAt": @([NSDate date].timeIntervalSince1970),
        @"workspace": normalized,
        @"items": payloadItems,
        @"skillsFromServer": @NO,
        @"skillErrors": @[],
        @"lastServerMCP": @[],
        @"lastServerSkills": @[],
        @"lastServerPlugins": @[],
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
    if (!data) {
        CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"composer catalog cache write failed: %@", error.localizedDescription ?: @"invalid snapshot");
        return NO;
    }
    NSString *path = [CAComposerCatalog cachePathForWorkspace:normalized];
    if (![CARuntimePaths writeFileAtomically:path contents:data mode:0600 error:&error]) {
        CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"composer catalog cache write failed: %@", error.localizedDescription ?: @"unknown");
        return NO;
    }
    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"composer catalog cache saved bytes=%lu", (unsigned long)data.length);
    return YES;
}

- (void)invalidate
{
    self.items = @[];
    self.loadedAt = nil;
    self.lastError = nil;
    self.lastMCPError = nil;
    self.lastPluginError = nil;
    self.generation += 1;
    [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:self];
}

#pragma mark - 刷新

- (void)refreshForWorkspace:(NSString *)workspace force:(BOOL)force completion:(CAComposerCatalogCompletion)completion
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshForWorkspace:workspace force:force completion:completion];
        });
        return;
    }

    NSString *normalized = workspace.length ? workspace : [CAComposerCatalog defaultWorkspacePath];
    if (self.loading && !force) {
        if (completion) [_waiters addObject:[completion copy]];
        return;
    }
    if (self.loading && force) {
        CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"composer catalog force refresh supersedes in-flight requests workspace=%@", normalized);
    }
    if (completion) [_waiters addObject:[completion copy]];

    self.generation += 1;
    NSUInteger generation = self.generation;
    self.loading = YES;
    self.workspacePath = normalized;
    self.lastError = nil;

    CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"composer catalog prewarm begin reason=%@ workspace=%@ force=%d",
          force ? @"force" : @"prewarm", normalized, (int)(force ? 1 : 0));

    NSString *home = [CAComposerCatalog resolvedHome];
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        CAComposerCatalog *strongSelf = weakSelf;
        if (!strongSelf) return;

        NSArray<CAComposerCatalogItem *> *files = [CAComposerCatalog scanFilesWithHome:home workspace:normalized];
        NSArray<CAComposerCatalogItem *> *mcp = [CAComposerCatalog scanConfiguredMCPWithHome:home];
        NSMutableArray<CAComposerCatalogItem *> *combined = [files mutableCopy];
        [combined addObjectsFromArray:mcp];
        NSArray<CAComposerCatalogItem *> *snapshot = [CAComposerCatalog sortedSkills:combined];

        dispatch_async(dispatch_get_main_queue(), ^{
            CAComposerCatalog *innerSelf = weakSelf;
            if (!innerSelf || generation != innerSelf.generation) return;
            innerSelf.items = snapshot;
            CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"composer catalog local-first items=%lu while server discovery continues",
                  (unsigned long)snapshot.count);

            [innerSelf refreshMCPRuntimeStatusWithCompletion:^(NSError *error) {
                CAComposerCatalog *finalSelf = weakSelf;
                if (!finalSelf || generation != finalSelf.generation) return;
                finalSelf.loading = NO;
                finalSelf.loadedAt = [NSDate date];
                if (error) finalSelf.lastError = error.localizedDescription;
                [finalSelf persistCacheForWorkspace:normalized];
                [finalSelf logCatalogSummary];
                CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"composer catalog prewarm done reason=%@ skills=%lu plugins=%lu mcp=%lu error=%@",
                      force ? @"force" : @"prewarm",
                      (unsigned long)[finalSelf itemsOfKind:CAComposerCatalogKindSkill].count,
                      (unsigned long)[finalSelf itemsOfKind:CAComposerCatalogKindPlugin].count,
                      (unsigned long)[finalSelf itemsOfKind:CAComposerCatalogKindMCP].count,
                      error.localizedDescription ?: @"(none)");
                [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:finalSelf];
                [finalSelf flushWaitersWithError:error];
            }];
        });
    });
}

- (void)flushWaitersWithError:(NSError *)error
{
    NSArray<CAComposerCatalogCompletion> *waiters = [_waiters copy];
    [_waiters removeAllObjects];
    for (CAComposerCatalogCompletion waiter in waiters) waiter(error);
}

- (void)refreshMCPRuntimeStatusWithCompletion:(CAComposerCatalogCompletion)completion
{
    NSArray<CAComposerCatalogItem *> *mcpItems = [self itemsOfKind:CAComposerCatalogKindMCP];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (CAComposerCatalogItem *item in mcpItems) {
        if (!item.name.length) continue;
        if ([CAComposerCatalog isInternalMCPName:item.name]) continue;
        [names addObject:item.name];
    }

    CACodexEngine *engine = [CACodexEngine sharedEngine];
    if (!names.count || engine.persistentAppServer == nil) {
        // 原包：MCP connection refresh skipped; using cached servers=%lu
        CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"MCP connection refresh skipped; using cached servers=%lu",
              (unsigned long)names.count);
        if (completion) completion(nil);
        return;
    }

    CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"MCP lightweight refresh begin workspace=%@", self.workspacePath ?: @"");
    __weak typeof(self) weakSelf = self;
    [engine readConnectedMCPServerStatusesForNames:names completion:^(NSDictionary<NSString *, NSNumber *> *statuses) {
        CAComposerCatalog *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSUInteger runtimeReady = 0;
        for (CAComposerCatalogItem *item in strongSelf.items) {
            if (item.kind != CAComposerCatalogKindMCP) continue;
            NSNumber *status = statuses[item.name];
            if (!status) continue;
            if (status.boolValue) runtimeReady += 1;
            item.installed = status.boolValue;
        }
        CALog(CALogLevelDebug, @"CHAT-PLUGIN",
              @"MCP lightweight refresh done configured=%lu runtime=%lu visible=%lu error=%@",
              (unsigned long)names.count, (unsigned long)runtimeReady, (unsigned long)mcpItems.count, @"(none)");
        if (completion) completion(nil);
    }];
}

- (void)logCatalogSummary
{
    NSUInteger skills = 0, prompts = 0, plugins = 0, mcp = 0, memory = 0;
    NSMutableSet<NSString *> *scopes = [NSMutableSet set];
    for (CAComposerCatalogItem *item in self.items) {
        switch (item.kind) {
            case CAComposerCatalogKindSkill:
                skills += 1;
                if (item.scope.length) [scopes addObject:item.scope];
                break;
            case CAComposerCatalogKindPrompt: prompts += 1; break;
            case CAComposerCatalogKindPlugin: plugins += 1; break;
            case CAComposerCatalogKindMCP:    mcp += 1;     break;
            case CAComposerCatalogKindMemory: memory += 1;  break;
            default: break;
        }
    }
    NSArray<NSString *> *sortedScopes = [scopes.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSString *scopeList = sortedScopes.count ? [sortedScopes componentsJoinedByString:@","] : @"none";

    CALog(CALogLevelInfo, @"CHAT-PLUGIN",
          @"composer catalog skills=%lu(%@) prompts=%lu plugins=%lu(server=%lu local=%lu) mcp=%lu memory=%lu",
          (unsigned long)skills, scopeList, (unsigned long)prompts, (unsigned long)plugins,
          (unsigned long)0, (unsigned long)plugins, (unsigned long)mcp, (unsigned long)memory);
}

- (void)refreshLocalSkillsForWorkspace:(NSString *)workspace completion:(CAComposerCatalogCompletion)completion
{
    NSString *normalized = workspace.length ? workspace : (self.workspacePath ?: [CAComposerCatalog defaultWorkspacePath]);
    NSString *home = [CAComposerCatalog resolvedHome];
    NSArray<CAComposerCatalogItem *> *scanned = [CAComposerCatalog scanSkillsWithHome:home workspace:normalized];

    NSMutableArray<CAComposerCatalogItem *> *others = [NSMutableArray array];
    for (CAComposerCatalogItem *item in self.items) {
        if (item.kind != CAComposerCatalogKindSkill) [others addObject:item];
    }
    NSMutableArray<CAComposerCatalogItem *> *combined = [others mutableCopy];
    [combined addObjectsFromArray:scanned];
    self.workspacePath = normalized;
    self.items = [CAComposerCatalog sortedSkills:combined];

    NSUInteger localCount = 0;
    for (CAComposerCatalogItem *item in scanned) {
        if ([item.scope isEqualToString:@"user"] || [item.scope isEqualToString:@"project"] || [item.scope isEqualToString:@"workspace"]) localCount += 1;
    }
    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"local skills refresh workspace=%@ local=%lu other=%lu",
          normalized, (unsigned long)localCount, (unsigned long)(scanned.count - localCount));
    [self persistCacheForWorkspace:normalized];
    [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:self];
    if (completion) completion(nil);
}

- (void)refreshMCPForWorkspace:(NSString *)workspace completion:(CAComposerCatalogCompletion)completion
{
    NSString *normalized = workspace.length ? workspace : (self.workspacePath ?: [CAComposerCatalog defaultWorkspacePath]);
    NSString *home = [CAComposerCatalog resolvedHome];
    NSArray<CAComposerCatalogItem *> *scanned = [CAComposerCatalog scanConfiguredMCPWithHome:home];

    NSMutableArray<CAComposerCatalogItem *> *others = [NSMutableArray array];
    for (CAComposerCatalogItem *item in self.items) {
        if (item.kind != CAComposerCatalogKindMCP) [others addObject:item];
    }
    NSMutableArray<CAComposerCatalogItem *> *combined = [others mutableCopy];
    [combined addObjectsFromArray:scanned];
    self.workspacePath = normalized;
    self.items = [CAComposerCatalog sortedSkills:combined];

    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"MCP lightweight refresh done configured=%lu runtime=%lu visible=%lu error=%@",
          (unsigned long)scanned.count, (unsigned long)0, (unsigned long)scanned.count, @"(none)");
    [self persistCacheForWorkspace:normalized];
    [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:self];
    if (completion) completion(nil);
}

#pragma mark - 开关 / 删除

- (void)forgetMCPServerNamed:(NSString *)name
{
    if (!name.length) return;
    NSMutableArray<CAComposerCatalogItem *> *remaining = [NSMutableArray array];
    for (CAComposerCatalogItem *item in self.items) {
        if (item.kind == CAComposerCatalogKindMCP && [item.name isEqualToString:name]) continue;
        [remaining addObject:item];
    }
    self.items = remaining;
}

- (void)setSkill:(CAComposerCatalogItem *)item enabled:(BOOL)enabled completion:(CAComposerCatalogActionCompletion)completion
{
    if (!item.identifier.length) {
        NSError *error = [NSError errorWithDomain:@"CodexApp.ComposerCatalog" code:400
                                         userInfo:@{ NSLocalizedDescriptionKey: @"skill item missing identifier" }];
        if (completion) completion(NO, error);
        return;
    }
    self.skillState[item.identifier] = @(enabled);
    NSError *error = nil;
    BOOL ok = [self persistSkillStateWithError:&error];
    item.enabled = enabled;
    // 原包走 app-server "skills/config/write"（keyPath/mergeStrategy=upsert）；此处以本地状态文件等价落盘
    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"skill %@ enabled=%@ effective=%@",
          item.name ?: item.identifier, enabled ? @"YES" : @"NO", enabled ? @"YES" : @"NO");
    [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:self];
    if (completion) completion(ok, error);
}

#pragma mark - MCP config.toml 重写

+ (NSString *)configPathForHome:(NSString *)home
{
    return [home stringByAppendingPathComponent:kCAConfigTOMLLeafName];
}

+ (NSRange)sectionRangeNamed:(NSString *)name lines:(NSArray<NSString *> *)lines fromIndex:(NSUInteger)fromIndex
{
    NSUInteger end = lines.count;
    for (NSUInteger index = fromIndex + 1; index < lines.count; index++) {
        NSString *line = lines[index];
        NSString *trimmed = CAComposerTrim(line);
        if (![trimmed hasPrefix:@"["]) continue;
        if ([self lineIsSubtableOfMCPServer:line name:name]) continue;
        end = index;
        break;
    }
    return NSMakeRange(fromIndex, end - fromIndex);
}

+ (BOOL)writeLines:(NSArray<NSString *> *)lines toConfigPath:(NSString *)path error:(NSError **)error
{
    NSString *text = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return [CARuntimePaths writeFileAtomically:path contents:data mode:0644 error:error];
}

+ (BOOL)setMCPEnabled:(BOOL)enabled name:(NSString *)name configPath:(NSString *)path error:(NSError **)error
{
    NSString *text = [self textAtPath:path];
    NSMutableArray<NSString *> *lines = [CAComposerLines(text) mutableCopy];
    NSString *rendered = [NSString stringWithFormat:@"enabled = %@", enabled ? @"true" : @"false"];

    for (NSUInteger index = 0; index < lines.count; index++) {
        NSString *lineName = [self mcpSectionHeaderNameFromLine:lines[index]];
        if (![lineName isEqualToString:name]) continue;

        NSRange range = [self sectionRangeNamed:name lines:lines fromIndex:index];
        for (NSUInteger cursor = range.location; cursor < NSMaxRange(range); cursor++) {
            if ([self enabledValueFromLine:lines[cursor]] >= 0) {
                lines[cursor] = rendered;
                return [self writeLines:lines toConfigPath:path error:error];
            }
        }
        [lines insertObject:rendered atIndex:range.location + 1];
        return [self writeLines:lines toConfigPath:path error:error];
    }

    // mcp_servers.NAME.enabled / mcp_servers."NAME".enabled
    NSString *dotted = [NSString stringWithFormat:@"^\\s*mcp_servers\\.(?:\"%@\"|'%@'|%@)\\.enabled\\s*=.*$", name, name, name];
    NSRegularExpression *dottedRegex = [NSRegularExpression regularExpressionWithPattern:dotted options:0 error:NULL];
    for (NSUInteger index = 0; index < lines.count; index++) {
        NSRange full = NSMakeRange(0, lines[index].length);
        if ([dottedRegex firstMatchInString:lines[index] options:0 range:full]) {
            lines[index] = [NSString stringWithFormat:@"mcp_servers.%@.%@", name, rendered];
            return [self writeLines:lines toConfigPath:path error:error];
        }
    }

    // 追加新段
    while (lines.count && !CAComposerTrim(lines.lastObject).length) [lines removeLastObject];
    if (lines.count) [lines addObject:@""];
    [lines addObject:[NSString stringWithFormat:@"[mcp_servers.%@]", name]];
    [lines addObject:rendered];
    return [self writeLines:lines toConfigPath:path error:error];
}

+ (BOOL)removeMCPServerNamed:(NSString *)name configPath:(NSString *)path error:(NSError **)error
{
    NSString *text = [self textAtPath:path];
    NSMutableArray<NSString *> *lines = [CAComposerLines(text) mutableCopy];
    BOOL changed = NO;

    for (NSUInteger index = 0; index < lines.count; ) {
        NSString *lineName = [self mcpSectionHeaderNameFromLine:lines[index]];
        if ([lineName isEqualToString:name]) {
            NSRange range = [self sectionRangeNamed:name lines:lines fromIndex:index];
            [lines removeObjectsInRange:range];
            changed = YES;
            continue;
        }
        index += 1;
    }

    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    NSArray<NSString *> *dottedPrefixes = @[
        [NSString stringWithFormat:@"mcp_servers.%@", name],
        [NSString stringWithFormat:@"mcp_servers.\"%@\"", name],
        [NSString stringWithFormat:@"mcp_servers.'%@'", name],
    ];
    for (NSString *line in lines) {
        NSString *trimmed = CAComposerTrim(line);
        BOOL isDotted = NO;
        for (NSString *prefix in dottedPrefixes) {
            if (![trimmed hasPrefix:prefix]) continue;
            NSString *rest = [trimmed substringFromIndex:prefix.length];
            if (!rest.length || [rest hasPrefix:@"."] || [rest hasPrefix:@" "] ||
                [rest hasPrefix:@"\t"] || [rest hasPrefix:@"="]) {
                isDotted = YES;
                break;
            }
        }
        if (isDotted) { changed = YES; continue; }
        [kept addObject:line];
    }
    if (!changed) return NO;
    return [self writeLines:kept toConfigPath:path error:error];
}

- (void)setMCPServer:(CAComposerCatalogItem *)item enabled:(BOOL)enabled completion:(CAComposerCatalogActionCompletion)completion
{
    if (!item.name.length) {
        NSError *error = [NSError errorWithDomain:@"CodexApp.ComposerCatalog" code:400
                                         userInfo:@{ NSLocalizedDescriptionKey: @"mcp item missing name" }];
        if (completion) completion(NO, error);
        return;
    }
    NSString *path = [CAComposerCatalog configPathForHome:[CAComposerCatalog resolvedHome]];
    NSError *error = nil;
    BOOL ok = [CAComposerCatalog setMCPEnabled:enabled name:item.name configPath:path error:&error];
    if (ok) {
        BOOL previous = item.enabled;
        item.enabled = enabled;
        CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"MCP toggle user config name=%@ enabled=%d status=%@ file=%@",
              item.name, (int)(enabled ? 1 : 0), @"saved", path);
        CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"MCP disk/UI sync name=%@ old=%d config=%d",
              item.name, (int)(previous ? 1 : 0), (int)(enabled ? 1 : 0));
        CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"MCP toggle project/local config saved name=%@ enabled=%d path=%@",
              item.name, (int)(enabled ? 1 : 0), path);
        [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:self];
    } else {
        self.lastMCPError = error.localizedDescription;
        CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"MCP toggle user config name=%@ enabled=%d status=%@ file=%@",
              item.name, (int)(enabled ? 1 : 0), error.localizedDescription ?: @"failed", path);
    }
    if (completion) completion(ok, error);
}

- (void)removeMCPServer:(CAComposerCatalogItem *)item completion:(CAComposerCatalogActionCompletion)completion
{
    if (!item.name.length) {
        NSError *error = [NSError errorWithDomain:@"CodexApp.ComposerCatalog" code:400
                                         userInfo:@{ NSLocalizedDescriptionKey: @"mcp item missing name" }];
        if (completion) completion(NO, error);
        return;
    }
    NSString *path = [CAComposerCatalog configPathForHome:[CAComposerCatalog resolvedHome]];
    NSError *error = nil;
    BOOL ok = [CAComposerCatalog removeMCPServerNamed:item.name configPath:path error:&error];
    if (ok) {
        CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"MCP remove user config name=%@ status=%@ file=%@", item.name, @"removed", path);
        CALog(CALogLevelDebug, @"CHAT-PLUGIN", @"MCP remove project/local config name=%@ path=%@", item.name, path);
        [self forgetMCPServerNamed:item.name];
        [[NSNotificationCenter defaultCenter] postNotificationName:CAComposerCatalogDidChangeNotification object:self];
    } else {
        self.lastMCPError = error.localizedDescription ?: @"not found in user config.toml";
        CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"MCP remove user config name=%@ status=%@ file=%@",
              item.name, self.lastMCPError, path);
    }
    if (completion) completion(ok, error);
}

#pragma mark - 过期判断

- (BOOL)isCacheStale
{
    if (!self.loadedAt) return YES;
    return -self.loadedAt.timeIntervalSinceNow > (NSTimeInterval)kCACatalogCacheTTL;
}

@end
