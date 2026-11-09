#!/usr/bin/env bash
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
VA_MANIFEST="$ROOT/USBTool/va-lib/src/main/AndroidManifest.xml"
APP_MANIFEST="$ROOT/USBTool/app/src/main/AndroidManifest.xml"
OUT="$ROOT/USBTool/VA_RUNTIME_TOPOLOGY_PHASE18.txt"
test -f "$VA_MANIFEST"
test -f "$APP_MANIFEST"

python3 - "$VA_MANIFEST" "$APP_MANIFEST" "$OUT" <<'PY'
import sys, xml.etree.ElementTree as ET
from pathlib import Path
va, app, out = map(Path, sys.argv[1:])
A = '{http://schemas.android.com/apk/res/android}'
def read(p):
    root = ET.parse(p).getroot()
    rows = []
    for tag in ('application',):
        node = root.find(tag)
        if node is None: continue
        for kind in ('activity','activity-alias','service','receiver','provider'):
            for item in node.findall(kind):
                rows.append((kind, item.get(A+'name',''), item.get(A+'process',''), item.get(A+'authorities','')))
    return rows
v, h = read(va), read(app)
lines = [
    'USBTool / VirtualApp Phase 18 manifest topology audit',
    'Static inspection only. Does not start VirtualCore or execute guest APKs.',
    '',
    f'VirtualApp library manifest: {len(v)} components',
]
for kind,name,proc,auth in v:
    lines.append(f'  VA {kind}: {name} process={proc or "(default)"} authorities={auth or "-"}')
lines += ['', f'USBTool host manifest: {len(h)} components']
for kind,name,proc,auth in h:
    lines.append(f'  HOST {kind}: {name} process={proc or "(default)"} authorities={auth or "-"}')
host_names = {name for _,name,_,_ in h}
lines += ['', 'Checks:']
for kind,name,proc,auth in v:
    if kind == 'provider' and name not in host_names:
        lines.append(f'  NOTE: library provider not explicitly duplicated in app manifest: {name} (verify manifest merge)')
if not any(k == 'activity' and ('Stub' in n or 'stub' in n) for k,n,_,_ in v+h):
    lines.append('  WARNING: no Activity with Stub/stub in its class name was found by this heuristic')
if not any(k == 'service' and ('Stub' in n or 'stub' in n) for k,n,_,_ in v+h):
    lines.append('  WARNING: no Service with Stub/stub in its class name was found by this heuristic')
if not any(k == 'provider' for k,_,_,_ in v+h):
    lines.append('  WARNING: no Provider declaration found')
lines += [
    '',
    'Acceptance boundary:',
    '- Manifest declarations are not proof that runtime initialization succeeds.',
    '- Verify merged manifest, process names, authorities, exported/permission flags and provider startup order.',
    '- VirtualCore startup, system hooks, package install and guest component launch remain unverified.',
    '- No separate Android UID/security sandbox is claimed.',
]
out.write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
PY
