#!/usr/bin/env bash
set -euo pipefail
APP="USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java"
PROVIDER="USBTool/va-lib/src/main/java/com/lody/virtual/client/stub/StubContentProvider.java"
COMPAT="USBTool/va-lib/src/main/java/com/lody/virtual/helper/compat/ContentProviderCompat.java"
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
for f in "$APP" "$PROVIDER" "$COMPAT" "$RUNNER"; do test -s "$f"; done
python3 - <<'PY'
from pathlib import Path

def replace_once(path, old, new, label):
    p=Path(path); s=p.read_text()
    if new.strip() in s: return
    if old not in s: raise SystemExit("Missing Phase 43 anchor: "+label)
    p.write_text(s.replace(old,new,1))

# Record process-local Application startup and wake any provider waiter if startup throws.
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java")
s=p.read_text()
if "writeUSBToolProcessStage" not in s:
    anchor='    private static boolean isLauncherProcess(Context context) {'
    helper=r'''    private static void writeUSBToolProcessStage(Context context, String stage) {
        try {
            String process = Application.getProcessName();
            java.io.File file = new java.io.File(context.getFilesDir(), "usbtool_va_process_startup.txt");
            String line = "pid=" + android.os.Process.myPid() + " process=" + process + " stage=" + stage + "\\n";
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file, true)) {
                out.write(line.getBytes("UTF-8")); out.flush(); out.getFD().sync();
            }
            java.io.File perProcess = new java.io.File(context.getFilesDir(),
                    "usbtool_va_process_" + android.os.Process.myPid() + "_startup.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(perProcess, false)) {
                out.write(line.getBytes("UTF-8")); out.flush(); out.getFD().sync();
            }
        } catch (Throwable ignored) {}
    }

'''
    if anchor not in s: raise SystemExit("Application helper anchor missing")
    s=s.replace(anchor,helper+anchor,1)
    s=s.replace('''        if (isLauncherProcess(base)) {
            Log.i(TAG, "Skipping synchronous VirtualCore startup in launcher process");
            return;
        }
        try {
            VirtualCore core = VirtualCore.get();''','''        if (isLauncherProcess(base)) {
            writeUSBToolProcessStage(base, "launcher startup skipped");
            Log.i(TAG, "Skipping synchronous VirtualCore startup in launcher process");
            return;
        }
        writeUSBToolProcessStage(base, "attachBaseContext entered");
        try {
            VirtualCore core = VirtualCore.get();''',1)
    s=s.replace('''                core.startup(base);
            }
        } catch (Throwable error) {
            startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
            Log.e(TAG, "VirtualCore startup failed before provider initialization", error);
        }''','''                core.startup(base);
            }
            writeUSBToolProcessStage(base, "VirtualCore.startup returned isStartup=" + core.isStartup());
        } catch (Throwable error) {
            startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
            writeUSBToolProcessStage(base, "STARTUP FAILED " + startupFailure);
            try {
                android.os.ConditionVariable lock = VirtualCore.get().getInitLock();
                if (lock != null) lock.open();
            } catch (Throwable ignored) {}
            Log.e(TAG, "VirtualCore startup failed before provider initialization", error);
        }''',1)
    s=s.replace('''        if (isLauncherProcess(this)) return;
        if (VirtualCore.get().isStartup()) {''','''        if (isLauncherProcess(this)) return;
        writeUSBToolProcessStage(this, "Application.onCreate entered");
        if (VirtualCore.get().isStartup()) {''',1)
    s=s.replace('''                VirtualCore.get().initialize(new VirtualCore.VirtualInitializer() {});
            } catch (Throwable error) {
                startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
                Log.e(TAG, "VirtualCore process initialization failed", error);
            }
        }
    }''','''                VirtualCore.get().initialize(new VirtualCore.VirtualInitializer() {});
                writeUSBToolProcessStage(this, "VirtualCore.initialize returned");
            } catch (Throwable error) {
                startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());
                writeUSBToolProcessStage(this, "INITIALIZE FAILED " + startupFailure);
                Log.e(TAG, "VirtualCore process initialization failed", error);
            }
        } else {
            writeUSBToolProcessStage(this, "Application.onCreate: VirtualCore not started");
        }
    }''',1)
    p.write_text(s)

