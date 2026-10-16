//
//  CAGitRepository.m — 本地 Git 仓库（用 /usr/bin/git 驱动，无 libgit2 依赖）
//
//  设计要点（对齐原包 ivar：_workspacePath/_repositoryRoot/_rootWaiters/_snapshotWaiters/_countWaiters）：
//    · 外部命令统一走工程内的 CAProcess（iOS SDK 无 NSTask），避免 fork
//    · 所有命令在私有串行队列上同步执行，回调回主线程（避免管道死锁与并发写仓库）
//    · 可执行文件按「越狱路径 → 托管运行时 → Helpers」顺序探测；都找不到时上层退化演示数据
//    · 凭据只用于单次 push/fetch/pull：把用户名口令拼进本次调用的 URL，不落盘
//
//  completion 约定（内部私有 block 形状，调用方按此实现）：
//    runArguments 系：void(^)(BOOL ok, NSString *output, NSInteger status)
//    readSnapshot：   void(^)(CAGitSnapshot *snapshot, NSError *error)
//    readDiff*：      void(^)(CAGitDiffResult *result, NSError *error) / void(^)(NSDictionary *stats, NSError *error)
//    stage 等变更：    void(^)(BOOL ok, NSString *message)
//

#import "CAGitRepository.h"
#import "CAGitSnapshot.h"
#import "CAGitDiffResult.h"
#import "CAProcess.h"
#import "CARuntimePaths.h"
#import "CACommon.h"

static const NSTimeInterval kCAGitDefaultTimeout = 25.0;   // 网络类命令另有更长超时
static const NSUInteger kCAGitDiffPreviewLimit = 400 * 1024;  // 预览文本上限（超出标记截断）

@interface CAGitRepository ()
{
    NSString *_workspacePath;
    NSString *_repositoryRoot;
    NSMutableArray *_rootWaiters;
    NSMutableArray *_snapshotWaiters;
    NSMutableArray *_countWaiters;
    dispatch_queue_t _workQueue;
    BOOL _hasChecksumDiff;   // 是否支持 --no-color（老版本 git 无该选项时降级）
}
@end

@implementation CAGitRepository

- (id)initWithWorkspacePath:(id)arg1
{
    if ((self = [super init])) {
        _workspacePath = [(NSString *)arg1 copy];
        _rootWaiters = [NSMutableArray array];
        _snapshotWaiters = [NSMutableArray array];
        _countWaiters = [NSMutableArray array];
        _workQueue = dispatch_queue_create("wiki.qaq.codexapp.git", DISPATCH_QUEUE_SERIAL);
        _hasChecksumDiff = YES;
    }
    return self;
}

#pragma mark - 基本访问器

- (NSString *)workspacePath { return _workspacePath; }
- (void)setWorkspacePath:(id)arg1 { _workspacePath = [(NSString *)arg1 copy]; }

- (NSString *)repositoryRoot { return _repositoryRoot; }
- (void)setRepositoryRoot:(id)arg1 { _repositoryRoot = [(NSString *)arg1 copy]; }

- (NSMutableArray *)rootWaiters { return _rootWaiters; }
- (void)setRootWaiters:(id)arg1 { _rootWaiters = [arg1 isKindOfClass:NSMutableArray.class] ? (NSMutableArray *)arg1 : [NSMutableArray array]; }

- (NSMutableArray *)snapshotWaiters { return _snapshotWaiters; }
- (void)setSnapshotWaiters:(id)arg1 { _snapshotWaiters = [arg1 isKindOfClass:NSMutableArray.class] ? (NSMutableArray *)arg1 : [NSMutableArray array]; }

- (NSMutableArray *)countWaiters { return _countWaiters; }
- (void)setCountWaiters:(id)arg1 { _countWaiters = [arg1 isKindOfClass:NSMutableArray.class] ? (NSMutableArray *)arg1 : [NSMutableArray array]; }

- (double)operationTimeout { return kCAGitDefaultTimeout; }

- (id)statusArguments
{
    // porcelain=v2 才能同时拿到 branch.ab（领先/落后）与逐文件 XY 状态
    return @[ @"status", @"--porcelain=v2", @"--branch", @"-z", @"--untracked-files=all" ];
}

#pragma mark - 可执行文件 / 环境

