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

add_once("import android.content.Intent;","import android.content.Intent;\nimport android.content.ClipData;\nimport android.content.ClipboardManager;", "clipboard imports")
add_once('''        page.addView(readiness);

        TextView note = new TextView(this);''','''        page.addView(readiness);

        Button copyLogs = new Button(this);
        copyLogs.setText("复制诊断日志");
        copyLogs.setOnClickListener(v -> copyDiagnosticLogs());
        page.addView(copyLogs);

        TextView note = new TextView(this);''',"main log button")
add_once('''                            .setMessage(result)
                            .setPositiveButton("关闭", null).show();''','''                            .setMessage(result)
                            .setNeutralButton("复制日志", (d, w) -> copyText("USBTool 虚拟 APK 诊断日志", result))
                            .setPositiveButton("关闭", null).show();''',"startup result copy")
add_once('''                .setMessage(VirtualAppReadinessReport.create(this))
                .setPositiveButton("关闭", null).show());''','''                .setMessage(VirtualAppReadinessReport.create(this))
                .setNeutralButton("复制日志", (d, w) -> copyText("USBTool 依赖诊断", VirtualAppReadinessReport.create(this)))
                .setPositiveButton("关闭", null).show());''',"readiness copy")
add_once('''                                    progress.dismiss();
                                    new AlertDialog.Builder(this)
                                            .setTitle("虚拟 APK 启动结果")
                                            .setMessage(result)
                                            .setPositiveButton("关闭", null).show();''','''                                    progress.dismiss();
                                    getSharedPreferences("usbtool_diagnostics", MODE_PRIVATE)
                                            .edit().putString("last_virtualapp_result", result).apply();
                                    new AlertDialog.Builder(this)
                                            .setTitle("虚拟 APK 启动结果")
                                            .setMessage(result)
                                            .setNeutralButton("复制日志", (d, w) -> copyText("USBTool 虚拟 APK 诊断日志", result))
                                            .setPositiveButton("关闭", null).show();''',"virtual launch result copy")

anchor='''    private void testRuntimeProcess() {'''
methods='''    private void copyText(String label, String value) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (clipboard == null) {
            Toast.makeText(this, "无法访问剪贴板", Toast.LENGTH_LONG).show();
            return;
        }
        clipboard.setPrimaryClip(ClipData.newPlainText(label, value == null ? "" : value));
        Toast.makeText(this, "诊断日志已复制", Toast.LENGTH_SHORT).show();
    }

    private String readDiagnosticFile(String name) {
        File file = new File(getFilesDir(), name);
        if (!file.isFile()) return "未生成";
        try (InputStream in = new java.io.FileInputStream(file)) {
            byte[] bytes = new byte[(int) Math.min(file.length(), 16384)];
            int offset = 0, count;
            while (offset < bytes.length && (count = in.read(bytes, offset, bytes.length - offset)) > 0) offset += count;
            return new String(bytes, 0, offset, "UTF-8").trim();
        } catch (Throwable error) {
            return "读取失败：" + error.getClass().getSimpleName() + ": " + error.getMessage();
        }
    }

    private void copyDiagnosticLogs() {
        StringBuilder log = new StringBuilder();
        log.append("USBTool 诊断日志\\n")
                .append("Android: ").append(android.os.Build.VERSION.RELEASE)
                .append(" (API ").append(android.os.Build.VERSION.SDK_INT).append(")\\n")
                .append("设备: ").append(android.os.Build.MANUFACTURER).append(" ")
                .append(android.os.Build.MODEL).append("\\n")
                .append("ABI: ").append(java.util.Arrays.toString(android.os.Build.SUPPORTED_ABIS)).append("\\n")
                .append("进程: ").append(android.app.Application.getProcessName()).append("\\n\\n")
                .append("VirtualCore 启动阶段:\\n")
                .append(readDiagnosticFile("usbtool_va_startup_stage.txt")).append("\\n\\n")
                .append("VirtualApp 服务启动阶段:\\n")
                .append(readDiagnosticFile("usbtool_va_server_boot.txt")).append("\\n\\n")
                .append("Activity 启动子阶段:\\n")
                .append(readDiagnosticFile("usbtool_va_activity_stage.txt")).append("\\n\\n")
                .append("最近一次虚拟 APK 结果:\\n")
                .append(getSharedPreferences("usbtool_diagnostics", MODE_PRIVATE)
                        .getString("last_virtualapp_result", "暂无记录"));
        copyText("USBTool 完整诊断日志", log.toString());
    }

'''
add_once(anchor,methods+anchor,"diagnostic methods")
p.write_text(s)
PY
grep -q '复制诊断日志' "$MAIN"
grep -q 'usbtool_va_activity_stage.txt' "$MAIN"
grep -q '复制日志' "$MAIN"
cat > USBTool/BUILD_AUDIT_PHASE42.txt <<'AUDIT'
USBTool Phase 42 - user-accessible diagnostic log copy
- Add a main-screen Copy Diagnostic Logs action.
- Copy Android/device/ABI details, VirtualCore startup breadcrumb, Binder server boot breadcrumb, Activity launch substage, and the most recent complete virtual APK result/stack trace.
- Persist the last virtual APK result across app restarts using private SharedPreferences.
- Add a Copy Logs action to the VirtualApp result dialog and copy support to startup/readiness diagnostic dialogs.
- Clipboard access uses Android ClipboardManager; no storage permission or network upload is required.
AUDIT
echo "Phase 42 diagnostic log copy audit passed."
