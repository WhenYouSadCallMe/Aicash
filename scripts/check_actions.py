#!/usr/bin/env python3
"""Static audit for UIKit target/action selectors used by the replica."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "MTAgent" / "Sources"

METHOD = re.compile(r"^[+-]\s*\([^)]*\)\s*([A-Za-z_]\w*(?::[^\s{;]+)*)", re.M)
TARGET = re.compile(r"(?:action|selector)\s*:\s*@selector\(([^)]+)\)")
GESTURE = re.compile(r"addGestureRecognizer:.*?action:@selector\(([^)]+)\)", re.S)

def main() -> int:
    files = list(SOURCES.rglob("*.m")) + list(SOURCES.rglob("*.h"))
    source = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in files)
    methods = set()
    for match in METHOD.finditer(source):
        selector = match.group(1)
        if selector:
            methods.add(selector)
    actions = []
    for match in TARGET.finditer(source):
        selector = match.group(1).strip()
        actions.append(selector)
    method_bases = {m.split(":", 1)[0] for m in methods}
    action_bases = {a.split(":", 1)[0] for a in actions}
    missing = sorted(action_bases - method_bases)
    print(f"target/action selectors: {len(actions)}")
    print(f"implemented candidates: {len(actions) - len(missing)}")
    if missing:
        print("missing selectors:")
        for selector in missing:
            print(f"  - {selector}")
        return 1
    print("all statically referenced action selectors have an implementation candidate")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
