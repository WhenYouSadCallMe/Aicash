# -*- coding: utf-8 -*-
"""一键校验：按顺序跑完所有一致性/完整性检查，输出汇总表并落盘 SPEC/验证汇总.json。

用法：python scripts/run_all_checks.py [--quick]
  --quick  跳过打包产物校验（未生成 .tipa 时）
"""
import argparse, json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable

CHECKS = [
    ("契约·plist/entitlements/布局/资源", ["verify/verify_parity.py"]),
    ("契约·关键字面量",                  ["verify/verify_literals.py"]),
    ("源码·import/括号/声明实现",        ["scripts/check_sources.py"]),
    ("源码·类型可达性(前向声明)",         ["scripts/fix_parity_forward_decls.py", "--check"]),
    ("覆盖度·选择器命中",                ["verify/verify_method_coverage.py", "--min", "0.05"]),
    ("覆盖度·属性类型映射",              ["scripts/extract_property_types.py"]),
    ("产物·.tipa 布局与内容",            ["verify/verify_package.py"]),
]

# 这些脚本即便发现问题也返回 0（纯报告型），判定标准另设
REPORT_ONLY = {"覆盖度·选择器命中", "覆盖度·属性类型映射"}


def run(script):
    path = os.path.join(ROOT, script[0])
    if not os.path.exists(path):
        return None, "脚本缺失: %s" % script[0]
    t0 = time.time()
    proc = subprocess.run([PY, path] + script[1:], cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    return proc, "%.1fs" % (time.time() - t0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args()

    rows, failures = [], []
    for name, script in CHECKS:
        if args.quick and name.startswith("产物"):
            rows.append({"check": name, "status": "skipped", "detail": "--quick"})
            continue
        proc, elapsed = run(script)
        if proc is None:
            rows.append({"check": name, "status": "missing", "detail": elapsed})
            failures.append(name)
            continue
        tail = [l for l in (proc.stdout or "").strip().splitlines() if l.strip()][-1:] or [""]
        ok = proc.returncode == 0
        status = "pass" if ok else ("report" if name in REPORT_ONLY else "fail")
        if status == "fail":
            failures.append(name)
        rows.append({"check": name, "status": status, "seconds": elapsed,
                     "detail": tail[0][:160], "returncode": proc.returncode})

    print("%-34s %-8s %-7s %s" % ("检查项", "结果", "耗时", "摘要"))
    print("-" * 100)
    for r in rows:
        print("%-34s %-8s %-7s %s" % (r["check"], r.get("status"), r.get("seconds", "-"), r.get("detail", "")))
    print("-" * 100)
    print("通过 %d / 报告 %d / 失败 %d（共 %d）"
          % (sum(1 for r in rows if r["status"] == "pass"),
             sum(1 for r in rows if r["status"] == "report"),
             sum(1 for r in rows if r["status"] == "fail"), len(rows)))

    summary = {"generated_at": time.strftime("%Y-%m-%d %H:%M:%S"), "rows": rows, "failures": failures}
    json.dump(summary, open(os.path.join(ROOT, "SPEC", "验证汇总.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("汇总: SPEC/验证汇总.json")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