- (id)gitExecutableForEnvironment:(id)arg1
{
    NSDictionary *environment = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];

    NSString *explicit = environment[@"CA_GIT_EXECUTABLE"];
    if (explicit.length > 0) {
        [candidates addObject:explicit];
    }
    [candidates addObjectsFromArray:@[
        @"/var/jb/usr/bin/git",
        @"/usr/bin/git",
        @"/var/jb/usr/local/bin/git",
        @"/usr/local/bin/git",
        @"/opt/procursus/usr/bin/git",
    ]];

    // 托管运行时：RuntimeDownloads/<runtime_id>/bin/git
    NSString *runtimeRoot = CARuntimePaths.runtimeDownloadsDirectory;
    NSArray<NSString *> *runtimeIDs = @[ @"CoreTools", @"coretools", @"Git", @"git", @"Tools", @"tools" ];
    for (NSString *identifier in runtimeIDs) {
        [candidates addObject:[runtimeRoot stringByAppendingPathComponent:[identifier stringByAppendingPathComponent:@"bin/git"]]];
        [candidates addObject:[runtimeRoot stringByAppendingPathComponent:[identifier stringByAppendingPathComponent:@"git"]]];
    }
    [candidates addObject:[CARuntimePaths.documentsHelpersDirectory stringByAppendingPathComponent:@"git"]];

    // 兜底：扫一层运行时子目录
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *child in [manager contentsOfDirectoryAtPath:runtimeRoot error:NULL] ?: @[]) {
        [candidates addObject:[[runtimeRoot stringByAppendingPathComponent:child] stringByAppendingPathComponent:@"bin/git"]];
    }

    for (NSString *candidate in candidates) {
        if (candidate.length > 0 && [manager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return @"";
}

- (id)gitEnvironment
{
    NSMutableDictionary<NSString *, NSString *> *environment = [NSProcessInfo.processInfo.environment mutableCopy] ?: [NSMutableDictionary dictionary];
    // 非交互：禁止终端提示、分页器与彩色的控制字符
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    environment[@"GIT_PAGER"] = @"cat";
    environment[@"GIT_CONFIG_NOSYSTEM"] = @"1";
    environment[@"GIT_ASKPASS"] = @"/bin/echo";
    environment[@"LC_ALL"] = @"zh_CN.UTF-8";
    environment[@"LANG"] = @"zh_CN.UTF-8";
    if (environment[@"GIT_SSL_CAINFO"] == nil) {
        NSString *caPath = CARuntimePaths.bundledCACertPath;
        if ([NSFileManager.defaultManager fileExistsAtPath:caPath]) {
            environment[@"GIT_SSL_CAINFO"] = caPath;
        }
    }
    return environment;
}

#pragma mark - 同步执行内核

/// 在私有队列上同步执行一条 git 命令；返回是否成功
- (BOOL)ca_runSync:(NSArray<NSString *> *)arguments
       environment:(NSDictionary<NSString *, NSString *> *)environment
            output:(NSString *__autoreleasing *)output
            status:(NSInteger *)status
           timeout:(NSTimeInterval)timeout
{
    NSString *executable = [self gitExecutableForEnvironment:environment];
    if (executable.length == 0) {
        if (output) *output = @"没有找到可用的 git 可执行文件";
        if (status) *status = -1;
        return NO;
    }

    CAProcess *task = [[CAProcess alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];

    NSMutableArray<NSString *> *fullArguments = [NSMutableArray array];
    NSString *root = _repositoryRoot.length > 0 ? _repositoryRoot : _workspacePath;
    if (root.length > 0) {
        [fullArguments addObject:@"-C"];
        [fullArguments addObject:root];
    }
    [fullArguments addObjectsFromArray:arguments];
    task.arguments = fullArguments;
    task.environment = environment ?: [self gitEnvironment];
    if (root.length > 0) {
        task.currentDirectoryURL = [NSURL fileURLWithPath:root isDirectory:YES];
    }

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (output) *output = launchError.localizedDescription ?: @"启动 git 失败";
        if (status) *status = -1;
        return NO;
    }

    // 两条管道并发抽干：单线程顺序读会在 64KB 缓冲区写满时互锁
    __block NSData *stdoutData = nil;
    __block NSData *stderrData = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t drainQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_group_async(group, drainQueue, ^{
        stdoutData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    });
    dispatch_group_async(group, drainQueue, ^{
        stderrData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
    });

    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
        [task terminate];
        if (output) *output = @"git 命令超时";
        if (status) *status = -1;
        return NO;
    }

    NSInteger exitStatus = (NSInteger)[task waitUntilExitWithTimeout:5.0];
    NSString *stdoutText = [[NSString alloc] initWithData:stdoutData ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
    NSString *stderrText = [[NSString alloc] initWithData:stderrData ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";

    if (status) *status = exitStatus;
    if (output) {
        *output = stderrText.length > 0 ? stderrText : stdoutText;
    }
    return exitStatus == 0;
}

#pragma mark - 异步执行入口

- (void)runArguments:(id)arg1 completion:(id)arg2
{
    // outputFile: 在生成头文件里是非空形参，传空串表示「不落盘」（实现里按 length>0 判断）
    [self runArguments:arg1 environment:[self gitEnvironment] outputFile:@"" completion:arg2];
}

- (void)runArguments:(id)arg1 environment:(id)arg2 completion:(id)arg3
{
    [self runArguments:arg1 environment:arg2 outputFile:@"" completion:arg3];
}

- (void)runArguments:(id)arg1 environment:(id)arg2 outputFile:(id)arg3 completion:(id)arg4
{
    NSArray<NSString *> *arguments = [arg1 isKindOfClass:NSArray.class] ? (NSArray *)arg1 : @[];
    NSDictionary<NSString *, NSString *> *environment = [arg2 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg2 : [self gitEnvironment];
    NSString *outputFile = [arg3 isKindOfClass:NSString.class] ? (NSString *)arg3 : nil;
    void (^completion)(BOOL, NSString *, NSInteger) = arg4;

    dispatch_async(_workQueue, ^{
        NSString *output = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:arguments
                       environment:environment
                            output:&output
                            status:&status
                           timeout:[self operationTimeout]];
        if (outputFile.length > 0) {
            [[output dataUsingEncoding:NSUTF8StringEncoding] writeToFile:outputFile atomically:YES];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(ok, output ?: @"", status);
            });
        }
    });
}

#pragma mark - 仓库定位

- (void)ensureRoot:(id)arg1
{
    void (^completion)(NSString *, NSError *) = arg1;
    dispatch_async(_workQueue, ^{
        NSString *output = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:@[ @"rev-parse", @"--show-toplevel" ]
                       environment:[self gitEnvironment]
                            output:&output
                            status:&status
                           timeout:10.0];
        NSString *root = ok ? [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
        if (ok && root.length > 0) {
            self.repositoryRoot = root;
        }
        NSError *error = ok ? nil : [NSError errorWithDomain:@"CAGitRepository"
                                                       code:status
                                                   userInfo:@{ NSLocalizedDescriptionKey: output ?: @"不是 Git 仓库" }];
        NSMutableArray *waiters = [_rootWaiters mutableCopy] ?: [NSMutableArray array];
        [_rootWaiters removeAllObjects];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(root, error);
            });
        }
        for (void (^waiter)(NSString *, NSError *) in waiters) {
            waiter(root, error);
        }
    });
}

