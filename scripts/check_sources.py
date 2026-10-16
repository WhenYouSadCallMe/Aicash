# -*- coding: utf-8 -*-
"""源码自检（精确版）：逐字符状态机剥离注释/字符串，检查括号平衡与头文件引用。

用法：python scripts/check_sources.py
"""
import os, re, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]


def strip_code(text):
    out = []
    i, n = 0, len(text)
    state = "code"
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if ch == "/" and nxt == "*":
                state = "block"; i += 2; continue
            if ch == '"':
                state = "string"; i += 1; continue
            if ch == "'":
                state = "char"; i += 1; continue
            out.append(ch); i += 1; continue
        if state == "line":
            if ch == "\n":
                state = "code"; out.append(ch)
            i += 1; continue
        if state == "block":
            if ch == "*" and nxt == "/":
                state = "code"; i += 2; continue
            i += 1; continue
        if state == "string":
            if ch == "\\":
                i += 2; continue
            if ch == '"':
                state = "code"
            i += 1; continue
        if state == "char":
            if ch == "\\":
                i += 2; continue
            if ch == "'":
                state = "code"
            i += 1; continue
    return "".join(out)


def main():
    files = []
    headers = set()
    for d in SRC_DIRS:
        if not os.path.isdir(d):
            continue
        for root_dir, _dirs, names in os.walk(d):
            for f in sorted(names):
                if f.endswith((".h", ".m")):
                    files.append(os.path.join(root_dir, f))
                    if f.endswith(".h"):
                        headers.add(f)

    imports_missing, balance_issues = [], []
    interfaces, implementations = {}, {}

    for path in files:
        name = os.path.basename(path)
        raw = open(path, encoding="utf-8", errors="replace").read()
        code = strip_code(raw)

        for m in re.finditer(r'#\s*import\s+"([^"]+)"', raw):
            header = os.path.basename(m.group(1))
            if header not in headers:
                imports_missing.append("%s -> %s" % (name, header))

        for open_ch, close_ch, label in (("{", "}", "brace"), ("(", ")", "paren"),
                                         ("[", "]", "bracket")):
            a, b = code.count(open_ch), code.count(close_ch)
            if a != b:
                balance_issues.append("%-32s %-8s %d vs %d (差 %+d)" % (name, label, a, b, a - b))

        for m in re.finditer(r"@interface\s+([A-Za-z_][A-Za-z0-9_]*)", code):
            interfaces.setdefault(m.group(1), []).append(name)
        for m in re.finditer(r"@implementation\s+([A-Za-z_][A-Za-z0-9_]*)", code):
            implementations.setdefault(m.group(1), []).append(name)

    orphan = [c for c in implementations if c not in interfaces]
    dup = [c for c, fs in implementations.items() if len(fs) > 1]

    print("源文件 %d（.h %d / .m %d），声明类 %d，实现类 %d"
          % (len(files), len(headers), len(files) - len(headers), len(interfaces), len(implementations)))

    if imports_missing:
        print("\n[问题] 未解析的本地 #import (%d):" % len(imports_missing))
        for x in imports_missing:
            print("   ", x)
    else:
        print("\n[OK] 本地 #import 全部可解析")

    if balance_issues:
        print("\n[问题] 括号不平衡 (%d):" % len(balance_issues))
        for x in balance_issues:
            print("   ", x)
    else:
        print("[OK] 全文括号平衡")

    if orphan:
        print("\n[问题] @implementation 缺 @interface:", ", ".join(orphan))
    else:
        print("[OK] @implementation 均有对应 @interface")

    if dup:
        print("[问题] 重复 @implementation:", ", ".join(dup))
    else:
        print("[OK] 无重复实现")

    must_have = ["CARemoteOperations", "CAProviderConfiguration", "CALogger", "CARuntimePaths", "CAStorageManager",
                 "CACodexEngine", "CAAppServerSession", "CAMCPBridge", "CARuntimeCatalog", "CAArchiveExtractor",
                 "CAUpdateManager", "CAExecutionEnvironment", "CAManagedRuntimeEnvironment", "CAPythonEnvironment",
                 "CATheosEnvironment", "CAReverseToolsEnvironment", "CABackgroundKeepAlive", "CAComposerCatalog",
                 "CAAppDelegate", "CAChatViewController", "CASettingsViewController", "CALogViewerViewController",
                 "CADiagnosticsViewController", "CAConversationStore", "CAModelPricingManager", "CACodexMetadataReader",
                 "CAAccountInfoBridge", "CAComposerCatalogItem"]
    missing = [c for c in must_have if c not in interfaces]
    print("\n关键类: %d/%d 已声明" % (len(must_have) - len(missing), len(must_have)))
    if missing:
        print("   待补:", ", ".join(missing))

    json.dump({"files": [os.path.relpath(f, ROOT) for f in files],
               "interfaces": interfaces, "implementations": implementations,
               "imports_missing": imports_missing, "balance_issues": balance_issues,
               "orphan_impl": orphan, "dup_impl": dup, "missing_core": missing},
              open(os.path.join(ROOT, "SPEC", "source_check_report.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("\n报告: SPEC/source_check_report.json")
    return 1 if (imports_missing or balance_issues or orphan or dup) else 0


if __name__ == "__main__":
    sys.exit(main())
