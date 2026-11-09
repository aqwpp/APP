#!/usr/bin/env bash
set -euo pipefail
VA="USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/VAppManagerService.java"
test -s "$VA" || { echo "Missing VirtualApp source: $VA" >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/VAppManagerService.java")
s = p.read_text()
needle = "PackageParserEx.parsePackage"
pos = s.find(needle)
if pos < 0:
    raise SystemExit("Cannot find PackageParserEx.parsePackage; source layout changed")
print("VirtualApp parser source context:")
print(s[max(0, pos-700):pos+1100])
old = "e.printStackTrace();"
if "USBTool parser diagnostic:" not in s:
    if old not in s[pos:pos+1800]:
        raise SystemExit("Parser catch block changed; refusing to patch unrelated exception handler")
    s = s[:pos] + s[pos:].replace(old,
        'android.util.Log.e("VAppManagerService", "USBTool parser diagnostic: " + packageFile, e);', 1)
old_message = 'InstallResult.makeFailure("Unable to parse the package.")'
new_message = 'InstallResult.makeFailure("Unable to parse the package. See logcat tag VAppManagerService for USBTool parser diagnostic.")'
if old_message in s:
    s = s.replace(old_message, new_message, 1)
if "USBTool parser diagnostic:" not in s or "See logcat tag VAppManagerService" not in s:
    raise SystemExit("Phase 30 parser diagnostic verification failed")
p.write_text(s)
PY
cat > USBTool/BUILD_AUDIT_PHASE30.txt <<'AUDIT'
USBTool Phase 30 - VirtualApp package parser diagnostics
- Log the original PackageParserEx Throwable under VAppManagerService.
- Make parse failure actionable by naming the logcat tag.
- Guard patch around the actual PackageParserEx call site.
- Does not claim parser compatibility or guest launch success until validated on device.
AUDIT
echo "Phase 30 VirtualApp parser diagnostics source audit passed."