#pragma mark - 读取

- (void)readSnapshot:(id)arg1
{
    void (^completion)(CAGitSnapshot *, NSError *) = arg1;
    dispatch_async(_workQueue, ^{
        NSDictionary<NSString *, NSString *> *environment = [self gitEnvironment];

        NSString *statusOutput = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:[self statusArguments]
                       environment:environment
                            output:&statusOutput
                            status:&status
                           timeout:20.0];
        if (!ok) {
            // -C 指向的目标不是仓库：跑一次 rev-parse 判断，再退化成「非仓库」快照
            NSString *probe = @"";
            NSInteger probeStatus = -1;
            BOOL isRepo = [self ca_runSync:@[ @"rev-parse", @"--is-inside-work-tree" ]
                               environment:environment
                                    output:&probe
                                    status:&probeStatus
                                   timeout:8.0];
            CAGitSnapshot *snapshot = [CAGitSnapshot emptySnapshotWithError:isRepo ? nil : (statusOutput.length > 0 ? statusOutput : @"不是 Git 仓库")];
            snapshot.repository = @(isRepo);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(snapshot, nil);
            });
            return;
        }

        CAGitSnapshot *snapshot = [CAGitSnapshot snapshotFromStatusOutput:statusOutput];

        NSString *rootOutput = @"";
        NSInteger rootStatus = -1;
        if ([self ca_runSync:@[ @"rev-parse", @"--show-toplevel" ] environment:environment output:&rootOutput status:&rootStatus timeout:8.0]) {
            NSString *root = [rootOutput stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (root.length > 0) {
                self.repositoryRoot = root;
            }
        }
        snapshot.repositoryRoot = self.repositoryRoot ?: self.workspacePath;

        // 远程列表 + 地址
        NSString *remoteOutput = @"";
        NSInteger remoteStatus = -1;
        if ([self ca_runSync:@[ @"remote", @"-v" ] environment:environment output:&remoteOutput status:&remoteStatus timeout:8.0]) {
            NSMutableArray<NSString *> *remotes = [NSMutableArray array];
            NSMutableDictionary<NSString *, NSString *> *urls = [NSMutableDictionary dictionary];
            for (NSString *line in [remoteOutput componentsSeparatedByString:@"\n"]) {
                NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 2) {
                    continue;
                }
                NSString *name = [parts[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                NSString *rest = parts[1];
                if (![rest hasSuffix:@"(fetch)"]) {
                    continue;   // 同一远程的 push 行忽略，取 fetch 行
                }
                NSString *url = [rest stringByReplacingOccurrencesOfString:@"(fetch)" withString:@""];
                url = [url stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if (name.length > 0 && url.length > 0) {
                    if (![remotes containsObject:name]) {
                        [remotes addObject:name];
                    }
                    urls[name] = url;
                }
            }
            snapshot.remotes = remotes;
            snapshot.remoteURLs = urls;
        }

        // 提交身份（用于「需要先配置身份」的提交前置检查）
        NSString *nameOutput = @"";
        NSInteger nameStatus = -1;
        if ([self ca_runSync:@[ @"config", @"--get", @"user.name" ] environment:environment output:&nameOutput status:&nameStatus timeout:8.0]) {
            snapshot.userName = [nameOutput stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }
        NSString *emailOutput = @"";
        NSInteger emailStatus = -1;
        if ([self ca_runSync:@[ @"config", @"--get", @"user.email" ] environment:environment output:&emailOutput status:&emailStatus timeout:8.0]) {
            snapshot.userEmail = [emailOutput stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        }

        NSMutableArray *waiters = [self snapshotWaiters].mutableCopy ?: [NSMutableArray array];
        [self.snapshotWaiters removeAllObjects];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(snapshot, nil);
            for (void (^waiter)(CAGitSnapshot *, NSError *) in waiters) {
                waiter(snapshot, nil);
            }
        });
    });
}

