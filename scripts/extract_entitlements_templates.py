# -*- coding: utf-8 -*-
import re, os

BASE = r"C:\Users\Administrator\AppData\Local\Temp\2\rea-extracted-924be991-2975-464f-9aa3-ed94a774daa7\Payload\CodexApp.app"
FILES = {
    "CodexApp": os.path.join(BASE, "CodexApp"),
    "codex-sign": os.path.join(BASE, "Helpers", "codex-sign"),
    "ca-filetool": os.path.join(BASE, "Helpers", "ca-filetool"),
}
pat = rb'<\?xml version="1\.0" encoding="UTF-8"\?>.{0,3000}?</plist>'
for name, path in FILES.items():
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