# Bound StubContentProvider's initialization wait. The previous unbounded block could
# leave ContentProviderClient.call() stuck forever if Application startup failed.
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/stub/StubContentProvider.java")
s=p.read_text()
if "writeUSBToolProviderStage" not in s:
    anchor='''public class StubContentProvider extends ContentProvider {

'''
    helper=r'''public class StubContentProvider extends ContentProvider {

    private void writeUSBToolProviderStage(String stage) {
        try {
            Context context = getContext();
            if (context == null) return;
            java.io.File file = new java.io.File(context.getFilesDir(), "usbtool_va_provider_stage.txt");
            String line = "pid=" + Process.myPid() + " process=" + android.app.Application.getProcessName()
                    + " stage=" + stage + "\\n";
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file, true)) {
                out.write(line.getBytes("UTF-8")); out.flush(); out.getFD().sync();
            }
        } catch (Throwable ignored) {}
    }

'''
    if anchor not in s: raise SystemExit("StubContentProvider class anchor missing")
    s=s.replace(anchor,helper,1)
    s=s.replace('''    public boolean onCreate() {
        return true;
    }''','''    public boolean onCreate() {
        writeUSBToolProviderStage("onCreate");
        return true;
    }''',1)
    s=s.replace('''    public Bundle call(String method, String arg, Bundle extras) {
        if ("_VA_|_init_process_".equals(method)) {
            return initProcess(extras);
        }
        return null;
    }''','''    public Bundle call(String method, String arg, Bundle extras) {
        writeUSBToolProviderStage("call begin method=" + method);
        if ("_VA_|_init_process_".equals(method)) {
            try {
                Bundle result = initProcess(extras);
                writeUSBToolProviderStage("call returned init_process");
                return result;
            } catch (Throwable error) {
                writeUSBToolProviderStage("call failed " + error.getClass().getName() + ": " + error.getMessage());
                if (error instanceof RuntimeException) throw (RuntimeException) error;
                if (error instanceof Error) throw (Error) error;
                throw new IllegalStateException(error);
            }
        }
        writeUSBToolProviderStage("call ignored method=" + method);
        return null;
    }''',1)
    s=s.replace('''        ConditionVariable lock = VirtualCore.get().getInitLock();
        if (lock != null) {
            lock.block();
        }
        IBinder token''','''        writeUSBToolProviderStage("initProcess entered");
        ConditionVariable lock = VirtualCore.get().getInitLock();
        if (lock != null) {
            writeUSBToolProviderStage("before initLock.block timeout=12000");
            boolean ready = lock.block(12000);
            writeUSBToolProviderStage("after initLock.block ready=" + ready);
            if (!ready) {
                throw new IllegalStateException("VirtualCore startup did not finish within 12 seconds in stub process "
                        + android.app.Application.getProcessName());
            }
        } else {
            writeUSBToolProviderStage("initLock already released");
        }
        IBinder token''',1)
    s=s.replace('''        VClientImpl client = VClientImpl.get();
        client.initProcess(token, vuid);
        Bundle res''','''        VClientImpl client = VClientImpl.get();
        writeUSBToolProviderStage("before VClientImpl.initProcess");
        client.initProcess(token, vuid);
        writeUSBToolProviderStage("after VClientImpl.initProcess");
        Bundle res''',1)
    p.write_text(s)

# Fail clearly instead of dereferencing a null ContentProviderClient.
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/helper/compat/ContentProviderCompat.java")
s=p.read_text()
s=s.replace('''        ContentProviderClient client = crazyAcquireContentProvider(context, uri);
        Bundle res = null;
        try {
            res = client.call(method, arg, extras);''','''        ContentProviderClient client = crazyAcquireContentProvider(context, uri);
        if (client == null) {
            throw new IllegalStateException("Unable to acquire ContentProviderClient for " + uri);
        }
        Bundle res = null;
        try {
            res = client.call(method, arg, extras);''',1)
p.write_text(s)

# Include provider/process startup trails in the copyable on-device report.
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
s=s.replace(r'''                        + "\\nActivity 启动子阶段: " + readActivityStage(appContext)
                        + "\\nServer boot marker: " + readServerBootMarker(appContext)''',r'''                        + "\\nActivity 启动子阶段: " + readActivityStage(appContext)
                        + "\\nProvider 调用阶段: " + readDiagnosticTail(appContext, "usbtool_va_provider_stage.txt", 8192)
                        + "\\n各进程启动记录: " + readDiagnosticTail(appContext, "usbtool_va_process_startup.txt", 8192)
                        + "\\nServer boot marker: " + readServerBootMarker(appContext)''',1)
if "readDiagnosticTail(Context context" not in s:
    anchor='''    private static String readServerBootMarker(Context context) {'''
    method='''    private static String readDiagnosticTail(Context context, String name, int maxBytes) {
        if (context == null) return "context unavailable";
        File marker = new File(context.getFilesDir(), name);
        if (!marker.isFile()) return "no record";
        try {
            long length = marker.length();
            int count = (int) Math.min(length, maxBytes);
            byte[] bytes = new byte[count];
            try (java.io.RandomAccessFile in = new java.io.RandomAccessFile(marker, "r")) {
                in.seek(Math.max(0, length - count));
                in.readFully(bytes);
            }
            return new String(bytes, "UTF-8").trim();
        } catch (Throwable error) {
            return "read failed: " + error.getClass().getSimpleName();
        }
    }

'''
    if anchor not in s: raise SystemExit("Runner diagnostic-tail anchor missing")
    s=s.replace(anchor,method+anchor,1)
p.write_text(s)
PY
grep -q 'lock.block(12000)' "$PROVIDER"
grep -q 'Provider 调用阶段:' "$RUNNER"
grep -q 'Unable to acquire ContentProviderClient' "$COMPAT"
cat > USBTool/BUILD_AUDIT_PHASE43.txt <<'AUDIT'
USBTool Phase 43 - bounded stub-provider initialization and process diagnostics
- Record per-process Application attachBaseContext/onCreate startup stages with PID and process name.
- On VirtualCore startup failure, persist the exception and open the init ConditionVariable so stub-provider callers are not left blocked forever.
- Bound StubContentProvider's init ConditionVariable wait to 12 seconds and record provider onCreate/call/initProcess boundaries.
- Fail clearly if Android cannot acquire the stub ContentProviderClient.
- Include provider call and per-process startup traces in the copyable runtime diagnostic report.
- This phase prevents an unbounded provider startup wait and adds evidence; it does not claim arbitrary guest APK execution is fixed.
AUDIT
echo "Phase 43 provider deadlock guard and diagnostics source checks passed."