- (void)readChangeCount:(id)arg1
{
    void (^completion)(NSUInteger, NSError *) = arg1;
    dispatch_async(_workQueue, ^{
        NSString *output = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:@[ @"status", @"--porcelain" ]
                       environment:[self gitEnvironment]
                            output:&output
                            status:&status
                           timeout:20.0];
        NSUInteger count = 0;
        if (ok) {
            for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
                if (line.length > 0) {
                    count += 1;
                }
            }
        }
        NSMutableArray *waiters = [self countWaiters].mutableCopy ?: [NSMutableArray array];
        [self.countWaiters removeAllObjects];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(count, ok ? nil : [NSError errorWithDomain:@"CAGitRepository" code:status userInfo:nil]);
            for (void (^waiter)(NSUInteger, NSError *) in waiters) {
                waiter(count, nil);
            }
        });
    });
}

- (void)readLocalBranches:(id)arg1
{
    void (^completion)(NSArray<NSString *> *, NSString *) = arg1;
    dispatch_async(_workQueue, ^{
        NSString *output = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:@[ @"for-each-ref", @"--format=%(refname:short)", @"refs/heads" ]
                       environment:[self gitEnvironment]
                            output:&output
                            status:&status
                           timeout:10.0];
        NSMutableArray<NSString *> *branches = [NSMutableArray array];
        if (ok) {
            for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
                NSString *name = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (name.length > 0) {
                    [branches addObject:name];
                }
            }
        }
        if (branches.count == 0) {
            [branches addObject:@"master"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(branches, ok ? nil : output);
        });
    });
}

