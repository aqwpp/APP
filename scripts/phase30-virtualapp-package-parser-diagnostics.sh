#!/usr/bin/env bash
set -euo pipefail
VA="USBTool/va-lib/src/main/java/com/lody/virtual/server/pm/VAppManagerService.java"
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
test -s "$VA"
test -s "$RUNNER"
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
            android.util.Log.e(TAG, "VirtualApp package parser failed for " + packageFile, e);
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

p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
if "private static volatile Context hostContext" not in s:
    s=s.replace("    private static final ExecutorService EXECUTOR", "    private static volatile Context hostContext;\\n    private static final ExecutorService EXECUTOR")
    s=s.replace("        VirtualCore core = VirtualCore.get();\\n        try {", "        hostContext = context.getApplicationContext();\\n        VirtualCore core = VirtualCore.get();\\n        try {", 1)
if "PackageInfo archiveInfo" not in s:
    s=s.replace("import android.content.Intent;", "import android.content.Intent;\\nimport android.content.pm.PackageInfo;\\nimport android.content.pm.PackageManager;\\nimport java.util.zip.ZipFile;")
    old='''                VirtualCore core = VirtualCore.get();
                if (!core.isStartup()) {
                    throw new IllegalStateException("VirtualCore 尚未初始化；请先在主线程初始化引擎");
                }
                InstallResult install = core.installPackage(
                        apk.getAbsolutePath(), InstallStrategy.UPDATE_IF_EXIST);'''
    new='''                Context appContext = hostContext;
                PackageManager pm = appContext == null ? null : appContext.getPackageManager();
                if (pm == null) throw new IllegalStateException("无法取得系统 PackageManager");
                PackageInfo archiveInfo = pm.getPackageArchiveInfo(apk.getAbsolutePath(),
                        PackageManager.GET_ACTIVITIES | PackageManager.GET_SERVICES
                                | PackageManager.GET_RECEIVERS | PackageManager.GET_PROVIDERS);
                StringBuilder preflight = new StringBuilder();
                preflight.append("APK path: ").append(apk.getAbsolutePath())
                        .append("\\nAPK bytes: ").append(apk.length());
                try (ZipFile zip = new ZipFile(apk)) {
                    preflight.append("\\nAndroidManifest.xml entry: ")
                            .append(zip.getEntry("AndroidManifest.xml") != null);
                }
                if (archiveInfo == null || archiveInfo.packageName == null) {
                    throw new IllegalStateException("系统 PackageManager 也无法解析该 APK。\\n"
                            + preflight + "\\n请确认导入的是完整 base APK，而不是 XAPK/APKS/拆分包中的单个 split。");
                }
                preflight.append("\\nHost parser package: ").append(archiveInfo.packageName)
                        .append("\\nHost parser versionCode: ").append(archiveInfo.versionCode)
                        .append("\\nSplit APK: ").append(archiveInfo.splitNames != null
                                && archiveInfo.splitNames.length > 0);
                if (!expectedPackage.equals(archiveInfo.packageName)) {
                    throw new IllegalStateException("导入记录包名与 APK 实际包名不一致。\\n"
                            + preflight);
                }
                VirtualCore core = VirtualCore.get();
                if (!core.isStartup()) {
                    throw new IllegalStateException("VirtualCore 尚未初始化；请先在主线程初始化引擎");
                }
                InstallResult install = core.installPackage(
                        apk.getAbsolutePath(), InstallStrategy.UPDATE_IF_EXIST);'''
    if old not in s: raise SystemExit("install block anchor missing")
    s=s.replace(old,new,1)
p.write_text(s)

PY
cat > USBTool/BUILD_AUDIT_PHASE30.txt <<'AUDIT'
USBTool Phase 30 - VirtualApp package parser diagnostics
- Preserve server-side PackageParserEx exceptions in InstallResult failure text and logcat.
- Preflight the selected APK with Android PackageManager.
- Report canonical path, byte length, AndroidManifest.xml ZIP entry, actual package/version and split status.
- Detect mismatch between imported record package name and archive package name.
- Does not claim parser compatibility or guest launch success until validated on device.
AUDIT
grep -q 'Parser detail:' "$VA"
grep -q 'Host parser package:' "$RUNNER"
echo "Phase 30 VirtualApp parser diagnostics source audit passed."
