#!/usr/bin/env bash
set -euo pipefail
VA="USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/VAppManagerService.java"
test -s "$VA"
python3 - <<'PY'
from pathlib import Path
import re
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/VAppManagerService.java")
s=p.read_text()
old='''        VPackage pkg = null;
        try {
            pkg = PackageParserEx.parsePackage(packageFile);
        } catch (Throwable e) {
            e.printStackTrace();
        }
        if (pkg == null || pkg.packageName == null) {
            return InstallResult.makeFailure("Unable to parse the package.");
        }'''
new='''        VPackage pkg = null;
        String parseFailure = null;
        try {
            pkg = PackageParserEx.parsePackage(packageFile);
        } catch (Throwable e) {
            parseFailure = android.util.Log.getStackTraceString(e);
            android.util.Log.e("VAppManagerService", "VirtualApp package parser failed for " + packageFile, e);
        }
        if (pkg == null || pkg.packageName == null) {
            String detail = parseFailure == null
                    ? "PackageParserEx returned null without throwing; check APK manifest and split layout."
                    : parseFailure;
            return InstallResult.makeFailure("Unable to parse the package. Parser detail: " + detail);
        }'''
if old not in s:
    if "Parser detail:" not in s:
        raise SystemExit("VAppManagerService parser block did not match; refusing unsafe patch")
else:
    s=s.replace(old,new,1)
p.write_text(s)


PY
cat > USBTool/BUILD_AUDIT_PHASE30.txt <<'AUDIT'
USBTool Phase 30 - VirtualApp package parser diagnostics
- Preserve server-side PackageParserEx exceptions in InstallResult failure text and logcat.
- Does not claim parser compatibility or guest launch success until validated on device.
AUDIT
grep -q 'Parser detail:' "$VA"
echo "Phase 30 VirtualApp parser diagnostics source audit passed."
