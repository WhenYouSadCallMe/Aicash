# -*- coding: utf-8 -*-
"""为 method_coverage 里"真实待写方法"补实现占位（幂等，写在各 .m 的最后一个 @end 之前）。
用法：python scripts/apply_missing_method_stubs.py
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
B, E = "// ==PARITY-METHOD-STUBS-BEGIN==", "// ==PARITY-METHOD-STUBS-END=="
SKIP = {".cxx_destruct"}


def signature(sel):
    if not sel.endswith(":"):
        return "- (void)%s" % sel
    parts = sel.split(":")[:-1]
    return "- (void)%s" % " ".join("%s:(id)arg%u" % (p, i + 1) for i, p in enumerate(parts))


def find_impl(cls):
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith(".m"):
                    continue
                p = os.path.join(rd, f)
                body = open(p, encoding="utf-8", errors="replace").read()
                if re.search(r"@implementation\s+%s\b" % re.escape(cls), body):
                    return p, body
    return None, None


def main():
    gaps = json.load(open(os.path.join(ROOT, "SPEC", "selector_gaps.json"), encoding="utf-8"))
    total = 0
    for cls, sels in gaps.items():
        todo = [s for s in sels if s not in SKIP]
        if not todo:
            continue
        path, body = find_impl(cls)
        if not path:
            print("  跳过（未找到实现文件）: %s" % cls)
            continue
        if B in body:
            todo = [s for s in todo if signature(s).split("]")[0] not in body]
            if not todo:
                continue
        block = [B]
        for s in todo:
            if signature(s) in body:
                continue
            block += [signature(s), "{", "    // TODO(parity): 行为按原包实现补全", "}", ""]
        block.append(E)
        idx = body.rfind("@end")
        body = body[:idx] + "\n".join(block) + "\n" + body[idx:]
        open(path, "w", encoding="utf-8", newline="\n").write(body)
        total += len(todo)
        print("  %s: +%d 个方法占位 (%s)" % (cls, len(todo), os.path.basename(path)))
    print("合计补写 %d 个方法占位" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
