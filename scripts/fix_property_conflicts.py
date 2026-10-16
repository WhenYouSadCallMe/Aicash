# -*- coding: utf-8 -*-
"""删除头文件 PARITY-PROPERTIES 块中，与同一类 .m 类扩展（@interface X ()）重声明冲突的属性行。

编译规则：类扩展里的 @property 声明必须与主声明的属性修饰一致，否则报
"illegal redeclaration of property in class extension"。占位属性会踩这个坑，直接移除占位行即可。

用法：python scripts/fix_property_conflicts.py [--check]
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
B, E = "// ==PARITY-PROPERTIES-BEGIN==", "// ==PARITY-PROPERTIES-END=="
PROP = re.compile(r"@property\s*\(([^)]*)\)\s*([^;]+?)\s*;\s*$")
NAME = re.compile(r"([A-Za-z_]\w*)\s*$")


def prop_name(line):
    m = PROP.search(line.strip())
    if not m:
        return None
    tail = m.group(2).strip()
    n = NAME.search(tail)
    return n.group(1) if n else None


def extension_props(m_path):
    """收集 .m 里类扩展/实现内声明的属性名集合（按类分组）。"""
    text = open(m_path, encoding="utf-8", errors="replace").read()
    result = {}
    cls = None
    for line in text.splitlines():
        m = re.match(r"\s*@interface\s+([A-Za-z_]\w*)\s*\(\s*\)", line)
        if m:
            cls = m.group(1)
            result.setdefault(cls, set())
            continue
        if re.match(r"\s*@implementation\s+([A-Za-z_]\w*)", line):
            cls = None
            continue
        if cls:
            n = prop_name(line)
            if n:
                result[cls].add(n)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    removed_total, files = 0, 0
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith(".m"):
                    continue
                m_path = os.path.join(rd, f)
                ext = extension_props(m_path)
                if not ext:
                    continue
                header = os.path.splitext(m_path)[0] + ".h"
                if not os.path.exists(header):
                    continue
                lines = open(header, encoding="utf-8", errors="replace").read().splitlines()
                out, in_block, removed = [], False, 0
                for line in lines:
                    if B in line:
                        in_block = True
                        out.append(line)
                        continue
                    if E in line:
                        in_block = False
                        out.append(line)
                        continue
                    if in_block:
                        n = prop_name(line)
                        if n and any(n in props for props in ext.values()):
                            removed += 1
                            continue
                    out.append(line)
                if removed:
                    files += 1
                    removed_total += removed
                    if not args.check:
                        open(header, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("%s：%d 个头文件，移除 %d 行冲突占位属性"
          % ("[check]" if args.check else "[apply]", files, removed_total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
