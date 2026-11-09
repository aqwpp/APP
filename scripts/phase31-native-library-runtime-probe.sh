#!/usr/bin/env bash
set -euo pipefail
TARGET="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualCoreStartupProbe.java"
test -s "$TARGET"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualCoreStartupProbe.java")
s=p.read_text()
if "APK 内 Native 库条目" not in s:
    s=s.replace("import java.io.File;", "import java.io.File;\nimport java.util.zip.ZipFile;")
    old='''        File nativeLibrary = new File(context.getApplicationInfo().nativeLibraryDir, "libva++.so");
        report.append("\\nNative 库文件：").append(nativeLibrary.exists() ? "存在" : "缺失");
        report.append("\\nNative 路径：").append(nativeLibrary.getAbsolutePath());'''
    new='''        File nativeLibrary = new File(context.getApplicationInfo().nativeLibraryDir, "libva++.so");
        report.append("\\nNative 解压文件：").append(nativeLibrary.exists() ? "存在" : "未解压/不存在");
        report.append("\\nNative 路径：").append(nativeLibrary.getAbsolutePath());
        boolean apkHasNative = false;
        try (ZipFile apk = new ZipFile(context.getApplicationInfo().sourceDir)) {
            apkHasNative = apk.getEntry("lib/arm64-v8a/libva++.so") != null;
        } catch (Throwable zipError) {
            report.append("\\nAPK ZIP 检查异常：").append(zipError.getClass().getName())
                    .append(": ").append(String.valueOf(zipError.getMessage()));
        }
        report.append("\\nAPK 内 Native 库条目：").append(apkHasNative ? "存在" : "缺失");
        try {
            System.loadLibrary("va++");
            report.append("\\nNative loadLibrary：成功");
        } catch (Throwable loadError) {
            report.append("\\nNative loadLibrary：失败：")
                    .append(loadError.getClass().getName())
                    .append(": ").append(String.valueOf(loadError.getMessage()));
        }'''
    if old not in s: raise SystemExit("native diagnostic block anchor missing")
    s=s.replace(old,new,1)
p.write_text(s)
PY
grep -q 'APK 内 Native 库条目' "$TARGET"
grep -q 'System.loadLibrary("va++")' "$TARGET"
cat > USBTool/BUILD_AUDIT_PHASE31.txt <<'AUDIT'
USBTool Phase 31 - runtime native library probe
- Distinguish extracted nativeLibraryDir files from libraries embedded in sourceDir APK.
- Inspect lib/arm64-v8a/libva++.so inside the installed APK.
- Attempt System.loadLibrary("va++") and report linker errors.
- A missing extracted file alone is not treated as proof that the APK lacks its native library.
AUDIT
echo "Phase 31 native library runtime probe source audit passed."
