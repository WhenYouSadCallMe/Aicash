# -*- coding: utf-8 -*-
"""按 CI 报错做定向修复（幂等）。用法：python scripts/fix_ci_errors.py"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "MTAgent", "Sources")
report = []


def patch(fname, pairs, require=False):
    path = os.path.join(SRC, fname)
    text = open(path, encoding="utf-8", errors="replace").read()
    original = text
    hits = 0
    for old, new in pairs:
        if old in text:
            hits += text.count(old)
            text = text.replace(old, new)
        elif require:
            report.append("!! %s 未匹配: %s" % (fname, old[:60]))
    if text != original:
        open(path, "w", encoding="utf-8", newline="\n").write(text)
    report.append("%-28s 替换 %d 处" % (fname, hits))


# A. CACommon.m：泛型参数 + 移除 iOS 不可用的 chdir_np
patch("CACommon.m", [
    ("NSDictionary<NSString *> *environment", "NSDictionary<NSString *, NSString *> *environment"),
    ("""    // posix_spawn_file_actions_addchdir_np 在较新 SDK 上标注 iOS 16+：必须做可用性守卫，
    // 否则以 iOS 15 为部署目标会直接编译报错（unavailable）。
    if (workingDirectory.length && @available(iOS 16.0, *)) {
        posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.fileSystemRepresentation);
    }
""", """    // posix_spawn_file_actions_addchdir_np 在 iOS SDK 中不可用（macOS 专属符号），
    // 需要指定工作目录的调用方请使用 CAProcess（内部以 /bin/sh -c 'cd … && exec …' 实现）。
"""),
])

# B. CAExecutionEnvironment.m：objc_msgSend 头文件 + NSArray 误用 containsString:
path = os.path.join(SRC, "CAExecutionEnvironment.m")
text = open(path, encoding="utf-8", errors="replace").read()
if "#import <objc/message.h>" not in text:
    text = text.replace("#import ", "#import <objc/message.h>\n#import ", 1)
n = text.count("[evidence containsString:")
text = text.replace("[evidence containsString:", "[evidence containsObject:")
open(path, "w", encoding="utf-8", newline="\n").write(text)
report.append("%-28s 替换 %d 处 + objc/message.h" % ("CAExecutionEnvironment.m", n))

# C. CAFileToolMain.m：NSString 下标表达式 + NSData 缺 error 参数
path = os.path.join(SRC, "CAFileToolMain.m")
text = open(path, encoding="utf-8", errors="replace").read()
before = text
text = text.replace("argument[0]", "[argument characterAtIndex:0]")
text = text.replace("argument[1]", "[argument characterAtIndex:1]")
text = re.sub(r"\[argument characterAtIndex:0\] == '-'", "[argument characterAtIndex:0] == '-'", text)
text = text.replace("[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe]",
                    "[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil]")
count = sum(1 for a, b in zip(before.splitlines(), text.splitlines()) if a != b)
if text != before:
    open(path, "w", encoding="utf-8", newline="\n").write(text)
report.append("%-28s 修改 %d 行（NSString 下标 / NSData 参数）" % ("CAFileToolMain.m", count))

# D. CACodexEngine.m：不存在的属性 runtimeRootForID:
patch("CACodexEngine.m", [
    ('[CARuntimePaths.runtimeRootForID:@"theos"]',
     '[CARuntimePaths.runtimeDownloadsDirectory stringByAppendingPathComponent:@"theos"]'),
])

print("\n".join(report))
