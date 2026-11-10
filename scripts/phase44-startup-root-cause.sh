#!/usr/bin/env bash
set -euo pipefail
APP="USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java"
PROVIDER="USBTool/va-lib/src/main/java/com/lody/virtual/client/stub/StubContentProvider.java"
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
for f in "$APP" "$PROVIDER" "$RUNNER"; do test -s "$f"; done

python3 - <<'PY'
from pathlib import Path

app = Path("USBTool/app/src/main/java/com/ssai/usbtool/USBToolApplication.java")
s = app.read_text()

def replace_once(src, old, new, label):
    if new.strip() in src:
        return src
    if old not in src:
        raise SystemExit("Missing Phase 44 anchor: " + label)
    return src.replace(old, new, 1)

# Persist the complete cause chain, not just ExceptionInInitializerError's empty message.
s = replace_once(
    s,
    'startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());\n            writeUSBToolProcessStage(base, "STARTUP FAILED " + startupFailure);',
    'java.io.StringWriter trace = new java.io.StringWriter();\n            error.printStackTrace(new java.io.PrintWriter(trace));\n            startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage()) + "\\n" + trace;\n            writeUSBToolProcessStage(base, "STARTUP FAILED " + startupFailure);',
    "attachBaseContext throwable capture")
s = replace_once(
    s,
    'startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage());\n                writeUSBToolProcessStage(this, "INITIALIZE FAILED " + startupFailure);',
    'java.io.StringWriter trace = new java.io.StringWriter();\n                error.printStackTrace(new java.io.PrintWriter(trace));\n                startupFailure = error.getClass().getName() + ": " + String.valueOf(error.getMessage()) + "\\n" + trace;\n                writeUSBToolProcessStage(this, "INITIALIZE FAILED " + startupFailure);',
    "onCreate throwable capture")
app.write_text(s)

# A failed Application startup must not be reported as a successful stub init_process.
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/stub/StubContentProvider.java")
s = p.read_text()
anchor = '        IBinder token = BundleCompat.getBinder(extras,"_VA_|_binder_");'
guard = '''        // USBTool Application startup can fail before this provider is called. The
        // init ConditionVariable is opened on failure to avoid deadlock, so check
        // the recorded cause before allowing VClientImpl to report false success.
        try {
            Class<?> application = Class.forName("com.ssai.usbtool.USBToolApplication");
            Object failure = application.getMethod("getStartupFailure").invoke(null);
            if (failure != null && !String.valueOf(failure).isEmpty()) {
                throw new IllegalStateException("USBTool VirtualCore startup failed in this process: "
                        + String.valueOf(failure));
            }
        } catch (ClassNotFoundException ignored) {
            // Keep the upstream VirtualApp library usable outside USBTool.
        } catch (java.lang.reflect.InvocationTargetException error) {
            throw new IllegalStateException("Unable to read USBTool process startup failure", error.getCause());
        } catch (ReflectiveOperationException error) {
            throw new IllegalStateException("Unable to inspect USBTool process startup state", error);
        }
'''
s = replace_once(s, anchor, guard + anchor, "stub process startup failure gate")
p.write_text(s)

# Label the report with the exact diagnostic meaning so a provider failure is not
# mistaken for a successful guest process initialization.
p = Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s = p.read_text()
if "Phase 44 startup-cause diagnostics" not in s:
    s = s.replace(
        '"\\n各进程启动记录: " + readDiagnosticTail(appContext, "usbtool_va_process_startup.txt", 8192)',
        '"\\n各进程启动记录（含完整异常堆栈）: " + readDiagnosticTail(appContext, "usbtool_va_process_startup.txt", 8192)',
        1)
p.write_text(s)
PY

grep -q 'error.printStackTrace(new java.io.PrintWriter(trace))' "$APP"
grep -q 'USBTool VirtualCore startup failed in this process' "$PROVIDER"
grep -q '含完整异常堆栈' "$RUNNER"

cat > USBTool/BUILD_AUDIT_PHASE44.txt <<'AUDIT'
USBTool Phase 44 - preserve VirtualCore startup cause and reject false stub initialization
- Persist complete throwable stack traces for attachBaseContext startup and Application.onCreate initialization failures.
- Before VClientImpl.initProcess, StubContentProvider checks the current USBTool process's recorded startup failure.
- A failed VirtualCore process startup now fails the ProviderCall explicitly rather than opening the init lock and continuing as if process initialization succeeded.
- The diagnostic report labels the per-process trace as including full exception details.
- This is a diagnostic/control-flow correction; the underlying ExceptionInInitializerError must be identified from the newly captured root stack before claiming a runtime fix.
AUDIT
echo "Phase 44 startup-cause diagnostics source checks passed."
