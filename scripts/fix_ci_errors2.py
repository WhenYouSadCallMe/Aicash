# -*- coding: utf-8 -*-
"""CI 修复批次 5：
 1) [[CARuntimePaths.X] …  → [CARuntimePaths.X …      （多余的方括号）
 2) IDA 伪类型 → ObjC 合法类型（unsigned __int64 / __int64 / _BOOL8 / _UNKNOWN 等）
 3) 移除跨类私有 ivar 访问（_pythonHome 等 → 直接重算）
用法：python scripts/fix_ci_errors2.py
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]

TYPE_MAP = [
    (r"\bunsigned __int64\b", "unsigned long long"),
    (r"\bunsigned __int32\b", "unsigned int"),
    (r"\bunsigned __int16\b", "unsigned short"),
    (r"\bunsigned __int8\b", "unsigned char"),
    (r"\b__int64\b", "long long"),
    (r"\b__int32\b", "int"),
    (r"\b__int16\b", "short"),
    (r"\b__int8\b", "signed char"),
    (r"\b_BOOL8\b", "BOOL"),
    (r"\b_UNKNOWN\b", "id"),
]

BRACKET = re.compile(r"\[\[CARuntimePaths\.([A-Za-z_]\w*)\]\s*")
IVAR = re.compile(r"^\s*if \(_[A-Za-z_]\w*\) return _[A-Za-z_]\w*;\s*$")

stats = {}
for d in DIRS:
    for rd, _sd, names in os.walk(d):
        for f in sorted(names):
            if not f.endswith((".m", ".h")):
                continue
            path = os.path.join(rd, f)
            text = open(path, encoding="utf-8", errors="replace").read()
            original = text
            n1 = len(BRACKET.findall(text))
            text = BRACKET.sub(lambda m: "[CARuntimePaths.%s " % m.group(1), text)
            n2 = 0
            for pat, rep in TYPE_MAP:
                hits = len(re.findall(pat, text))
                if hits:
                    n2 += hits
                    text = re.sub(pat, rep, text)
            n3 = 0
            if f.endswith(".m"):
                lines = text.splitlines()
                kept = [l for l in lines if not IVAR.match(l)]
                n3 = len(lines) - len(kept)
                if n3:
                    text = "\n".join(kept) + "\n"
            if text != original:
                open(path, "w", encoding="utf-8", newline="\n").write(text)
                stats[f] = (n1, n2, n3)

print("修补文件 %d 个（括号 / 伪类型 / 私有 ivar）" % len(stats))
for f, (a, b, c) in sorted(stats.items(), key=lambda kv: -(kv[1][0] + kv[1][1] + kv[1][2]))[:12]:
    print("   %-40s 括号%d 类型%d ivar%d" % (f, a, b, c))
