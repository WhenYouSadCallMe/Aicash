# -*- coding: utf-8 -*-
import re, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# An extracted app may be supplied by the operator; keep the repository copy
# as the default so this helper never reaches outside the workspace silently.
BASE = os.environ.get("REA_EXTRACTED_APP", os.path.join(ROOT, "OriginalAssets", "Payload", "CodexApp.app"))
FILES = {
    "CodexApp": os.path.join(BASE, "CodexApp"),
    "codex-sign": os.path.join(BASE, "Helpers", "codex-sign"),
    "ca-filetool": os.path.join(BASE, "Helpers", "ca-filetool"),
}
pat = rb'<\?xml version="1\.0" encoding="UTF-8"\?>.{0,3000}?</plist>'
for name, path in FILES.items():
    if not os.path.isfile(path):
        print('SKIP %s: file not present at %s' % (name, path))
        continue
    d = open(path, 'rb').read()
    seen = set()
    for m in re.finditer(pat, d, re.S):
        s = m.group(0)
        if b'platform-application' not in s:
            continue
        norm = re.sub(rb'\s+', b' ', s)
        if norm in seen:
            continue
        seen.add(norm)
        print('=' * 72)
        print('FILE %s  offset %d  len %d' % (name, m.start(), len(s)))
        print(s.decode('utf-8', 'replace'))
