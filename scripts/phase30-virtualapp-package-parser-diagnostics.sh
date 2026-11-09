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
# Android 9+ changed PackageParser.collectCertificates(Package, int) to
# collectCertificates(Package, boolean). The legacy Nougat mirror resolves
# the old int signature, leaving its RefStaticMethod null on API 28/29.
pie = Path("USBTool/va-lib/src/main/java/mirror/android/content/pm/PackageParserPie.java")
pie.parent.mkdir(parents=True, exist_ok=True)
pie.write_text("""package mirror.android.content.pm;

import mirror.MethodReflectParams;
import mirror.RefClass;
import mirror.RefStaticMethod;

/** Android 9 (API 28) and newer PackageParser certificate API. */
public class PackageParserPie {
    public static Class<?> TYPE = RefClass.load(PackageParserPie.class, "android.content.pm.PackageParser");
    @MethodReflectParams({"android.content.pm.PackageParser$Package", "boolean"})
    public static RefStaticMethod<Void> collectCertificates;
}
""")
compat = Path("USBTool/va-lib/src/main/java/com/lody/virtual/helper/compat/PackageParserCompat.java")
cs = compat.read_text()
if "import mirror.android.content.pm.PackageParserPie;" not in cs:
    cs = cs.replace("import mirror.android.content.pm.PackageParserNougat;","import mirror.android.content.pm.PackageParserNougat;\\nimport mirror.android.content.pm.PackageParserPie;")
if "PackageParserPie.collectCertificates.callWithException" not in cs:
    old_branch = """        if (API_LEVEL >= N) {
            PackageParserNougat.collectCertificates.callWithException(p, flags);"""
    new_branch = """        if (API_LEVEL >= Build.VERSION_CODES.P) {
            // Android 9/10 signature is (Package, boolean skipVerify), not (Package, int flags).
            // false preserves normal APK certificate verification.
            PackageParserPie.collectCertificates.callWithException(p, false);
        } else if (API_LEVEL >= N) {
            PackageParserNougat.collectCertificates.callWithException(p, flags);"""
    if old_branch not in cs:
        raise SystemExit("PackageParserCompat certificate branch changed; refusing patch")
    cs = cs.replace(old_branch, new_branch, 1)
    compat.write_text(cs)
if "PackageParserPie.collectCertificates.callWithException(p, false)" not in compat.read_text():
    raise SystemExit("Android P certificate compatibility patch failed")
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
USBTool Phase 30 - Android P+ PackageParser certificate compatibility
- Android 9/API 28 and Android 10/API 29 use PackageParser.collectCertificates(Package, boolean).
- The legacy Nougat mirror expected (Package, int), causing a null RefStaticMethod on API 29.
- Added PackageParserPie mirror with the boolean signature and call skipVerify=false (normal verification retained).
- Parser Throwable is returned through InstallResult.error for device-side diagnostics.
- Guest runtime compatibility remains unverified.
AUDIT
echo "Phase 30 VirtualApp parser diagnostics source audit passed."
