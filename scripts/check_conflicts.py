# -*- coding: utf-8 -*-
"""编译前静态体检：同一类内同选择器但返回值类型不一致（ObjC 会直接报 conflicting types）。

覆盖来源：@interface 声明、@implementation 方法定义、PARITY-PLACEHOLDER / PARITY-METHOD-STUBS 占位块。
用法：python scripts/check_conflicts.py [--fix]
      --fix 会删除“占位块里与已有实现冲突”的声明行（只动标记块内的行）。
"""
import argparse, os, re, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
EMPTY_RET = {"", "id", "instancetype"}

DECL = re.compile(r"^\s*([-+])\s*\(\s*([^)]*?)\s*\)\s*([^;{]+?)\s*[;{]")


def normalize_selector(sig):
    parts = re.findall(r"([A-Za-z_]\w*)\s*:", sig)
    if parts:
        return "".join(p + ":" for p in parts)
    bare = re.match(r"\s*([A-Za-z_]\w*)", sig)
    return bare.group(1) if bare else None


def scan():
    """返回 conflicts: {(class, sel): {ret: [ (file, line_no, in_block) ]}}"""
    found = collections.defaultdict(lambda: collections.defaultdict(list))
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith((".h", ".m")):
                    continue
                path = os.path.join(rd, f)
                lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
                cls, in_block = None, False
                for idx, line in enumerate(lines, 1):
                    if "==PARITY-PLACEHOLDER-BEGIN==" in line or "==PARITY-METHOD-STUBS-BEGIN==" in line:
                        in_block = True
                    if "==PARITY-PLACEHOLDER-END==" in line or "==PARITY-METHOD-STUBS-END==" in line:
                        in_block = False
                    m = re.match(r"\s*@(?:interface|implementation)\s+([A-Za-z_]\w*)", line)
                    if m:
                        cls = m.group(1)
                        continue
                    if not cls:
                        continue
                    dm = DECL.match(line)
                    if not dm:
                        continue
                    ret_raw, sig = dm.group(2).strip(), dm.group(3).strip()
                    sel = normalize_selector(sig)
                    if not sel:
                        continue
                    ret = "id" if ret_raw in EMPTY_RET else ret_raw
                    found[(cls, sel)][ret].append((os.path.relpath(path, ROOT), idx, in_block))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args()

    found = scan()
    conflicts = {k: v for k, v in found.items() if len(v) > 1}
    print("扫描到方法声明点 %d 组；返回值类型冲突 %d 组" % (len(found), len(conflicts)))
    if not conflicts:
        print("未发现冲突：同选择器返回值一致。")
        return 0

    fixable = 0
    for (cls, sel), rets in sorted(conflicts.items())[:40]:
        detail = "; ".join("%s×%d(%s)" % (r, len(v), v[0][0]) for r, v in rets.items())
        block_only = all(loc[2] for locs in rets.values() for loc in locs)
        print("  %-34s %-34s %s%s" % (cls, sel, detail, "  ← 全在占位块内，可自动修" if block_only else ""))
        if block_only:
            fixable += 1

    if args.fix and fixable:
        removed = 0
        for path in {loc[0] for rets in conflicts.values() for locs in rets.values() for loc in locs}:
            abspath = os.path.join(ROOT, path)
            lines = open(abspath, encoding="utf-8", errors="replace").read().splitlines()
            out, in_block, changed = [], False, False
            keep_block = []
            for line in lines:
                if "==PARITY-PLACEHOLDER-BEGIN==" in line or "==PARITY-METHOD-STUBS-BEGIN==" in line:
                    in_block, keep_block = True, []
                    out.append(line)
                    continue
                if "==PARITY-PLACEHOLDER-END==" in line or "==PARITY-METHOD-STUBS-END==" in line:
                    in_block = False
                    out.extend(keep_block)
                    out.append(line)
                    continue
                if in_block:
                    dm = DECL.match(line)
                    sel = normalize_selector(dm.group(3)) if dm else None
                    drop = False
                    for (cls, s), rets in conflicts.items():
                        if s == sel and not all(loc[2] for locs in rets.values() for loc in locs):
                            drop = True
                            break
                    if drop:
                        removed += 1
                        changed = True
                        continue
                    keep_block.append(line)
                    continue
                out.append(line)
            if changed:
                open(abspath, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
        print("已删除 %d 行冲突占位声明" % removed)
    return 1


if __name__ == "__main__":
    sys.exit(main())
