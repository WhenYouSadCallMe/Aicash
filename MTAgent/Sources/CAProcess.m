//
//  CAProcess.m — posix_spawn 实现（NSTask 替代）
//

#import "CAProcess.h"
#import "CALogger.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>
#import <fcntl.h>

extern char **environ;

@interface CAProcess ()
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) int status;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL launched;
@property (nonatomic, assign) BOOL reaped;
@property (nonatomic, strong) dispatch_semaphore_t exitSemaphore;
@end

@implementation CAProcess

- (instancetype)init
{
    if ((self = [super init])) {
        _pid = -1;
        _status = 0;
        _exitSemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (pid_t)processIdentifier { return self.pid; }
- (int)terminationStatus { return self.status; }
- (BOOL)isRunning { return self.running; }
- (BOOL)isLaunched { return self.launched; }

#pragma mark - 启动

- (BOOL)launchAndReturnError:(NSError **)error
{
    if (self.launched) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Process" code:409
                                            userInfo:@{ NSLocalizedDescriptionKey: @"process already launched" }];
        return NO;
    }
    NSString *executable = self.executableURL.path ?: self.executableURL.absoluteString;
    if (!executable.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Process" code:400
                                            userInfo:@{ NSLocalizedDescriptionKey: @"missing executable" }];
        return NO;
    }

    // 工作目录：优先用 posix_spawn_file_actions_addchdir_np（iOS 16+/macOS 10.15+）；
    // 不可用时用 /bin/sh -c 'cd "$1" && shift && exec "$@"' 包装，保证子进程 cwd 正确。
    NSMutableArray<NSString *> *argvList = [NSMutableArray array];
    // The iPhoneOS SDK used by this target does not expose
    // posix_spawn_file_actions_addchdir_np, so always use the wrapper when a
    // working directory is requested. This keeps cwd behavior consistent on
    // both iOS 15 and newer runtimes.
    BOOL useShellWrapper = self.currentDirectoryURL.path.length > 0;
    if (useShellWrapper) {
        [argvList addObject:@"/bin/sh"];
        [argvList addObject:@"-c"];
        [argvList addObject:@"cd \"$1\" && shift && exec \"$@\""];
        [argvList addObject:@"sh"];
        [argvList addObject:self.currentDirectoryURL.path];
    }
    [argvList addObject:executable];
    [argvList addObjectsFromArray:self.arguments ?: @[]];

    char **argv = calloc(argvList.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvList.count; i++) argv[i] = strdup(argvList[i].UTF8String);
    argv[argvList.count] = NULL;

    NSDictionary<NSString *, NSString *> *environment = self.environment ?: NSProcessInfo.processInfo.environment;
    char **envp = calloc(environment.count + 1, sizeof(char *));
    __block NSUInteger envIndex = 0;
    [environment enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        envp[envIndex++] = strdup([[NSString stringWithFormat:@"%@=%@", key, value] UTF8String]);
    }];
    envp[envIndex] = NULL;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    NSPipe *stdinPipe  = [self.standardInput isKindOfClass:NSPipe.class]  ? self.standardInput  : nil;
    NSPipe *stdoutPipe = [self.standardOutput isKindOfClass:NSPipe.class] ? self.standardOutput : nil;
    NSPipe *stderrPipe = [self.standardError isKindOfClass:NSPipe.class]  ? self.standardError  : nil;

    if (stdinPipe)  posix_spawn_file_actions_adddup2(&actions, stdinPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO);
    if (stdoutPipe) posix_spawn_file_actions_adddup2(&actions, stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);
    if (stderrPipe) posix_spawn_file_actions_adddup2(&actions, stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO);
    // 说明：posix_spawn_file_actions_addchdir_np 在 iOS SDK 中不可用（macOS 专属），
    // 需要 chdir 的场景统一由上面的 /bin/sh 包装实现（useShellWrapper 分支）。

    // When a working directory is requested on SDKs without the chdir file
    // action, the shell wrapper is the actual process to spawn. The original
    // executable remains argv[4], after the wrapper has changed directory.
    NSString *spawnPath = useShellWrapper ? @"/bin/sh" : executable;
    pid_t pid = -1;
    int rc = posix_spawn(&pid, spawnPath.fileSystemRepresentation, &actions, NULL, argv, envp);

    posix_spawn_file_actions_destroy(&actions);
    for (NSUInteger i = 0; i <= argvList.count; i++) if (argv[i]) free(argv[i]);
    for (NSUInteger i = 0; i <= envIndex; i++) if (envp[i]) free(envp[i]);
    free(argv);
    free(envp);

    if (rc != 0) {
        CALog(CALogLevelError, @"SHELL", @"posix_spawn failed rc=%d (%s) executable=%@", rc, strerror(rc), executable);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:rc
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"posix_spawn: %s", strerror(rc)] }];
        return NO;
    }

    // 关闭父进程持有的管道另一端，保证子进程退出时读端能收到 EOF
    if (stdoutPipe) [stdoutPipe.fileHandleForWriting closeFile];
    if (stderrPipe) [stderrPipe.fileHandleForWriting closeFile];
    if (stdinPipe)  [stdinPipe.fileHandleForReading closeFile];

    self.pid = pid;
    self.running = YES;
    self.launched = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        pid_t waited = waitpid(pid, &status, 0);
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.status = (waited == pid) ? (WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status)) : -1;
        strongSelf.running = NO;
        strongSelf.reaped = YES;
        dispatch_semaphore_signal(strongSelf.exitSemaphore);
        void (^handler)(CAProcess *) = strongSelf.terminationHandler;
        if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(strongSelf); });
    });
    return YES;
}

#pragma mark - 等待 / 终止

- (void)waitUntilExit
{
    if (!self.launched) return;
    if (!self.running) return;
    dispatch_semaphore_wait(self.exitSemaphore, DISPATCH_TIME_FOREVER);
}

- (int)waitUntilExitWithTimeout:(NSTimeInterval)timeout
{
    if (!self.launched) return -1;
    if (self.running) {
        dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
        dispatch_semaphore_wait(self.exitSemaphore, deadline);
    }
    if (self.running) {
        [self terminate];
        return -2;   // 超时
    }
    return self.status;
}

- (void)terminate
{
    if (!self.launched || !self.running || self.pid <= 0) return;
    kill(self.pid, SIGTERM);
}

- (void)interrupt
{
    if (!self.launched || !self.running || self.pid <= 0) return;
    kill(self.pid, SIGINT);
}

- (void)dealloc
{
    if (self.launched && self.running) kill(self.pid, SIGKILL);
}

@end