- (void)readDiffStats:(id)arg1
{
    void (^completion)(NSDictionary<NSString *, NSDictionary *> *, NSError *) = arg1;
    dispatch_async(_workQueue, ^{
        NSDictionary<NSString *, NSString *> *environment = [self gitEnvironment];
        NSMutableDictionary<NSString *, NSDictionary *> *stats = [NSMutableDictionary dictionary];
        for (NSNumber *staged in @[ @NO, @YES ]) {
            NSArray *arguments = staged.boolValue
                ? @[ @"diff", @"--cached", @"--numstat", @"--no-color" ]
                : @[ @"diff", @"--numstat", @"--no-color" ];
            NSString *output = @"";
            NSInteger status = -1;
            if (![self ca_runSync:arguments environment:environment output:&output status:&status timeout:20.0]) {
                continue;
            }
            for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
                NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 3) {
                    continue;
                }
                NSString *path = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"\t"];
                stats[path] = @{
                    @"add": @(parts[0].integerValue),
                    @"del": @(parts[1].integerValue),
                    @"staged": staged,
                };
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(stats, nil);
        });
    });
}

- (void)readDiffForChange:(id)arg1 staged:(id)arg2 completion:(id)arg3
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : @{};
    BOOL staged = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    void (^completion)(CAGitDiffResult *, NSError *) = arg3;

    dispatch_async(_workQueue, ^{
        NSString *path = change[kCAGitChangePathKey] ?: @"";
        BOOL untracked = [change[kCAGitChangeUntrackedKey] boolValue];
        NSString *root = self.repositoryRoot ?: self.workspacePath ?: @"";
        NSString *absolute = path.length > 0 ? [root stringByAppendingPathComponent:path] : root;

        NSArray<NSString *> *arguments;
        if (untracked && !staged) {
            // 未跟踪文件没有 HEAD 版本：用 --no-index 对着 /dev/null 生成新增 diff
            arguments = @[ @"diff", @"--no-color", @"--no-index", @"--", @"/dev/null", absolute ];
        } else if (staged) {
            arguments = @[ @"diff", @"--no-color", @"--cached", @"--", path ];
        } else {
            arguments = @[ @"diff", @"--no-color", @"--", path ];
        }

        NSString *output = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:arguments
                       environment:[self gitEnvironment]
                            output:&output
                            status:&status
                           timeout:25.0];

        CAGitDiffResult *result = [[CAGitDiffResult alloc] init];
        result.status = @((int)status);
        NSString *text = ok ? output : (output.length > 0 ? output : @"（没有可显示的差异）");
        if (text.length > kCAGitDiffPreviewLimit) {
            result.truncated = @YES;
            text = [[text substringToIndex:kCAGitDiffPreviewLimit] stringByAppendingString:@"\n…（差异过大，已截断）"];
        }
        result.preview = text;

        // 完整 diff 落临时文件，供「分享」按钮使用
        NSString *tmpName = [NSString stringWithFormat:@"codex-git-diff-%@.txt", NSUUID.UUID.UUIDString];
        NSString *tmpPath = [CARuntimePaths.tmpDirectory stringByAppendingPathComponent:tmpName];
        if ([text writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
            result.fileURL = [NSURL fileURLWithPath:tmpPath];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result, ok ? nil : [NSError errorWithDomain:@"CAGitRepository" code:status userInfo:nil]);
        });
    });
}

- (id)matchingChange:(id)arg1 snapshot:(id)arg2
{
    NSDictionary *target = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    CAGitSnapshot *snapshot = [arg2 isKindOfClass:CAGitSnapshot.class] ? (CAGitSnapshot *)arg2 : nil;
    if (target == nil || snapshot == nil) {
        return nil;
    }
    BOOL staged = [target[kCAGitChangeStagedKey] boolValue];
    NSString *path = target[kCAGitChangePathKey];
    for (NSDictionary *change in snapshot.changes) {
        if ([change[kCAGitChangePathKey] isEqualToString:path] && [change[kCAGitChangeStagedKey] boolValue] == staged) {
            return change;
        }
    }
    return nil;
}

#pragma mark - 变更操作

- (void)stageChange:(id)arg1 completion:(id)arg2
{
    [self ca_performChangeOperation:arg1
                          arguments:^NSArray<NSString *> *(NSDictionary *change) {
        return @[ @"add", @"-A", @"--", change[kCAGitChangePathKey] ?: @"." ];
    }
                         completion:arg2
                         busyPrefix:@"暂存"];
}

- (void)unstageChange:(id)arg1 completion:(id)arg2
{
    [self ca_performChangeOperation:arg1
                          arguments:^NSArray<NSString *> *(NSDictionary *change) {
        return @[ @"restore", @"--staged", @"--", change[kCAGitChangePathKey] ?: @"." ];
    }
                         completion:arg2
                         busyPrefix:@"取消暂存"];
}

