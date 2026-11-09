#!/usr/bin/env bash
set -euo pipefail
CORE="USBTool/va-lib/src/main/java/com/lody/virtual/client/core/VirtualCore.java"
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
test -s "$CORE"; test -s "$RUNNER"
python3 - <<'PY'
from pathlib import Path
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/core/VirtualCore.java")
s=p.read_text()
if "usbtool_va_startup_stage.txt" not in s:
    marker='''    private void writeUSBToolStartupStage(Context context, String stage) {
        try {
            java.io.File file = new java.io.File(context.getFilesDir(), "usbtool_va_startup_stage.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file, false)) {
                out.write((stage + "\\n").getBytes("UTF-8"));
                out.flush();
                out.getFD().sync();
            }
        } catch (Throwable ignored) {
        }
    }

'''
    anchor='    public void startup(Context context) throws Throwable {'
    if anchor not in s: raise SystemExit("VirtualCore.startup anchor missing")
    s=s.replace(anchor, marker+anchor, 1)
    replacements=[
      ('            if (Looper.myLooper() != Looper.getMainLooper()) {','            writeUSBToolStartupStage(context, "startup: entered");\n            if (Looper.myLooper() != Looper.getMainLooper()) {'),
      ('            VASettings.STUB_CP_AUTHORITY = context.getPackageName() + "." + VASettings.STUB_DEF_AUTHORITY;','            writeUSBToolStartupStage(context, "startup: configure authorities");\n            VASettings.STUB_CP_AUTHORITY = context.getPackageName() + "." + VASettings.STUB_DEF_AUTHORITY;'),
      ('            mainThread = ActivityThread.currentActivityThread.call();','            writeUSBToolStartupStage(context, "startup: ActivityThread.currentActivityThread");\n            mainThread = ActivityThread.currentActivityThread.call();'),
      ('            hostPkgInfo = unHookPackageManager.getPackageInfo(context.getPackageName(), PackageManager.GET_PROVIDERS);','            writeUSBToolStartupStage(context, "startup: PackageManager.getPackageInfo");\n            hostPkgInfo = unHookPackageManager.getPackageInfo(context.getPackageName(), PackageManager.GET_PROVIDERS);'),
      ('            IPCBus.initialize(new IServerCache() {','            writeUSBToolStartupStage(context, "startup: IPCBus.initialize");\n            IPCBus.initialize(new IServerCache() {'),
      ('            detectProcessType();','            writeUSBToolStartupStage(context, "startup: detectProcessType");\n            detectProcessType();'),
      ('            invocationStubManager.init();','            writeUSBToolStartupStage(context, "startup: InvocationStubManager.init");\n            invocationStubManager.init();'),
      ('            invocationStubManager.injectAll();','            writeUSBToolStartupStage(context, "startup: InvocationStubManager.injectAll");\n            invocationStubManager.injectAll();'),
      ('            ContextFixer.fixContext(context);','            writeUSBToolStartupStage(context, "startup: ContextFixer.fixContext");\n            ContextFixer.fixContext(context);'),
      ('            isStartUp = true;','            writeUSBToolStartupStage(context, "startup: completed");\n            isStartUp = true;')
    ]
    for old,new in replacements:
        if old not in s: raise SystemExit("Missing startup patch anchor: "+old)
        s=s.replace(old,new,1)
p.write_text(s)

p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
old='''                result = "Server boot marker: " + readServerBootMarker(appContext)
                        + "\\nVirtualApp 安装/启动异常："'''
new='''                result = "VirtualCore 上次启动阶段: " + readStartupStage(appContext)
                        + "\\nServer boot marker: " + readServerBootMarker(appContext)
                        + "\\nVirtualApp 安装/启动异常："'''
if old not in s: raise SystemExit("Runner diagnostic insertion anchor missing")
s=s.replace(old,new,1)
anchor='    private static String readServerBootMarker(Context context) {'
method='''    private static String readStartupStage(Context context) {
        if (context == null) return "context unavailable";
        File marker = new File(context.getFilesDir(), "usbtool_va_startup_stage.txt");
        if (!marker.isFile()) return "no previous stage record";
        try {
            byte[] bytes = new byte[(int) Math.min(marker.length(), 4096)];
            try (java.io.FileInputStream in = new java.io.FileInputStream(marker)) {
                int offset = 0, count;
                while (offset < bytes.length && (count = in.read(bytes, offset, bytes.length - offset)) > 0) offset += count;
                return new String(bytes, 0, offset, "UTF-8").trim();
            }
        } catch (Throwable error) {
            return "read failed: " + error.getClass().getSimpleName();
        }
    }

'''
if anchor not in s: raise SystemExit("Runner marker method anchor missing")
s=s.replace(anchor,method+anchor,1)
p.write_text(s)
PY
grep -q 'startup: InvocationStubManager.injectAll' "$CORE"
grep -q 'VirtualCore 上次启动阶段' "$RUNNER"
cat > USBTool/BUILD_AUDIT_PHASE40.txt <<'AUDIT'
USBTool Phase 40 - persistent VirtualCore startup stage breadcrumbs
- VirtualCore.startup() explicitly requires the Android main thread; moving it to a worker would violate the upstream contract.
- Persist a synchronous stage marker before each potentially blocking startup operation.
- Record ActivityThread lookup, PackageManager package lookup, IPCBus initialization, process detection, stub manager initialization/injection, and ContextFixer.
- Include the last recorded startup stage in later runtime error diagnostics.
- This is diagnostic instrumentation, not a claim that the underlying hook or Binder fault is fixed. Validate on the target Android 10 / MT8183 device.
AUDIT
echo "Phase 40 startup-stage diagnostics audit passed."
