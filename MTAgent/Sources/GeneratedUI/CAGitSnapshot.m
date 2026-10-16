//
//  CAGitSnapshot.m — 仓库快照解析与状态文案
//
//  解析 `git status --porcelain=v2 --branch -z`：
//    # branch.oid / branch.head / branch.upstream / branch.ab +N -M
//    1 XY sub mH mI mW hH hI <path>            普通变更
//    2 XY sub mH mI mW hH hI Xscore <path> \0 <origPath>   重命名/复制
//    u XY sub m1 m2 m3 mW h1 h2 h3 <path>      冲突
//    ? <path>                                  未跟踪
//  路径本身用 NUL 分隔，因此用 -z 才能在含空格/中文路径下不歧义。
//

#import "CAGitSnapshot.h"

NSString *const kCAGitChangePathKey = @"path";
NSString *const kCAGitChangeOriginalPathKey = @"originalPath";
NSString *const kCAGitChangeSubtitleKey = @"subtitle";
NSString *const kCAGitChangeSymbolKey = @"symbol";
NSString *const kCAGitChangeTintKey = @"tint";
NSString *const kCAGitChangeLabelKey = @"label";
NSString *const kCAGitChangeStagedKey = @"staged";
NSString *const kCAGitChangeUntrackedKey = @"untracked";
NSString *const kCAGitChangeConflictedKey = @"conflicted";
NSString *const kCAGitChangeAddedKey = @"added";
NSString *const kCAGitChangeDeletedKey = @"deleted";
NSString *const kCAGitChangeRenamedKey = @"renamed";
NSString *const kCAGitChangeModifiedKey = @"modified";
NSString *const kCAGitChangeIndexStatusKey = @"indexStatus";
NSString *const kCAGitChangeWorktreeStatusKey = @"worktreeStatus";

@interface CAGitSnapshot ()
{
    NSString *_branch;
    NSString *_upstream;
    NSString *_trackingRemote;
    NSString *_trackingRef;
    NSString *_repositoryRoot;
    NSString *_branchSummary;
    NSString *_error;
    NSString *_userName;
    NSString *_userEmail;
    NSArray *_changes;
    NSArray *_remotes;
    NSDictionary *_remoteURLs;
    unsigned long long _ahead;
    unsigned long long _behind;
    unsigned long long _stagedCount;
    unsigned long long _unstagedCount;
    BOOL _repository;
    BOOL _hasHead;
    BOOL _hasConflicts;
    BOOL _trackingCountsKnown;
}
@end

@implementation CAGitSnapshot

#pragma mark - 构造

+ (instancetype)snapshotFromStatusOutput:(NSString *)output
{
    CAGitSnapshot *snapshot = [[CAGitSnapshot alloc] init];
    [snapshot parseStatusOutput:output];
    return snapshot;
}

+ (instancetype)emptySnapshotWithError:(NSString *)error
{
    CAGitSnapshot *snapshot = [[CAGitSnapshot alloc] init];
    snapshot.error = error;
    snapshot.repository = @NO;
    snapshot.changes = @[];
    snapshot.branch = @"—";
    snapshot.branchSummary = @"没有可用的仓库";
    return snapshot;
}

+ (instancetype)demoSnapshotWithWorkspaceName:(NSString *)name
{
    CAGitSnapshot *snapshot = [[CAGitSnapshot alloc] init];
    // 生成头文件里 setXxx: 的形参是 id 占位，标量一律装箱
    snapshot.repository = @YES;
    // 与截图一致：仓库尚无提交（卡片副标题「未设置上游 · 尚无提交」）
    snapshot.hasHead = @NO;
    snapshot.repositoryRoot = name.length > 0 ? name : @"Documents";
    snapshot.branch = @"master";
    snapshot.branchSummary = @"master";
    snapshot.trackingCountsKnown = @NO;
    snapshot.remoteURLs = @{};
    snapshot.remotes = @[];

    NSArray<NSArray<NSString *> *> *demoRows = @[
        @[ @".mt-device-group-id-v1", @"项目根目录" ],
        @[ @"58A2A9A1-6E24-4C7B-AF31-0E1122339D625.json", @"AIAnalysisHistory/com.bilibili.nddz" ],
        @[ @"952FCAE6-5C41-4A8E-9C62-6B7D8E2294FDE8D.json", @"AIAnalysisHistory/com.bilibili.nddz" ],
        @[ @"97C6CFE2-E7A1-4C3D-8F52-9A1B3C5D24C321.json", @"AIAnalysisHistory/com.bilibili.nddz" ],
        @[ @"C6A9869F-2D54-4E88-B3A7-1F8C9D65E6053.json", @"AIAnalysisHistory/com.bilibili.nddz" ],
        @[ @"D6C0F868-9B12-46D1-8E44-77A0C2B33CA4D9.json", @"AIAnalysisHistory/com.bilibili.nddz" ],
    ];

    NSMutableArray *changes = [NSMutableArray array];
    for (NSArray<NSString *> *row in demoRows) {
        [changes addObject:[self changeWithPath:row[0]
                                      subtitle:row[1]
                                         label:@"未跟踪"
                                       staged:NO
                                      untracked:YES
                                            status:'?'
                                          symbol:nil]];
    }
    snapshot.changes = changes;
    snapshot.stagedCount = @(0);
    // 列表只放代表性样本，计数与截图一致（真实仓库里这里是全部变更数）
    snapshot.unstagedCount = @(24154);
    snapshot.hasConflicts = @NO;
    return snapshot;
}