- (void)discardChange:(id)arg1 completion:(id)arg2
{
    [self ca_performChangeOperation:arg1
                          arguments:^NSArray<NSString *> *(NSDictionary *change) {
        return @[ @"restore", @"--source=HEAD", @"--staged", @"--worktree", @"--", change[kCAGitChangePathKey] ?: @"." ];
    }
                         completion:arg2
                         busyPrefix:@"还原"];
}

- (void)deleteNewChange:(id)arg1 completion:(id)arg2
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : @{};
    void (^completion)(BOOL, NSString *) = arg2;
    NSString *path = change[kCAGitChangePathKey] ?: @"";
    dispatch_async(_workQueue, ^{
        NSString *root = self.repositoryRoot ?: self.workspacePath ?: @"";
        NSString *absolute = [root stringByAppendingPathComponent:path];
        NSError *error = nil;
        BOOL ok = path.length > 0 && [NSFileManager.defaultManager removeItemAtPath:absolute error:&error];
        NSString *message = ok ? [NSString stringWithFormat:@"已删除未跟踪文件 %@", path] : (error.localizedDescription ?: @"删除失败");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, message);
        });
    });
}

- (void)discardTrackedChanges:(id)arg1
{
    void (^completion)(BOOL, NSString *) = arg1;
    [self runArguments:@[ @"restore", @"--source=HEAD", @"--staged", @"--worktree", @"--", @"." ]
           completion:^(BOOL ok, NSString *output, NSInteger status) {
        if (completion) {
            completion(ok, ok ? @"已还原全部已跟踪文件" : (output.length > 0 ? output : @"还原失败"));
        }
    }];
}

- (void)commitMessage:(id)arg1 stageAll:(id)arg2 completion:(id)arg3
{
    NSString *message = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    BOOL stageAll = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    void (^completion)(BOOL, NSString *) = arg3;

    if (message.length == 0) {
        if (completion) completion(NO, @"提交信息不能为空");
        return;
    }

    NSMutableArray<NSArray<NSString *> *> *commands = [NSMutableArray array];
    if (stageAll) {
        [commands addObject:@[ @"add", @"-A" ]];
    }
    [commands addObject:@[ @"commit", @"-m", message ]];

    dispatch_async(_workQueue, ^{
        NSString *lastOutput = @"";
        BOOL ok = YES;
        for (NSArray<NSString *> *arguments in commands) {
            NSInteger status = -1;
            NSString *output = @"";
            ok = [self ca_runSync:arguments environment:[self gitEnvironment] output:&output status:&status timeout:30.0];
            lastOutput = output ?: @"";
            if (!ok) {
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, ok ? @"提交完成" : (lastOutput.length > 0 ? lastOutput : @"提交失败"));
        });
    });
}

- (void)setUserName:(id)arg1 email:(id)arg2 completion:(id)arg3
{
    NSString *name = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    NSString *email = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : @"";
    void (^completion)(BOOL, NSString *) = arg3;
    dispatch_async(_workQueue, ^{
        NSDictionary<NSString *, NSString *> *environment = [self gitEnvironment];
        BOOL ok = YES;
        NSString *last = @"";
        if (name.length > 0) {
            NSInteger status = -1;
            ok = [self ca_runSync:@[ @"config", @"user.name", name ] environment:environment output:&last status:&status timeout:8.0];
        }
        if (ok && email.length > 0) {
            NSInteger status = -1;
            ok = [self ca_runSync:@[ @"config", @"user.email", email ] environment:environment output:&last status:&status timeout:8.0];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, ok ? @"已保存提交身份" : (last.length > 0 ? last : @"保存失败"));
        });
    });
}

- (void)switchToBranch:(id)arg1 create:(id)arg2 completion:(id)arg3
{
    NSString *branch = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"";
    BOOL create = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    void (^completion)(BOOL, NSString *) = arg3;
    if (branch.length == 0) {
        if (completion) completion(NO, @"分支名不能为空");
        return;
    }
    NSArray<NSString *> *arguments = create ? @[ @"switch", @"-c", branch ] : @[ @"switch", branch ];
    [self runArguments:arguments completion:^(BOOL ok, NSString *output, NSInteger status) {
        if (completion) {
            completion(ok, ok ? [NSString stringWithFormat:create ? @"已创建并切换到 %@" : @"已切换到 %@", branch]
                             : (output.length > 0 ? output : @"切换分支失败"));
        }
    }];
}

