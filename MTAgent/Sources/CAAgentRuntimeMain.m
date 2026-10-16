//
//  CAAgentRuntimeMain.m — 无界面运行模式（原包类：CAAgentRuntimeMain / CAAgentRuntimeShouldHandleArguments）
//  用途：Helpers/bash-codex 与 codex-code-mode-host 都是指向主程序的链接，用于把 codex 的
//        code-mode host 与 bash 包装成设备内的执行入口。
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAExecutionEnvironment.h"
#import "CACodexEngine.h"
#import <spawn.h>
#import <sys/wait.h>

static NSString *CAAgentArgumentValue(NSArray<NSString *> *arguments, NSString *flag)
{
    NSUInteger index = [arguments indexOfObject:flag];
    if (index == NSNotFound || index + 1 >= arguments.count) return nil;
    return arguments[index + 1];
}

int CAAgentRuntimeMain(int argc, char **argv)
{
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (int i = 1; i < argc; i++) [arguments addObject:[NSString stringWithUTF8String:argv[i]]];

    CALog(CALogLevelInfo, @"RUNTIME", @"agent runtime start invocation=%@ arguments=%lu",
          CACurrentInvocationName(), (unsigned long)arguments.count);

    // 1) 直接透传给 codex（runtime 安装目录优先）
    NSString *codex = [[CACodexEngine sharedEngine] resolveCodexExecutable];
    // 2) bash-codex 的另一条路径：把参数当 shell 脚本交给 bash.real
    BOOL wantsShell = [CACurrentInvocationName() isEqualToString:@"bash-codex"];

    if (wantsShell && codex.length) {
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:codex];
        task.arguments = arguments;
        NSMutableDictionary *env = [[[CACodexEngine sharedEngine] environmentForCodexInvocation] mutableCopy];
        env[CAEnvSpawnExternal] = @"1";
        task.environment = env;
        NSError *error = nil;
        if ([task launchAndReturnError:&error]) {
            [task waitUntilExit];
            return task.terminationStatus;
        }
        CALog(CALogLevelError, @"RUNTIME", @"agent runtime launch failed error=%@", error.localizedDescription);
    }

    if (wantsShell) {
        // 无 codex 时退化为 bash -lc
        NSMutableArray<NSString *> *bashArguments = [NSMutableArray arrayWithObject:@"-lc"];
        [bashArguments addObjectsFromArray:arguments.count ? @[[arguments componentsJoinedByString:@" "]] : @[@""]];
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:CARuntimePaths.bashRealPath];
        task.arguments = bashArguments;
        NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
        env[@"PATH"] = [@[[CARuntimePaths helpersDirectory], CARuntimePaths.helperSearchPath] componentsJoinedByString:@":"];
        task.environment = env;
        NSError *error = nil;
        if ([task launchAndReturnError:&error]) {
            [task waitUntilExit];
            return task.terminationStatus;
        }
        fprintf(stderr, "bash-codex: %s\n", error.localizedDescription.UTF8String);
        return 127;
    }

    // codex-code-mode-host：保持前台，等待 codex 连接内部 MCP 桥（27018）
    CALog(CALogLevelInfo, @"RUNTIME", @"code-mode host waiting for internal MCP bridge %@", CAInternalMCPURLString);
    dispatch_main();
    return 0;
}
