# -*- coding: utf-8 -*-
"""类型可达性审计 + 自动补 @class 前向声明。

背景：T1 的属性补齐块、以及 UI 外壳头文件里出现 `CAFoo *` 这类类型，
      若该类型在本文件及其 #import 链里都没有声明，编译会报 unknown type name。

做法：
  1. 收集每个文件声明的类型（@interface/@implementation/@protocol/@class/typedef/NS_ENUM/NS_OPTIONS）
  2. 对每个 .h/.m，沿 #import "x.h" 做 BFS，得到可达类型集合
  3. 找出被当作类型使用（`CA*/MT* *` 或泛型参数）但不在可达集合里的类型
  4. 在最后一个 #import 之后插入 `@class A, B;`（幂等，标记包裹）

用法：python scripts/fix_parity_forward_decls.py [--check]
"""
import argparse, os, re, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIRS = [os.path.join(ROOT, "MTAgent", "Sources"), os.path.join(ROOT, "MTShareExtension", "Sources")]
BEGIN = "// ==PARITY-FORWARD-DECLS-BEGIN=="
END = "// ==PARITY-FORWARD-DECLS-END=="

DECL_RE = re.compile(r"@(?:interface|implementation|protocol)\s+([A-Za-z_]\w*)|@class\s+([A-Za-z_]\w*\s*(?:,\s*[A-Za-z_]\w*\s*)*);"
                     r"|typedef\s+[^;]*?\b([A-Za-z_]\w*)\s*;"
                     r"|(?:static\s+)?(?:const\s+)?[A-Za-z_]\w*\s+([A-Za-z_]\w*)\s*(?:=|;)")
USE_RE = re.compile(r"\b((?:CA|MT)[A-Za-z0-9_]+)\s*[*<]")
IMPORT_RE = re.compile(r'#\s*import\s+"([^"]+)"')


def strip_strings(text):
    """去掉字符串与注释，避免把宏前缀/文案误判成类型名。"""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return re.sub(r'@?"(?:\\.|[^"\\])*"', '""', text)


def is_type_candidate(name):
    if name.endswith("_") or "_" in name and name.upper() == name:
        return False
    return bool(re.fullmatch(r"[A-Z][A-Za-z0-9]{2,}", name))


def load():
    files = {}
    for d in SRC_DIRS:
        if not os.path.isdir(d):
            continue
        for root_dir, _dirs, names in os.walk(d):
            for f in sorted(names):
                if f.endswith((".h", ".m")):
                    files[f] = open(os.path.join(root_dir, f), encoding="utf-8", errors="replace").read()
    return files


def declared_types(text):
    out = set()
    for m in DECL_RE.finditer(text):
        for g in m.groups():
            if not g:
                continue
            for part in g.split(","):
                name = part.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", name):
                    out.add(name)
    for m in re.finditer(r"\bNS_(?:ENUM|OPTIONS)\s*\(\s*[^,]+,\s*([A-Za-z_]\w*)\s*\)", text):
        out.add(m.group(1))
    for m in re.finditer(r"typedef\s+NS_(?:ENUM|OPTIONS)\s*\(\s*[^)]*\)\s*([A-Za-z_]\w*)", text):
        out.add(m.group(1))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    files = load()
    decl = {name: declared_types(body) for name, body in files.items()}
    imports = {name: [os.path.basename(i) for i in IMPORT_RE.findall(body)] for name, body in files.items()}

    def reachable(name, seen=None):
        seen = seen or set()
        if name in seen:
            return set()
        seen.add(name)
        out = set(decl.get(name, set()))
        for imported in imports.get(name, []):
            if imported in files:
                out |= reachable(imported, seen)
        return out

    report, fixes = {}, {}
    for name, body in files.items():
        code = strip_strings(body)
        used = {t for t in USE_RE.findall(code) if is_type_candidate(t)}
        known = reachable(name)
        missing = sorted(t for t in used if t not in known and t not in decl.get(name, set()))
        if missing:
            report[name] = missing

    if not args.check:
        for name, missing in report.items():
            body = files[name]
            body = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "", body, flags=re.S)
            lines, current = [], []
            for t in missing:
                current.append(t)
                if len(", ".join(current)) > 90:
                    lines.append("@class " + ", ".join(current) + ";")
                    current = []
            if current:
                lines.append("@class " + ", ".join(current) + ";")
            block = "\n" + BEGIN + "\n" + "\n".join(lines) + "\n" + END + "\n"
            matches = list(IMPORT_RE.finditer(body))
            if matches:
                pos = matches[-1].end()
                body = body[:pos] + "\n" + block + body[pos:]
            else:
                # 放在文件首个 @interface/@protocol 之前
                anchor = re.search(r"@(interface|protocol)", body)
                pos = anchor.start() if anchor else 0
                body = body[:pos] + block + "\n" + body[pos:]
            path = None
            for d in SRC_DIRS:
                if os.path.exists(os.path.join(d, name)):
                    path = os.path.join(d, name)
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(body)
            fixes[name] = len(lines)

    total = sum(len(v) for v in report.values())
    print("%s：%d 个文件存在未声明类型引用，共 %d 个类型"
          % ("[check]" if args.check else "[apply]", len(report), total))
    for name, missing in sorted(report.items(), key=lambda kv: -len(kv[1]))[:20]:
        print("   %-34s %3d 个: %s" % (name, len(missing), ", ".join(missing[:6]) + (" …" if len(missing) > 6 else "")))
    if len(report) > 20:
        print("   ... 其余 %d 个文件见 SPEC/forward_decl_report.json" % (len(report) - 20))
    json.dump({"files": report, "added_decl_lines": fixes},
              open(os.path.join(ROOT, "SPEC", "forward_decl_report.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("\n报告: SPEC/forward_decl_report.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