- (void)configureRemote:(id)arg1 URL:(id)arg2 completion:(id)arg3
{
    NSString *name = [arg1 isKindOfClass:NSString.class] && [(NSString *)arg1 length] > 0 ? (NSString *)arg1 : @"origin";
    NSString *url = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : @"";
    void (^completion)(BOOL, NSString *) = arg3;
    if (url.length == 0) {
        if (completion) completion(NO, @"远程地址不能为空");
        return;
    }

    dispatch_async(_workQueue, ^{
        NSDictionary<NSString *, NSString *> *environment = [self gitEnvironment];
        NSString *existing = @"";
        NSInteger status = -1;
        BOOL hasRemote = [self ca_runSync:@[ @"remote", @"get-url", name ] environment:environment output:&existing status:&status timeout:8.0];
        NSArray<NSString *> *arguments = hasRemote ? @[ @"remote", @"set-url", name, url ]
                                                   : @[ @"remote", @"add", name, url ];
        NSString *output = @"";
        NSInteger opStatus = -1;
        BOOL ok = [self ca_runSync:arguments environment:environment output:&output status:&opStatus timeout:12.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(ok, ok ? [NSString stringWithFormat:@"已保存远程 %@", name]
                                 : (output.length > 0 ? output : @"保存远程失败"));
            }
        });
    });
}

#pragma mark - 网络操作

- (void)remoteEnvironment:(id)arg1 push:(id)arg2 username:(id)arg3 token:(id)arg4 completion:(id)arg5
{
    NSString *remoteName = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"origin";
    BOOL push = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    NSString *username = [arg3 isKindOfClass:NSString.class] ? (NSString *)arg3 : nil;
    NSString *token = [arg4 isKindOfClass:NSString.class] ? (NSString *)arg4 : nil;
    void (^completion)(NSDictionary<NSString *, NSString *> *, NSString *) = arg5;

    dispatch_async(_workQueue, ^{
        NSDictionary<NSString *, NSString *> *environment = [self gitEnvironment];
        NSString *output = @"";
        NSInteger status = -1;
        BOOL ok = [self ca_runSync:(push ? @[ @"remote", @"get-url", @"--push", remoteName ] : @[ @"remote", @"get-url", remoteName ])
                       environment:environment
                            output:&output
                            status:&status
                           timeout:8.0];
        NSString *url = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

        NSMutableDictionary<NSString *, NSString *> *merged = [environment mutableCopy];
        merged[@"GIT_TERMINAL_PROMPT"] = @"0";
        merged[@"GIT_ASKPASS"] = @"/bin/echo";

        NSString *effectiveURL = url;
        if (ok && [url hasPrefix:@"https://"] && token.length > 0) {
            // 单次调用内联凭据：不写入远端配置，不进磁盘
            NSString *user = username.length > 0 ? username : @"oauth2";
            NSString *escapedUser = [user stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLUserAllowedCharacterSet] ?: user;
            NSString *escapedToken = [token stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPasswordAllowedCharacterSet] ?: token;
            effectiveURL = [NSString stringWithFormat:@"https://%@:%@@%@", escapedUser, escapedToken, [url substringFromIndex:@"https://".length]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(merged, ok ? effectiveURL : nil);
        });
    });
}

- (void)fetchFromRemote:(id)arg1 username:(id)arg2 token:(id)arg3 completion:(id)arg4
{
    [self ca_performRemoteOperation:@"获取"
                             remote:arg1
                             branch:nil
                           username:arg2
                              token:arg3
                         completion:arg4
                               push:NO];
}

- (void)pullFromRemote:(id)arg1 branch:(id)arg2 username:(id)arg3 token:(id)arg4 completion:(id)arg5
{
    [self ca_performRemoteOperation:@"拉取"
                             remote:arg1
                             branch:arg2
                           username:arg3
                              token:arg4
                         completion:arg5
                               push:NO];
}

