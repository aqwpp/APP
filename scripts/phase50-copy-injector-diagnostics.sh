#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java"
test -s "$FILE"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s = p.read_text()
if "private String readDiagnosticTail(" not in s:
    marker = "    private void copyDiagnosticLogs() {"
    helper = '''    private String readDiagnosticTail(String name, int maxBytes) {
        File file = new File(getFilesDir(), name);
        if (!file.isFile()) return "未生成";
        try (java.io.RandomAccessFile in = new java.io.RandomAccessFile(file, "r")) {
            int count = (int) Math.min(file.length(), Math.max(0, maxBytes));
            byte[] bytes = new byte[count];
            in.seek(Math.max(0L, file.length() - count));
            in.readFully(bytes);
            return new String(bytes, "UTF-8").trim();
        } catch (Throwable error) {
            return "读取失败：" + error.getClass().getSimpleName() + ": " + error.getMessage();
        }
    }

'''
    if marker not in s:
        raise SystemExit("copyDiagnosticLogs insertion anchor missing")
    s = s.replace(marker, helper + marker, 1)
old = '''                .append("Activity 启动子阶段:\\n")
                .append(readDiagnosticFile("usbtool_va_activity_stage.txt")).append("\\n\\n")
                .append("最近一次虚拟 APK 结果:\\n")
'''
new = '''                .append("Activity 启动子阶段:\\n")
                .append(readDiagnosticFile("usbtool_va_activity_stage.txt")).append("\\n\\n")
                .append("Hook 注入逐项记录:\\n")
                .append(readDiagnosticTail("usbtool_va_injector_stage.txt", 16384)).append("\\n\\n")
                .append("Provider 调用阶段:\\n")
                .append(readDiagnosticTail("usbtool_va_provider_stage.txt", 8192)).append("\\n\\n")
                .append("各进程启动记录:\\n")
                .append(readDiagnosticTail("usbtool_va_process_startup.txt", 16384)).append("\\n\\n")
                .append("最近一次虚拟 APK 结果:\\n")
'''
if "Hook 注入逐项记录:" not in s:
    if old not in s:
        raise SystemExit("copy diagnostic log insertion block missing")
    s = s.replace(old, new, 1)
p.write_text(s)
PY
cat > USBTool/BUILD_AUDIT_PHASE50.txt <<'AUDIT'
USBTool Phase 50 - expose startup hook traces in the in-app copy report
- Add a bounded tail reader so long multi-process diagnostics do not hide the newest failure.
- The Copy Diagnostic Logs action now includes per-injector hook traces, ProviderCall stage traces, and the process startup stack-trace log.
- This allows the user to collect the Phase 49 failing injector even when startup fails synchronously from the engine diagnostic button before a guest-install result dialog exists.
- This is diagnostics and log transport only; no hook behavior or security policy is changed.
- Validation required: Android Gradle build and manual confirmation that copied text contains the latest injector entry after a failed VirtualCore startup.
AUDIT

grep -q 'private String readDiagnosticTail(' "$FILE"
grep -q 'Hook 注入逐项记录:' "$FILE"
grep -q 'usbtool_va_process_startup.txt' "$FILE"
echo 'Phase 50 patch applied.'
