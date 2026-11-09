#!/usr/bin/env bash
set -euo pipefail
VA="USBTool/va-lib/src/main/java/com/lody/virtual/server/BinderProvider.java"
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
test -s "$VA"; test -s "$RUNNER"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/server/BinderProvider.java")
s=p.read_text()
if "writeUSBToolBootStage" not in s:
    anchor="public final class BinderProvider extends ContentProvider {"
    helper="""
    private static void writeUSBToolBootStage(Context context, String stage) {
        try {
            java.io.File marker = new java.io.File(context.getFilesDir(), "usbtool_va_server_boot.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(marker, false)) {
                out.write(("USBTool server boot stage: " + stage + "\\n").getBytes("UTF-8"));
                out.flush();
                out.getFD().sync();
            }
        } catch (Throwable error) {
            android.util.Log.e("USBTool-VAServer", "Cannot persist server boot stage: " + stage, error);
        }
    }
"""
    if anchor not in s: raise SystemExit("BinderProvider class anchor missing")
    s=s.replace(anchor,anchor+helper,1)
    pairs=[
      ("        DaemonService.startup(context);","        writeUSBToolBootStage(context, \"before DaemonService.startup\");\n        DaemonService.startup(context);\n        writeUSBToolBootStage(context, \"DaemonService started\");"),
      ("        VPackageManagerService.systemReady();","        writeUSBToolBootStage(context, \"before VPackageManagerService.systemReady\");\n        VPackageManagerService.systemReady();"),
      ("        VActivityManagerService.systemReady(context);","        writeUSBToolBootStage(context, \"before VActivityManagerService.systemReady\");\n        VActivityManagerService.systemReady(context);"),
      ("        VAppManagerService.systemReady();","        writeUSBToolBootStage(context, \"before VAppManagerService.systemReady\");\n        VAppManagerService.systemReady();"),
      ("        BroadcastSystem.attach(VActivityManagerService.get(), VAppManagerService.get());","        writeUSBToolBootStage(context, \"before BroadcastSystem.attach\");\n        BroadcastSystem.attach(VActivityManagerService.get(), VAppManagerService.get());"),
      ("        VNotificationManagerService.systemReady(context);","        writeUSBToolBootStage(context, \"before VNotificationManagerService.systemReady\");\n        VNotificationManagerService.systemReady(context);"),
      ("        VAppManagerService.get().scanApps();","        writeUSBToolBootStage(context, \"before VAppManagerService.scanApps\");\n        VAppManagerService.get().scanApps();"),
      ("        VAccountManagerService.systemReady();","        writeUSBToolBootStage(context, \"before VAccountManagerService.systemReady\");\n        VAccountManagerService.systemReady();"),
      ("        IPCBus.register(IVirtualLocationManager.class, VirtualLocationService.get());","        IPCBus.register(IVirtualLocationManager.class, VirtualLocationService.get());\n        writeUSBToolBootStage(context, \"BinderProvider initialization complete\");")
    ]
    for old,new in pairs:
        if old not in s: raise SystemExit("missing BinderProvider anchor: "+old)
        s=s.replace(old,new,1)
p.write_text(s)
r=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
t=r.read_text()
if "Server boot marker:" not in t:
    t=t.replace("    private static final Handler MAIN = new Handler(Looper.getMainLooper());", "    private static final Handler MAIN = new Handler(Looper.getMainLooper());\n    private static volatile Context appContext;")
    t=t.replace("    public static void prepareOnMain(Context context) {", "    public static void prepareOnMain(Context context) {\n        appContext = context.getApplicationContext();")
    anchor='''                result = "VirtualApp 安装/启动异常：" + error.getClass().getName()'''
    if anchor not in t: raise SystemExit("runner catch anchor missing")
    t=t.replace(anchor,'''                result = "Server boot marker: " + readServerBootMarker(appContext)
                        + "\\nVirtualApp 安装/启动异常：" + error.getClass().getName()''',1)
    method="""
    private static String readServerBootMarker(Context context) {
        if (context == null) return "context unavailable";
        java.io.File marker = new java.io.File(context.getFilesDir(), "usbtool_va_server_boot.txt");
        if (!marker.isFile()) return "missing (BinderProvider may not have started)";
        try {
            byte[] bytes = new byte[(int) marker.length()];
            try (java.io.FileInputStream in = new java.io.FileInputStream(marker)) {
                int offset=0, count;
                while (offset < bytes.length && (count=in.read(bytes,offset,bytes.length-offset)) > 0) offset += count;
            }
            return new String(bytes, "UTF-8").trim();
        } catch (Throwable error) {
            return "read failed: " + error.getClass().getName() + ": " + error.getMessage();
        }
    }
"""
    t=t[:t.rfind("}")]+method+t[t.rfind("}"):]
r.write_text(t)
if "BinderProvider initialization complete" not in s or "Server boot marker:" not in t:
    raise SystemExit("Phase 32 verification failed")
PY
cat > USBTool/BUILD_AUDIT_PHASE32.txt <<'AUDIT'
USBTool Phase 32 - VirtualApp Binder server startup breadcrumbs
- Persist BinderProvider initialization stage in app-private files shared by same-UID processes.
- Track daemon startup, package/activity/app manager readiness, broadcast setup, app scan, and final initialization.
- Include the last persisted server stage in client-side DeadServerException diagnostics.
- Diagnostic instrumentation only; it does not claim the Binder process crash is fixed.
AUDIT
echo "Phase 32 Binder server startup breadcrumb audit passed."
