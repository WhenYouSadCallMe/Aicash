# -*- coding: utf-8 -*-
"""补齐已实现类的缺失选择器（PARITY-PLACEHOLDER 声明块，幂等）。

依据 SPEC/method_coverage.json 的逐类 missing 清单，在对应头文件的 @interface 末尾插入
`- (id)sel:(id)arg1 …;` 声明（仅声明，方法体由后续行为补全轮次填写）。标记块可重复执行。
用法：python scripts/apply_selector_placeholders.py [--check]
"""
import argparse, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
B, E = "// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==", "// ==PARITY-SELECTOR-PLACEHOLDER-END=="


def sig(sel):
    if not sel.endswith(":"):
        return "- (id)%s;" % sel
    parts = sel.split(":")[:-1]
    return "- (id)%s;" % " ".join("%s:(id)arg%u" % (p, i + 1) for i, p in enumerate(parts))


def find_header(cls):
    """先按 <类名>.h 匹配；否则扫描所有头文件找 @interface <类名>（多类共用头文件的情况）。"""
    fallback = None
    for d in DIRS:
        for rd, _sd, names in os.walk(d):
            for f in sorted(names):
                if not f.endswith(".h"):
                    continue
                path = os.path.join(rd, f)
                if f == cls + ".h":
                    return path
                if fallback is None:
                    body = open(path, encoding="utf-8", errors="replace").read()
                    if re.search(r"@interface\s+%s\b" % re.escape(cls), body):
                        fallback = path
    return fallback


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    cov = json.load(open(os.path.join(ROOT, "SPEC", "method_coverage.json"), encoding="utf-8"))["classes"]

    files, total = 0, 0
    for cls, info in cov.items():
        missing = [s for s in info.get("missing", []) if re.fullmatch(r"[A-Za-z_]\w*:?(?:[A-Za-z_]\w*:)*", s)]
        if not missing:
            continue
        path = find_header(cls)
        if not path:
            continue
        body = open(path, encoding="utf-8", errors="replace").read()
        new = [s for s in missing if sig(s).rstrip(";").split(":")[0] not in body]
        if not new:
            continue
        block = "\n" + B + "\n" + "\n".join("    " + sig(s) for s in sorted(new)) + "\n" + E + "\n"
        m = re.search(r"@interface\s+%s\b" % re.escape(cls), body)
        end = body.find("@end", m.end()) if m else -1
        if end < 0:
            continue
        if not args.check:
            open(path, "w", encoding="utf-8", newline="\n").write(body[:end] + block + body[end:])
        files += 1
        total += len(new)
    print("%s：%d 个头文件补充了 %d 条选择器声明" % ("[check]" if args.check else "[apply]", files, total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
