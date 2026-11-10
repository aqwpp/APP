#!/usr/bin/env bash
set -euo pipefail
MAIN="USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java"
test -s "$MAIN"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/MainActivity.java")
s=p.read_text()

def add_once(old,new,label):
    global s
    if new in s: return
    if old not in s: raise SystemExit("Missing MainActivity anchor: "+label)
    s=s.replace(old,new,1)

# Add a document-picker export action next to clipboard copy.
add_once('''        copyLogs.setOnClickListener(v -> copyDiagnosticLogs());
        page.addView(copyLogs);''','''        copyLogs.setOnClickListener(v -> copyDiagnosticLogs());
        page.addView(copyLogs);

        Button exportLogs = new Button(this);
        exportLogs.setText("导出完整诊断日志 ZIP");
        exportLogs.setOnClickListener(v -> exportDiagnosticLogs());
        page.addView(exportLogs);''',"export button")

# Add the SAF export implementation before the existing runtime probe method.
anchor='''    private void testRuntimeProcess() {'''
methods='''    private static final int USBTOOL_EXPORT_DIAGNOSTICS_REQUEST = 5402;

    private void exportDiagnosticLogs() {
        try {
            android.content.Intent intent = new android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT);
            intent.addCategory(android.content.Intent.CATEGORY_OPENABLE);
            intent.setType("application/zip");
            intent.putExtra(android.content.Intent.EXTRA_TITLE, "USBTool-diagnostics.zip");
            startActivityForResult(intent, USBTOOL_EXPORT_DIAGNOSTICS_REQUEST);
        } catch (Throwable error) {
            Toast.makeText(this, "无法打开文件保存窗口：" + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void writeDiagnosticZip(android.net.Uri target) throws Exception {
        try (java.io.OutputStream raw = getContentResolver().openOutputStream(target)) {
            if (raw == null) throw new java.io.IOException("无法写入所选文件");
            try (java.util.zip.ZipOutputStream zip = new java.util.zip.ZipOutputStream(raw)) {
                java.io.File[] files = getFilesDir().listFiles();
                if (files != null) {
                    for (java.io.File file : files) {
                        String name = file.getName();
                        if (!file.isFile() || !name.startsWith("usbtool_va_") || !name.endsWith(".txt")) continue;
                        zip.putNextEntry(new java.util.zip.ZipEntry("logs/" + name));
                        try (java.io.InputStream in = new java.io.FileInputStream(file)) {
                            byte[] buffer = new byte[8192];
                            int count;
                            while ((count = in.read(buffer)) != -1) zip.write(buffer, 0, count);
                        }
                        zip.closeEntry();
                    }
                }
                zip.putNextEntry(new java.util.zip.ZipEntry("logs/usbtool_environment.txt"));
                String environment = "Android: " + android.os.Build.VERSION.RELEASE
                        + " (API " + android.os.Build.VERSION.SDK_INT + ")\\n"
                        + "Device: " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL + "\\n"
                        + "ABI: " + java.util.Arrays.toString(android.os.Build.SUPPORTED_ABIS) + "\\n"
                        + "Process: " + android.app.Application.getProcessName() + "\\n";
                zip.write(environment.getBytes("UTF-8"));
                zip.closeEntry();
                zip.putNextEntry(new java.util.zip.ZipEntry("logs/last_virtualapp_result.txt"));
                String last = getSharedPreferences("usbtool_diagnostics", MODE_PRIVATE)
                        .getString("last_virtualapp_result", "暂无记录");
                zip.write(last.getBytes("UTF-8"));
                zip.closeEntry();
            }
        }
        Toast.makeText(this, "完整诊断日志 ZIP 已保存，请将 ZIP 文件发送到聊天", Toast.LENGTH_LONG).show();
    }

'''
# Inject into the existing callback, which already exists for APK picking.
import re
pattern = r'((?:public|protected)\s+void\s+onActivityResult\s*\(\s*int\s+requestCode\s*,\s*int\s+resultCode\s*,\s*(?:android\.content\.)?Intent\s+(\w+)\s*\)\s*\{)'
m=re.search(pattern,s)
if not m: raise SystemExit("Existing onActivityResult callback not found")
callback=m.group(1); data_name=m.group(2)
handler=f'''
        if (requestCode == USBTOOL_EXPORT_DIAGNOSTICS_REQUEST) {{
            if (resultCode == RESULT_OK && {data_name} != null && {data_name}.getData() != null) {{
                try {{
                    writeDiagnosticZip({data_name}.getData());
                }} catch (Throwable error) {{
                    Toast.makeText(this, "导出失败：" + error.getClass().getSimpleName()
                            + ": " + error.getMessage(), Toast.LENGTH_LONG).show();
                }}
            }}
            return;
        }}
'''
# Add the constant and helper, then splice the branch into existing callback.
if "USBTOOL_EXPORT_DIAGNOSTICS_REQUEST" not in s:
    if anchor not in s: raise SystemExit("runtime method insertion anchor missing")
    s=s.replace(anchor,methods+anchor,1)
s=s.replace(callback,callback+handler,1)
if "USBTOOL_EXPORT_DIAGNOSTICS_REQUEST" not in s:
    if anchor not in s: raise SystemExit("runtime method insertion anchor missing")
    s=s.replace(anchor,methods+anchor,1)

p.write_text(s)
PY

grep -q '导出完整诊断日志 ZIP' "$MAIN"
grep -q 'ACTION_CREATE_DOCUMENT' "$MAIN"
grep -q 'writeDiagnosticZip' "$MAIN"
! grep -q 'protected void onActivityResult(int requestCode, int resultCode, android.content.Intent data)' "$MAIN"
grep -q 'usbtool_va_' "$MAIN"
cat > USBTool/BUILD_AUDIT_PHASE54.txt <<'AUDIT'
USBTool Phase 54 - export complete diagnostics as ZIP
- Add a Storage Access Framework "Export Full Diagnostic Logs ZIP" action.
- The user chooses a destination through Android's system document picker; no broad storage permission is requested.
- Export every matching usbtool_va_*.txt diagnostic file in the app's private files directory without tail truncation.
- Include device/API/ABI/process metadata and the persisted last VirtualApp result/stack trace.
- The export is local only; no network upload or clipboard size limit.
- User can attach the resulting ZIP in ChatGPT.
AUDIT
echo "Phase 54 diagnostic ZIP export patch applied."
