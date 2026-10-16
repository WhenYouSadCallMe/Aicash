# -*- coding: utf-8 -*-
"""确保每个 .m 都能看到它实现的每个类的 @interface（否则会报
no known class method for selector 'alloc' / cannot use 'super' because it is a root class /
properties not found 这类"接口不可见"错误）。

做法：扫描全部 .h，建立 类名 → 声明所在头文件 的映射；对每个 .m 里出现的 @implementation X，
若该 .m 未 import 任何声明了 X 的头文件，则补上 `#import "Header.h"`。
用法：python scripts/ensure_impl_imports.py [--check]
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
IMPORT = re.compile(r'^\s*#\s*import\s+"([^"]+)"', re.M)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    headers, decl_of = {}, {}
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith(".h"):
                    continue
                body = open(os.path.join(rd, f), encoding="utf-8", errors="replace").read()
                headers[f] = body
                for cls in re.findall(r"@interface\s+([A-Za-z_]\w*)\s*(?::[^<\n]*)?", body):
                    decl_of.setdefault(cls, f)

    fixed = []
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith(".m"):
                    continue
                path = os.path.join(rd, f)
                body = open(path, encoding="utf-8", errors="replace").read()
                implemented = re.findall(r"@implementation\s+([A-Za-z_]\w*)", body)
                imported = set(IMPORT.findall(body))
                need = []
                for cls in implemented:
                    hdr = decl_of.get(cls)
                    if not hdr or hdr in imported:
                        continue
                    if any(cls in headers.get(i, "") for i in imported):
                        continue          # 已通过别的头间接可见
                    need.append(hdr)
                if not need:
                    continue
                lines = body.splitlines()
                last_import = max((i for i, l in enumerate(lines) if IMPORT.match(l)), default=-1)
                insert = ["#import \"%s\"" % h for h in sorted(set(need))]
                lines[last_import + 1:last_import + 1] = insert
                fixed.append("%s ← %s" % (f, ", ".join(insert)))
                if not args.check:
                    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")

    print("%s：%d 个实现文件补齐类接口 import" % ("[check]" if args.check else "[apply]", len(fixed)))
    for line in fixed[:20]:
        print("   " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
