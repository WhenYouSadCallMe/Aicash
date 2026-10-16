//
//  CARuntimeCatalog.m
//  对齐原包：CARuntimeManifestURL（raw.githubusercontent.com/susu123oss/CodexApp-Runtime/.../runtime-manifest.json）、
//           缓存到 support/RuntimeDownloads、只接受 https、字段名原样（runtimeID/…/archiveSHA256/downloadSize/expandedSize/order/optional/install）
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CARuntimeCatalog.h"

NSNotificationName const CARuntimeCatalogDidChangeNotification = @"CARuntimeCatalogDidChangeNotification";

static const NSTimeInterval kAutoRefreshInterval = 6 * 60 * 60;

@implementation CARuntimeCatalogEntry

+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary error:(NSError **)error
{
    if (![dictionary isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Runtime" code:400 userInfo:@{ NSLocalizedDescriptionKey: @"invalid manifest entry" }];
        return nil;
    }
    CARuntimeCatalogEntry *entry = [CARuntimeCatalogEntry new];
    entry.runtimeID     = dictionary[@"runtime_id"] ?: dictionary[@"runtimeID"] ?: dictionary[@"id"];
    entry.displayName   = dictionary[@"display_name"] ?: dictionary[@"displayName"] ?: dictionary[@"name"];
    entry.summary       = dictionary[@"summary"] ?: dictionary[@"description"];
    entry.handler       = dictionary[@"handler"];
    entry.group         = dictionary[@"group"];
    entry.version       = dictionary[@"version"];
    entry.revision      = [dictionary[@"revision"] integerValue];
    entry.archiveURL    = dictionary[@"archive_url"] ?: dictionary[@"archiveURL"];
    entry.archiveSHA256 = dictionary[@"archive_sha256"] ?: dictionary[@"archiveSHA256"];
    entry.downloadSize  = [dictionary[@"download_size"] unsignedLongLongValue];
    entry.expandedSize  = [dictionary[@"expanded_size"] unsignedLongLongValue];
    entry.order         = [dictionary[@"order"] integerValue];
    entry.optional      = [dictionary[@"optional"] boolValue];
    entry.install       = dictionary[@"install"];
    entry.raw           = dictionary;
    if (!entry.runtimeID.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Runtime" code:400 userInfo:@{ NSLocalizedDescriptionKey: @"manifest entry missing runtime id" }];
        return nil;
    }
    return entry;
}

@end

@implementation CARuntimeCatalog
{
    NSMutableArray<CARuntimeCatalogEntry *> *_entries;
    NSMutableArray<NSString *> *_newlyAvailable;
    NSMutableArray<NSString *> *_changed;
    NSTimer *_timer;
    dispatch_queue_t _queue;
}

+ (instancetype)sharedCatalog
{
    static CARuntimeCatalog *catalog; static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [CARuntimeCatalog new]; });
    return catalog;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _manifestURLString = CARuntimeManifestURL;
        _cachePath = [[CARuntimePaths runtimeDownloadsDirectory] stringByAppendingPathComponent:@"runtime-manifest.json"];
        _entries = [NSMutableArray array];
        _newlyAvailable = [NSMutableArray array];
        _changed = [NSMutableArray array];
        _queue = dispatch_queue_create("app.codex.runtimecatalog", DISPATCH_QUEUE_SERIAL);
        [self loadCachedManifest];
    }
    return self;
}

- (NSArray<CARuntimeCatalogEntry *> *)entries { return [_entries copy]; }
- (NSArray<NSString *> *)newlyAvailableRuntimeIDs { return [_newlyAvailable copy]; }
- (NSArray<NSString *> *)changedRuntimeIDs { return [_changed copy]; }

#pragma mark - 解析 / 缓存

- (NSArray<CARuntimeCatalogEntry *> *)entriesFromData:(NSData *)data error:(NSError **)error
{
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return nil;
    NSArray *rawEntries = nil;
    if ([json isKindOfClass:NSArray.class]) rawEntries = json;
    else if ([json isKindOfClass:NSDictionary.class]) rawEntries = json[@"runtimes"] ?: json[@"entries"] ?: json[@"runtimes_v2"] ?: @[];
    NSMutableArray<CARuntimeCatalogEntry *> *result = [NSMutableArray array];
    for (NSDictionary *d in rawEntries) {
        CARuntimeCatalogEntry *entry = [CARuntimeCatalogEntry entryWithDictionary:d error:error];
        if (entry) [result addObject:entry];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(CARuntimeCatalogEntry *a, CARuntimeCatalogEntry *b) {
        return [@(a.order) compare:@(b.order)];
    }];
}

