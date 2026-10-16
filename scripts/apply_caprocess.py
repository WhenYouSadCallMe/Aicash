# -*- coding: utf-8 -*-
"""把源码里的 NSTask 调用点替换为 iOS 可用的 CAProcess（同名同形 API），并补 import。
用法：python scripts/apply_caprocess.py [--check]
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
SKIP_FILES = {"CAProcess.h", "CAProcess.m"}

IMPORT_LINE = '#import "CAProcess.h"'
IMPORT_RE = re.compile(r'^\s*#\s*import\s+.*$', re.M)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    touched, replaced = [], 0
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith((".m", ".h")) or f in SKIP_FILES:
                    continue
                path = os.path.join(rd, f)
                body = open(path, encoding="utf-8", errors="replace").read()
                if "NSTask" not in body:
                    continue
                count = len(re.findall(r"\bNSTask\b", body))
                new = re.sub(r"\bNSTask\b", "CAProcess", body)
                if IMPORT_LINE not in new:
                    matches = list(IMPORT_RE.finditer(new))
                    if matches:
                        pos = matches[-1].end()
                        new = new[:pos] + "\n" + IMPORT_LINE + new[pos:]
                    else:
                        new = IMPORT_LINE + "\n" + new
                replaced += count
                touched.append((f, count))
                if not args.check:
                    open(path, "w", encoding="utf-8", newline="\n").write(new)

    print("%s：%d 个文件、共 %d 处 NSTask → CAProcess"
          % ("[check]" if args.check else "[apply]", len(touched), replaced))
    for f, c in sorted(touched, key=lambda x: -x[1])[:15]:
        print("   %-38s %d" % (f, c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
