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
# Preserve the parser exception in InstallResult.error for the host UI.
if "USBTool parser diagnostic:" not in s:
    old = """        VPackage pkg = null;
        try {
            pkg = PackageParserEx.parsePackage(packageFile);
        } catch (Throwable e) {
            e.printStackTrace();
        }
        if (pkg == null || pkg.packageName == null) {
            return InstallResult.makeFailure("Unable to parse the package.");
        }"""
    new = """        VPackage pkg = null;
        String parserDiagnostic = null;
        try {
            pkg = PackageParserEx.parsePackage(packageFile);
        } catch (Throwable e) {
            android.util.Log.e("VAppManagerService", "USBTool parser diagnostic: " + packageFile, e);
            parserDiagnostic = android.util.Log.getStackTraceString(e);
            if (parserDiagnostic != null && parserDiagnostic.length() > 6000) {
                parserDiagnostic = parserDiagnostic.substring(0, 6000);
            }
        }
        if (pkg == null || pkg.packageName == null) {
            String detail = parserDiagnostic == null ? "PackageParserEx returned null without a Throwable." : parserDiagnostic;
            return InstallResult.makeFailure("Unable to parse the package.\\nParser diagnostic:\\n" + detail);
        }"""
    if old not in s:
        raise SystemExit("Parser try/catch block changed; refusing unsafe patch")
    s = s.replace(old, new, 1)
if "parserDiagnostic = android.util.Log.getStackTraceString(e);" not in s or "Parser diagnostic:" not in s:
    raise SystemExit("Phase 30 parser diagnostic verification failed")
p.write_text(s)
PY
cat > USBTool/BUILD_AUDIT_PHASE30.txt <<'AUDIT'
USBTool Phase 30 - VirtualApp package parser diagnostics
- Log the original PackageParserEx Throwable under VAppManagerService.
- Return the parser Throwable stack trace through InstallResult.error (capped at 6000 chars), so the host UI can display the actual cause without ADB.
- Guard patch around the actual PackageParserEx call site and preserve Parcelable InstallResult.error transport.
- Does not claim parser compatibility or guest launch success until validated on device.
AUDIT
echo "Phase 30 VirtualApp parser diagnostics source audit passed."