- (void)pushToRemote:(id)arg1 branch:(id)arg2 remoteRef:(id)arg3 username:(id)arg4 token:(id)arg5 completion:(id)arg6
{
    NSString *remoteName = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : @"origin";
    NSString *branch = [arg2 isKindOfClass:NSString.class] ? (NSString *)arg2 : @"";
    NSString *remoteRef = [arg3 isKindOfClass:NSString.class] ? (NSString *)arg3 : branch;
    NSString *username = [arg4 isKindOfClass:NSString.class] ? (NSString *)arg4 : nil;
    NSString *token = [arg5 isKindOfClass:NSString.class] ? (NSString *)arg5 : nil;
    void (^completion)(BOOL, NSString *) = arg6;

    [self remoteEnvironment:remoteName push:@YES username:username token:token completion:^(NSDictionary<NSString *, NSString *> *environment, NSString *url) {
        dispatch_async(self->_workQueue, ^{
            NSString *spec = (branch.length > 0 && remoteRef.length > 0)
                ? [NSString stringWithFormat:@"%@:%@", branch, remoteRef]
                : (branch.length > 0 ? branch : @"HEAD");
            NSString *target = url.length > 0 ? url : remoteName;
            NSInteger status = -1;
            NSString *output = @"";
            BOOL ok = [self ca_runSync:@[ @"push", target, spec ]
                           environment:environment
                                output:&output
                                status:&status
                               timeout:120.0];
            if (!ok && [output containsString:@"has no upstream branch"]) {
                // 首次推送：补上 --set-upstream
                output = @"";
                status = -1;
                ok = [self ca_runSync:@[ @"push", @"--set-upstream", target, spec ]
                          environment:environment
                               output:&output
                               status:&status
                              timeout:120.0];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(ok, ok ? [NSString stringWithFormat:@"已推送到 %@", remoteName]
                                     : (output.length > 0 ? output : @"推送失败"));
                }
            });
        });
    }];
}

#pragma mark - 私有

/// 单文件变更操作（暂存/取消暂存/还原）的统一外壳
- (void)ca_performChangeOperation:(id)arg1
                        arguments:(NSArray<NSString *> *(^)(NSDictionary *change))argumentsBuilder
                       completion:(id)arg2
                       busyPrefix:(NSString *)prefix
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : @{};
    void (^completion)(BOOL, NSString *) = arg2;
    NSArray<NSString *> *arguments = argumentsBuilder ? argumentsBuilder(change) : nil;
    if (arguments.count == 0) {
        if (completion) completion(NO, @"缺少目标文件");
        return;
    }
    [self runArguments:arguments completion:^(BOOL ok, NSString *output, NSInteger status) {
        if (completion) {
            NSString *path = change[kCAGitChangePathKey] ?: @"";
            completion(ok, ok ? [NSString stringWithFormat:@"%@ %@", prefix, path.lastPathComponent]
                             : (output.length > 0 ? output : [NSString stringWithFormat:@"%@失败", prefix]));
        }
    }];
}

/// 远程命令统一外壳（fetch / pull）
- (void)ca_performRemoteOperation:(NSString *)title
                           remote:(id)remoteArgument
                           branch:(id)branchArgument
                         username:(id)usernameArgument
                            token:(id)tokenArgument
                       completion:(id)completionArgument
                             push:(BOOL)push
{
    NSString *remoteName = [remoteArgument isKindOfClass:NSString.class] && [(NSString *)remoteArgument length] > 0 ? (NSString *)remoteArgument : @"origin";
    NSString *branch = [branchArgument isKindOfClass:NSString.class] ? (NSString *)branchArgument : nil;
    NSString *username = [usernameArgument isKindOfClass:NSString.class] ? (NSString *)usernameArgument : nil;
    NSString *token = [tokenArgument isKindOfClass:NSString.class] ? (NSString *)tokenArgument : nil;
    void (^completion)(BOOL, NSString *) = completionArgument;

    [self remoteEnvironment:remoteName push:@(push) username:username token:token completion:^(NSDictionary<NSString *, NSString *> *environment, NSString *url) {
        dispatch_async(self->_workQueue, ^{
            NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:[title isEqualToString:@"拉取"] ? @"pull" : @"fetch"];
            [arguments addObject:(url.length > 0 ? url : remoteName)];
            if (branch.length > 0) {
                [arguments addObject:branch];
            }
            NSInteger status = -1;
            NSString *output = @"";
            BOOL ok = [self ca_runSync:arguments
                           environment:environment
                                output:&output
                                status:&status
                               timeout:120.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    if (ok) {
                        // 去掉 URL 中的凭据再展示
                        NSString *safeOutput = [output stringByReplacingOccurrencesOfString:token ?: @"" withString:@"<redacted>"];
                        completion(YES, [NSString stringWithFormat:@"%@完成\n%@", title, safeOutput]);
                    } else {
                        completion(NO, output.length > 0 ? output : [NSString stringWithFormat:@"%@失败", title]);
                    }
                }
            });
        });
    }];
}

@end