- (NSArray *)changesStaged:(BOOL)staged
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *change in self.changes ?: @[]) {
        BOOL isStaged = [change[kCAGitChangeStagedKey] boolValue];
        if (isStaged == staged) {
            [result addObject:change];
        }
    }
    return result;
}

#pragma mark - 解析

- (void)parseStatusOutput:(NSString *)output
{
    NSMutableArray *changes = [NSMutableArray array];
    unsigned long long staged = 0;
    unsigned long long unstaged = 0;
    BOOL conflicts = NO;

    NSArray<NSString *> *tokens = output.length > 0 ? [output componentsSeparatedByString:@"\0"] : @[];
    for (NSUInteger index = 0; index < tokens.count; index++) {
        NSString *token = tokens[index];
        if (token.length == 0) {
            continue;
        }

        if ([token hasPrefix:@"# branch.oid "]) {
            NSString *oid = [token substringFromIndex:@"# branch.oid ".length];
            _hasHead = ![oid hasPrefix:@"(initial)"];
            continue;
        }
        if ([token hasPrefix:@"# branch.head "]) {
            NSString *head = [token substringFromIndex:@"# branch.head ".length];
            _branch = [head hasPrefix:@"(detached"] ? @"游离头指针" : head;
            continue;
        }
        if ([token hasPrefix:@"# branch.upstream "]) {
            _upstream = [token substringFromIndex:@"# branch.upstream ".length];
            NSRange slash = [_upstream rangeOfString:@"/"];
            _trackingRemote = slash.location == NSNotFound ? nil : [_upstream substringToIndex:slash.location];
            _trackingRef = slash.location == NSNotFound ? nil : [_upstream substringFromIndex:slash.location + 1];
            continue;
        }
        if ([token hasPrefix:@"# branch.ab "]) {
            NSString *rest = [token substringFromIndex:@"# branch.ab ".length];
            for (NSString *piece in [rest componentsSeparatedByString:@" "]) {
                if ([piece hasPrefix:@"+"]) {
                    _ahead = (unsigned long long)[piece substringFromIndex:1].longLongValue;
                } else if ([piece hasPrefix:@"-"]) {
                    _behind = (unsigned long long)[piece substringFromIndex:1].longLongValue;
                }
            }
            _trackingCountsKnown = YES;
            continue;
        }

        if ([token hasPrefix:@"? "]) {
            NSString *path = [token substringFromIndex:2];
            [changes addObject:[CAGitSnapshot changeWithPath:path subtitle:nil label:nil staged:NO untracked:YES status:'?' symbol:nil]];
            unstaged++;
            continue;
        }
        if ([token hasPrefix:@"! "]) {
            continue;
        }
        if ([token hasPrefix:@"1 "]) {
            NSArray<NSString *> *fields = [CAGitSnapshot fieldsFromLine:token expected:9];
            if (fields.count < 9) {
                continue;
            }
            NSString *xy = fields[1];
            NSString *path = fields[8];
            unichar x = xy.length > 0 ? [xy characterAtIndex:0] : ' ';
            unichar y = xy.length > 1 ? [xy characterAtIndex:1] : ' ';
            if (x != ' ') {
                [changes addObject:[CAGitSnapshot changeWithPath:path subtitle:nil label:nil staged:YES untracked:NO status:(char)x symbol:nil]];
                staged++;
            }
            if (y != ' ') {
                [changes addObject:[CAGitSnapshot changeWithPath:path subtitle:nil label:nil staged:NO untracked:NO status:(char)y symbol:nil]];
                unstaged++;
            }
            continue;
        }
        if ([token hasPrefix:@"2 "]) {
            NSArray<NSString *> *fields = [CAGitSnapshot fieldsFromLine:token expected:10];
            if (fields.count < 10) {
                continue;
            }
            NSString *xy = fields[1];
            NSString *path = fields[9];
            NSString *original = (index + 1 < tokens.count) ? tokens[index + 1] : @"";
            index += 1;
            unichar x = xy.length > 0 ? [xy characterAtIndex:0] : ' ';
            unichar y = xy.length > 1 ? [xy characterAtIndex:1] : ' ';
            if (x != ' ') {
                [changes addObject:[CAGitSnapshot changeWithPath:path subtitle:original label:nil staged:YES untracked:NO status:(char)x symbol:nil]];
                staged++;
            }
            if (y != ' ') {
                [changes addObject:[CAGitSnapshot changeWithPath:path subtitle:original label:nil staged:NO untracked:NO status:(char)y symbol:nil]];
                unstaged++;
            }
            continue;
        }
        if ([token hasPrefix:@"u "]) {
            NSArray<NSString *> *fields = [CAGitSnapshot fieldsFromLine:token expected:11];
            if (fields.count < 11) {
                continue;
            }
            NSMutableDictionary *change = [[CAGitSnapshot changeWithPath:fields[10] subtitle:nil label:nil staged:NO untracked:NO status:'U' symbol:nil] mutableCopy];
            change[kCAGitChangeConflictedKey] = @YES;
            change[kCAGitChangeLabelKey] = @"冲突";
            [changes addObject:change];
            conflicts = YES;
            unstaged++;
            continue;
        }
    }

    _changes = changes;
    _stagedCount = staged;
    _unstagedCount = unstaged;
    _hasConflicts = conflicts;
    _repository = YES;
    _branchSummary = [self computedBranchSummary];
}

