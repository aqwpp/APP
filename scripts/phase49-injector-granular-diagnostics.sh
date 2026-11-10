#!/usr/bin/env bash
set -euo pipefail
FILE="USBTool/va-lib/src/main/java/com/lody/virtual/client/core/InvocationStubManager.java"
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
test -s "$FILE"
test -s "$RUNNER"
python3 - <<'PY'
from pathlib import Path
p = Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/core/InvocationStubManager.java")
s = p.read_text()
if "writeUSBToolInjectorStage(" not in s:
    marker = "\tvoid injectAll() throws Throwable {\n"
    helper = r'''    private static void writeUSBToolInjectorStage(String injector, String stage, Throwable error) {
        try {
            android.content.Context context = VirtualCore.get().getContext();
            if (context == null) return;
            String process = android.app.Application.getProcessName();
            StringBuilder line = new StringBuilder();
            line.append("pid=").append(android.os.Process.myPid())
                    .append(" process=").append(process)
                    .append(" time=").append(System.currentTimeMillis())
                    .append(" injector=").append(injector)
                    .append(" stage=").append(stage).append("\n");
            if (error != null) {
                java.io.StringWriter trace = new java.io.StringWriter();
                error.printStackTrace(new java.io.PrintWriter(trace));
                line.append(trace).append("\n");
                android.util.Log.e("USBToolInjector", line.toString(), error);
            } else {
                android.util.Log.i("USBToolInjector", line.toString());
            }
            java.io.File marker = new java.io.File(context.getFilesDir(),
                    "usbtool_va_injector_stage.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(marker, true)) {
                out.write(line.toString().getBytes("UTF-8"));
                out.flush();
                out.getFD().sync();
            }
        } catch (Throwable ignored) {
            // Diagnostics must never replace or mask the original injector failure.
        }
    }

'''
    if marker not in s:
        raise SystemExit("injectAll method anchor missing")
    s = s.replace(marker, helper + marker, 1)
    old = '''\tvoid injectAll() throws Throwable {
\t\tfor (IInjector injector : mInjectors.values()) {
\t\t\tinjector.inject();
\t\t}
\t\t// XXX: Lazy inject the Instrumentation,
\t\taddInjector(AppInstrumentation.getDefault());
\t}
'''
    new = '''\tvoid injectAll() throws Throwable {
        writeUSBToolInjectorStage("<manager>", "injectAll begin count=" + mInjectors.size(), null);
        int index = 0;
        for (IInjector injector : mInjectors.values()) {
            String name = injector == null ? "<null>" : injector.getClass().getName();
            writeUSBToolInjectorStage(name, "before index=" + index, null);
            try {
                if (injector == null) throw new IllegalStateException("Null IInjector at index " + index);
                injector.inject();
                writeUSBToolInjectorStage(name, "complete index=" + index, null);
            } catch (Throwable error) {
                writeUSBToolInjectorStage(name, "FAILED index=" + index, error);
                throw error;
            }
            index++;
        }
        writeUSBToolInjectorStage(AppInstrumentation.class.getName(), "register lazy instrumentation", null);
        try {
            // XXX: Lazy inject the Instrumentation,
            addInjector(AppInstrumentation.getDefault());
            writeUSBToolInjectorStage(AppInstrumentation.class.getName(), "registered", null);
        } catch (Throwable error) {
            writeUSBToolInjectorStage(AppInstrumentation.class.getName(), "FAILED during registration", error);
            throw error;
        }
        writeUSBToolInjectorStage("<manager>", "injectAll complete", null);
    }
'''
    if old not in s:
        raise SystemExit("injectAll original body not found")
    s = s.replace(old, new, 1)
p.write_text(s)

p = Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s = p.read_text()
needle = '''                        + "\\nProvider 调用阶段: " + readDiagnosticTail(appContext, "usbtool_va_provider_stage.txt", 8192)
'''
replacement = '''                        + "\\nHook 注入逐项记录: " + readDiagnosticTail(appContext, "usbtool_va_injector_stage.txt", 16384)
                        + "\\nProvider 调用阶段: " + readDiagnosticTail(appContext, "usbtool_va_provider_stage.txt", 8192)
'''
if "Hook 注入逐项记录:" not in s:
    if needle not in s:
        raise SystemExit("runner provider diagnostic insertion anchor missing")
    s = s.replace(needle, replacement, 1)
p.write_text(s)
PY
cat > USBTool/BUILD_AUDIT_PHASE49.txt <<'AUDIT'
USBTool Phase 49 - per-injector startup diagnostics
- The previously persisted VirtualCore stage only identified InvocationStubManager.injectAll as a whole; it could not identify which Binder/framework hook failed.
- Record the class name, index, PID, process name, timestamp, and before/complete/failure state for each IInjector.
- Persist the original Throwable stack trace and rethrow it unchanged so diagnostics do not turn a failed hook into a false success.
- Include the last 16 KiB of the injector trace in the existing install/launch diagnostic report.
- This is diagnostic instrumentation only. It does not skip hooks, suppress exceptions, change Android security boundaries, or claim that guest Activity launch works.
- Validation required: cloud Android Gradle build and a fresh on-device reproduction on Android 10 / MT8183. The exact failing injector should be the last entry marked FAILED, or the last BEFORE entry if the process is killed during injection.
AUDIT

grep -q 'writeUSBToolInjectorStage(name, "before index="' "$FILE"
grep -q 'writeUSBToolInjectorStage(name, "FAILED index="' "$FILE"
grep -q 'Hook 注入逐项记录:' "$RUNNER"
echo 'Phase 49 patch applied.'