- (BOOL)loadCachedManifest
{
    NSData *data = [NSData dataWithContentsOfFile:self.cachePath];
    if (!data) return NO;
    NSArray<CARuntimeCatalogEntry *> *entries = [self entriesFromData:data error:NULL];
    if (!entries) return NO;
    [self applyEntries:entries markChanges:NO];
    return YES;
}

- (void)applyEntries:(NSArray<CARuntimeCatalogEntry *> *)entries markChanges:(BOOL)markChanges
{
    dispatch_async(_queue, ^{
        NSDictionary<NSString *, CARuntimeCatalogEntry *> *previous = [NSDictionary dictionaryWithObjects:self->_entries
                                                                                                 forKeys:[self->_entries valueForKey:@"runtimeID"] ?: @[]];
        [self->_newlyAvailable removeAllObjects];
        [self->_changed removeAllObjects];
        for (CARuntimeCatalogEntry *entry in entries) {
            CARuntimeCatalogEntry *old = previous[entry.runtimeID];
            if (markChanges && !old) [self->_newlyAvailable addObject:entry.runtimeID];
            else if (markChanges && old.revision != entry.revision) [self->_changed addObject:entry.runtimeID];
        }
        self->_entries = [entries mutableCopy];
        CALog(CALogLevelInfo, @"RUNTIME", @"catalog refreshed entries=%lu new=%lu changed=%lu",
              (unsigned long)entries.count, (unsigned long)self->_newlyAvailable.count, (unsigned long)self->_changed.count);
        [[NSNotificationCenter defaultCenter] postNotificationName:CARuntimeCatalogDidChangeNotification object:self];
    });
}

#pragma mark - 拉取

- (BOOL)isSafeHTTPSURL:(NSURL *)url
{
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length > 0;
}

- (void)startAutoRefresh
{
    [self refreshIfStale];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kAutoRefreshInterval target:self selector:@selector(refreshIfStale) userInfo:nil repeats:YES];
}

- (void)refreshIfStale
{
    NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:@"CodexRuntimeCatalogLastRefresh"];
    if (last && -[last timeIntervalSinceNow] < kAutoRefreshInterval) return;
    [self refreshNowWithCompletion:nil];
}

- (void)refreshNowWithCompletion:(void (^)(BOOL, NSError *))completion
{
    NSURL *url = [NSURL URLWithString:self.manifestURLString];
    if (![self isSafeHTTPSURL:url]) {
        self.lastError = @"manifest url is not https";
        if (completion) completion(NO, [NSError errorWithDomain:@"CodexApp.Runtime" code:400 userInfo:@{ NSLocalizedDescriptionKey: self.lastError }]);
        return;
    }
    self.refreshing = YES;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        self.refreshing = NO;
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error || !data.length || http.statusCode >= 400) {
            self.lastError = error.localizedDescription ?: [NSString stringWithFormat:@"http %ld", (long)http.statusCode];
            CALog(CALogLevelWarn, @"RUNTIME", @"catalog refresh failed reason=%@", self.lastError);
            if (completion) completion(NO, error);
            return;
        }
        NSError *parseError = nil;
        NSArray<CARuntimeCatalogEntry *> *entries = [self entriesFromData:data error:&parseError];
        if (!entries) {
            self.lastError = parseError.localizedDescription;
            if (completion) completion(NO, parseError);
            return;
        }
        [CARuntimePaths writeFileAtomically:self.cachePath contents:data mode:0644 error:NULL];
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"CodexRuntimeCatalogLastRefresh"];
        [self applyEntries:entries markChanges:YES];
        if (completion) completion(YES, nil);
    }];
    [task resume];
}

- (CARuntimeCatalogEntry *)entryForID:(NSString *)runtimeID
{
    for (CARuntimeCatalogEntry *entry in _entries) if ([entry.runtimeID isEqualToString:runtimeID]) return entry;
    return nil;
}

- (NSString *)fallbackDisplayName:(NSString *)runtimeID
{
    if ([runtimeID isEqualToString:@"codex"]) return @"Codex Runtime";
    if ([runtimeID isEqualToString:@"python"]) return @"Python Runtime";
    if ([runtimeID isEqualToString:@"theos"]) return @"Theos";
    if ([runtimeID containsString:@"reverse"]) return @"Reverse Tools";
    return runtimeID;
}

- (NSString *)fallbackHandler:(NSString *)runtimeID
{
    if ([runtimeID isEqualToString:@"codex"]) return @"codex";
    if ([runtimeID isEqualToString:@"python"]) return @"python";
    if ([runtimeID isEqualToString:@"theos"]) return @"theos";
    if ([runtimeID containsString:@"reverse"]) return @"reverse-tools";
    return @"generic";
}

@end