/// 按 git porcelain v2 的固定字段数切分，最后一列（路径）允许含空格
+ (NSArray<NSString *> *)fieldsFromLine:(NSString *)line expected:(NSUInteger)count
{
    NSArray<NSString *> *all = [line componentsSeparatedByString:@" "];
    if (all.count <= count) {
        return all;
    }
    NSMutableArray *fields = [[all subarrayWithRange:NSMakeRange(0, count - 1)] mutableCopy];
    NSString *tail = [[all subarrayWithRange:NSMakeRange(count - 1, all.count - count + 1)] componentsJoinedByString:@" "];
    [fields addObject:tail];
    return fields;
}

+ (NSDictionary *)changeWithPath:(NSString *)path
                        subtitle:(NSString *)subtitle
                           label:(NSString *)label
                          staged:(BOOL)staged
                       untracked:(BOOL)untracked
                          status:(char)status
                          symbol:(NSString *)symbol
{
    NSString *resolvedLabel = label ?: [self labelForStatus:status untracked:untracked staged:staged];
    return @{
        kCAGitChangePathKey: path ?: @"",
        kCAGitChangeSubtitleKey: subtitle ?: [self relativeSubtitleForPath:path],
        kCAGitChangeLabelKey: resolvedLabel,
        kCAGitChangeSymbolKey: symbol ?: [self symbolForStatus:status untracked:untracked],
        kCAGitChangeTintKey: [self tintForStatus:status untracked:untracked],
        kCAGitChangeStagedKey: @(staged),
        kCAGitChangeUntrackedKey: @(untracked),
        kCAGitChangeConflictedKey: @(status == 'U'),
        kCAGitChangeAddedKey: @(status == 'A' || untracked),
        kCAGitChangeDeletedKey: @(status == 'D'),
        kCAGitChangeRenamedKey: @(status == 'R' || status == 'C'),
        kCAGitChangeModifiedKey: @(status == 'M' || status == 'T'),
        kCAGitChangeIndexStatusKey: @(status),
        kCAGitChangeWorktreeStatusKey: @(status),
    };
}

+ (NSString *)relativeSubtitleForPath:(NSString *)path
{
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (directory.length == 0 || [directory isEqualToString:@"."]) {
        return @"项目根目录";
    }
    return directory;
}

+ (NSString *)labelForStatus:(char)status untracked:(BOOL)untracked staged:(BOOL)staged
{
    if (untracked || status == '?') {
        return @"未跟踪";
    }
    switch (status) {
        case 'A':
            return staged ? @"已暂存" : @"新增";
        case 'M':
        case 'T':
            return staged ? @"已暂存" : @"已修改";
        case 'D':
            return staged ? @"已暂存删除" : @"已删除";
        case 'R':
            return @"重命名";
        case 'C':
            return @"已复制";
        case 'U':
            return @"冲突";
        default:
            return staged ? @"已暂存" : @"已修改";
    }
}

+ (NSString *)symbolForStatus:(char)status untracked:(BOOL)untracked
{
    if (untracked || status == '?') {
        return @"plus";
    }
    switch (status) {
        case 'A':
            return @"plus";
        case 'D':
            return @"minus";
        case 'R':
        case 'C':
            return @"arrow.right";
        case 'U':
            return @"exclamationmark";
        default:
            return @"pencil";
    }
}

