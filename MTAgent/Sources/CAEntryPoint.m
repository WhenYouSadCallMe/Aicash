//
//  CAEntryPoint.m — 进程入口 + 多调用（multi-call）分发
//  原包布局：Helpers/bash、Helpers/sh、Helpers/bash-codex、Helpers/theos-helper、Helpers/cat… 全部是符号链接，
//          指向 ../CodexApp（bash/sh/bash-codex）或 ca-filetool（cat/ls/grep/…/theos-helper）。
//  因此主程序必须按 argv[0] 分派：App 主流程 / bash.real / codex code-mode-host / ca-filetool 工具集。
//

#import <UIKit/UIKit.h>
#import "CACommon.h"
#import "CAExecutionEnvironment.h"
#import "CAStorageManager.h"

int CAFileToolMain(int argc, char **argv);
int CAAgentRuntimeMain(int argc, char **argv);

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (CAIsHelperInvocation()) {
            return CARunHelperInvocation(argc, argv);
        }
        NSString *invocation = CACurrentInvocationName();
        if ([invocation isEqualToString:@"codex-sign"]) {
            // 由 Helpers/codex-sign 自己处理；走到这里说明链接到了主程序
            fprintf(stderr, "codex-sign: unexpected main dispatch\n");
            return 1;
        }
        return UIApplicationMain(argc, argv, nil, @"CAAppDelegate");
    }
}