+ (UIColor *)tintForStatus:(char)status untracked:(BOOL)untracked
{
    if (untracked || status == '?') {
        return UIColor.systemGreenColor;
    }
    switch (status) {
        case 'A':
            return UIColor.systemGreenColor;
        case 'D':
            return UIColor.systemRedColor;
        case 'U':
            return UIColor.systemRedColor;
        case 'R':
        case 'C':
            return UIColor.systemBlueColor;
        default:
            return UIColor.systemOrangeColor;
    }
}

- (NSString *)computedBranchSummary
{
    if (!_repository) {
        return @"没有可用的仓库";
    }
    NSString *branch = _branch.length > 0 ? _branch : @"unknown";
    if (!_trackingCountsKnown) {
        return branch;
    }
    if (_ahead == 0 && _behind == 0) {
        return [NSString stringWithFormat:@"%@ · 与远程一致", branch];
    }
    if (_behind == 0) {
        return [NSString stringWithFormat:@"%@ · 领先 %llu", branch, _ahead];
    }
    if (_ahead == 0) {
        return [NSString stringWithFormat:@"%@ · 落后 %llu", branch, _behind];
    }
    return [NSString stringWithFormat:@"%@ · 领先 %llu / 落后 %llu", branch, _ahead, _behind];
}

#pragma mark - 访问器

- (unsigned long long)ahead { return _ahead; }
- (void)setAhead:(id)arg1 { _ahead = [(NSNumber *)arg1 unsignedLongLongValue]; }

- (unsigned long long)behind { return _behind; }
- (void)setBehind:(id)arg1 { _behind = [(NSNumber *)arg1 unsignedLongLongValue]; }

- (NSString *)branch { return _branch ?: @"—"; }
- (void)setBranch:(id)arg1 { _branch = [(NSString *)arg1 copy]; }

- (NSString *)branchSummary { return _branchSummary ?: [self computedBranchSummary]; }
- (void)setBranchSummary:(id)arg1 { _branchSummary = [(NSString *)arg1 copy]; }

- (NSArray *)changes { return _changes ?: @[]; }
- (void)setChanges:(id)arg1 { _changes = [(NSArray *)arg1 copy]; }

- (NSString *)error { return _error; }
- (void)setError:(id)arg1 { _error = [(NSString *)arg1 copy]; }

- (bool)hasConflicts { return _hasConflicts; }
- (void)setHasConflicts:(id)arg1 { _hasConflicts = [(NSNumber *)arg1 boolValue]; }

- (bool)hasHead { return _hasHead; }
- (void)setHasHead:(id)arg1 { _hasHead = [(NSNumber *)arg1 boolValue]; }

- (NSDictionary *)remoteURLs { return _remoteURLs ?: @{}; }
- (void)setRemoteURLs:(id)arg1 { _remoteURLs = [(NSDictionary *)arg1 copy]; }

- (NSArray *)remotes { return _remotes ?: @[]; }
- (void)setRemotes:(id)arg1 { _remotes = [(NSArray *)arg1 copy]; }

- (bool)repository { return _repository; }
- (void)setRepository:(id)arg1 { _repository = [(NSNumber *)arg1 boolValue]; }

- (NSString *)repositoryRoot { return _repositoryRoot; }
- (void)setRepositoryRoot:(id)arg1 { _repositoryRoot = [(NSString *)arg1 copy]; }

- (unsigned long long)stagedCount { return _stagedCount; }
- (void)setStagedCount:(id)arg1 { _stagedCount = [(NSNumber *)arg1 unsignedLongLongValue]; }

- (bool)trackingCountsKnown { return _trackingCountsKnown; }
- (void)setTrackingCountsKnown:(id)arg1 { _trackingCountsKnown = [(NSNumber *)arg1 boolValue]; }

- (NSString *)trackingRef { return _trackingRef; }
- (void)setTrackingRef:(id)arg1 { _trackingRef = [(NSString *)arg1 copy]; }

- (NSString *)trackingRemote { return _trackingRemote; }
- (void)setTrackingRemote:(id)arg1 { _trackingRemote = [(NSString *)arg1 copy]; }

- (unsigned long long)unstagedCount { return _unstagedCount; }
- (void)setUnstagedCount:(id)arg1 { _unstagedCount = [(NSNumber *)arg1 unsignedLongLongValue]; }

- (NSString *)upstream { return _upstream; }
- (void)setUpstream:(id)arg1 { _upstream = [(NSString *)arg1 copy]; }

- (NSString *)userEmail { return _userEmail; }
- (void)setUserEmail:(id)arg1 { _userEmail = [(NSString *)arg1 copy]; }

- (NSString *)userName { return _userName; }
- (void)setUserName:(id)arg1 { _userName = [(NSString *)arg1 copy]; }

@end
