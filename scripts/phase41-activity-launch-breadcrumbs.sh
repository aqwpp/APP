#!/usr/bin/env bash
set -euo pipefail
RUNNER="USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java"
VAM="USBTool/va-lib/src/main/java/com/lody/virtual/client/ipc/VActivityManager.java"
STACK="USBTool/va-lib/src/main/java/com/lody/virtual/server/am/ActivityStack.java"
SERVICE="USBTool/va-lib/src/main/java/com/lody/virtual/server/am/VActivityManagerService.java"
for f in "$RUNNER" "$VAM" "$STACK" "$SERVICE"; do test -s "$f"; done
python3 - <<'PY'
from pathlib import Path

def patch(path, old, new, label):
    p=Path(path); s=p.read_text()
    if new.strip() in s: return
    if old not in s: raise SystemExit("Missing patch anchor: "+label)
    p.write_text(s.replace(old,new,1))

# Client-side split: determine whether package resolution or the remote service call blocks.
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/client/ipc/VActivityManager.java")
s=p.read_text()
if "usbtool_va_activity_stage.txt" not in s:
    helper='''    private static void writeUSBToolActivityStage(String stage) {
        try {
            java.io.File file = new java.io.File(VirtualCore.get().getContext().getFilesDir(), "usbtool_va_activity_stage.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file, false)) {
                out.write((stage + "\\n").getBytes("UTF-8")); out.flush(); out.getFD().sync();
            }
        } catch (Throwable ignored) {}
    }

'''
    anchor='    public static VActivityManager get() {'
    if anchor not in s: raise SystemExit("VActivityManager helper anchor missing")
    s=s.replace(anchor,helper+anchor,1)
    old='''        ActivityInfo info = VirtualCore.get().resolveActivityInfo(intent, userId);
        if (info == null) {
            return ActivityManagerCompat.START_INTENT_NOT_RESOLVED;
        }
        return startActivity(intent, info, null, null, null, 0, userId);'''
    new='''        writeUSBToolActivityStage("client: resolveActivityInfo begin");
        ActivityInfo info = VirtualCore.get().resolveActivityInfo(intent, userId);
        writeUSBToolActivityStage("client: resolveActivityInfo returned " + (info != null));
        if (info == null) {
            return ActivityManagerCompat.START_INTENT_NOT_RESOLVED;
        }
        writeUSBToolActivityStage("client: remote startActivity begin");
        int result = startActivity(intent, info, null, null, null, 0, userId);
        writeUSBToolActivityStage("client: remote startActivity returned " + result);
        return result;'''
    if old not in s: raise SystemExit("VActivityManager startActivity anchor missing")
    s=s.replace(old,new,1); p.write_text(s)

# Server ActivityStack breadcrumbs.
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/server/am/ActivityStack.java")
s=p.read_text()
if "usbtool_va_activity_stage.txt" not in s:
    helper='''    private void writeUSBToolActivityStage(String stage) {
        try {
            java.io.File file = new java.io.File(VirtualCore.get().getContext().getFilesDir(), "usbtool_va_activity_stage.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file, false)) {
                out.write(("server: " + stage + "\\n").getBytes("UTF-8")); out.flush(); out.getFD().sync();
            }
        } catch (Throwable ignored) {}
    }

'''
    anchor='    int startActivityLocked(int userId, Intent intent, ActivityInfo info, IBinder resultTo, Bundle options,'
    if anchor not in s: raise SystemExit("ActivityStack start anchor missing")
    s=s.replace(anchor,helper+anchor,1)
    s=s.replace('''        optimizeTasksLocked();

        Intent destIntent;''','''        writeUSBToolActivityStage("startActivityLocked entered");
        optimizeTasksLocked();
        writeUSBToolActivityStage("after optimizeTasksLocked");

        Intent destIntent;''',1)
    s=s.replace('''        if (reuseTask == null) {
            startActivityInNewTaskLocked(userId, intent, info, options);''','''        if (reuseTask == null) {
            writeUSBToolActivityStage("before startActivityInNewTaskLocked");
            startActivityInNewTaskLocked(userId, intent, info, options);
            writeUSBToolActivityStage("after startActivityInNewTaskLocked");''',1)
    s=s.replace('''    private void startActivityInNewTaskLocked(int userId, Intent intent, ActivityInfo info, Bundle options) {
        Intent destIntent = startActivityProcess(userId, null, intent, info);''','''    private void startActivityInNewTaskLocked(int userId, Intent intent, ActivityInfo info, Bundle options) {
        writeUSBToolActivityStage("startActivityInNewTaskLocked: before startActivityProcess");
        Intent destIntent = startActivityProcess(userId, null, intent, info);
        writeUSBToolActivityStage("startActivityInNewTaskLocked: after startActivityProcess dest=" + (destIntent != null));''',1)
    s=s.replace('''                VirtualCore.get().getContext().startActivity(destIntent, options);''','''                writeUSBToolActivityStage("before host Context.startActivity");
                VirtualCore.get().getContext().startActivity(destIntent, options);
                writeUSBToolActivityStage("after host Context.startActivity");''',1)
    s=s.replace('''    private Intent startActivityProcess(int userId, ActivityRecord sourceRecord, Intent intent, ActivityInfo info) {
        intent = new Intent(intent);
        ProcessRecord targetApp = mService.startProcessIfNeedLocked(info.processName, userId, info.packageName);''','''    private Intent startActivityProcess(int userId, ActivityRecord sourceRecord, Intent intent, ActivityInfo info) {
        writeUSBToolActivityStage("startActivityProcess: before startProcessIfNeedLocked");
        intent = new Intent(intent);
        ProcessRecord targetApp = mService.startProcessIfNeedLocked(info.processName, userId, info.packageName);
        writeUSBToolActivityStage("startActivityProcess: after startProcessIfNeedLocked target=" + (targetApp != null));''',1)
    p.write_text(s)

# VActivityManagerService breadcrumbs around virtual process startup and its blocking ProviderCall.
p=Path("USBTool/va-lib/src/main/java/com/lody/virtual/server/am/VActivityManagerService.java")
s=p.read_text()
if "usbtool_va_activity_stage.txt" not in s:
    helper='''    private void writeUSBToolActivityStage(String stage) {
        try {
            java.io.File file = new java.io.File(VirtualCore.get().getContext().getFilesDir(), "usbtool_va_activity_stage.txt");
            try (java.io.FileOutputStream out = new java.io.FileOutputStream(file, false)) {
                out.write(("process: " + stage + "\\n").getBytes("UTF-8")); out.flush(); out.getFD().sync();
            }
        } catch (Throwable ignored) {}
    }

'''
    anchor='    ProcessRecord startProcessIfNeedLocked(String processName, int userId, String packageName) {'
    if anchor not in s: raise SystemExit("VAMS startProcess anchor missing")
    s=s.replace(anchor,helper+anchor,1)
    s=s.replace('''    ProcessRecord startProcessIfNeedLocked(String processName, int userId, String packageName) {
        if (VActivityManagerService.get().getFreeStubCount() < 3) {''','''    ProcessRecord startProcessIfNeedLocked(String processName, int userId, String packageName) {
        writeUSBToolActivityStage("startProcessIfNeedLocked entered: " + processName);
        if (VActivityManagerService.get().getFreeStubCount() < 3) {''',1)
    s=s.replace('''        app = performStartProcessLocked(uid, vpid, info, processName);
        if (app != null) {''','''        writeUSBToolActivityStage("before performStartProcessLocked vpid=" + vpid);
        app = performStartProcessLocked(uid, vpid, info, processName);
        writeUSBToolActivityStage("after performStartProcessLocked app=" + (app != null));
        if (app != null) {''',1)
    s=s.replace('''        Bundle res = ProviderCall.call(VASettings.getStubAuthority(vpid), "_VA_|_init_process_", null, extras);
        if (res == null) {''','''        writeUSBToolActivityStage("performStartProcessLocked: before ProviderCall.call authority=" + VASettings.getStubAuthority(vpid));
        Bundle res = ProviderCall.call(VASettings.getStubAuthority(vpid), "_VA_|_init_process_", null, extras);
        writeUSBToolActivityStage("performStartProcessLocked: after ProviderCall.call result=" + (res != null));
        if (res == null) {''',1)
    s=s.replace('''        attachClient(pid, clientBinder);
        return app;''','''        writeUSBToolActivityStage("performStartProcessLocked: before attachClient pid=" + pid);
        attachClient(pid, clientBinder);
        writeUSBToolActivityStage("performStartProcessLocked: after attachClient");
        return app;''',1)
    p.write_text(s)

# Include the last substage in the on-device failure report.
p=Path("USBTool/app/src/main/java/com/ssai/usbtool/runtime/virtualapp/VirtualAppPackageRunner.java")
s=p.read_text()
old='''                result = "VirtualCore 上次启动阶段: " + readStartupStage(appContext)
                        + "\\nServer boot marker: " + readServerBootMarker(appContext)'''
new='''                result = "VirtualCore 上次启动阶段: " + readStartupStage(appContext)
                        + "\\nActivity 启动子阶段: " + readActivityStage(appContext)
                        + "\\nServer boot marker: " + readServerBootMarker(appContext)'''
if "Activity 启动子阶段:" not in s:
    if old not in s: raise SystemExit("Runner diagnostics anchor missing")
    s=s.replace(old,new,1)
    anchor='    private static String readServerBootMarker(Context context) {'
    method='''    private static String readActivityStage(Context context) {
        if (context == null) return "context unavailable";
        File marker = new File(context.getFilesDir(), "usbtool_va_activity_stage.txt");
        if (!marker.isFile()) return "no activity-stage record";
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
    if anchor not in s: raise SystemExit("Runner read method anchor missing")
    s=s.replace(anchor,method+anchor,1)
    p.write_text(s)

PY
grep -q 'client: resolveActivityInfo begin' "$VAM"
grep -q 'before ProviderCall.call' "$SERVICE"
grep -q 'Activity 启动子阶段:' "$RUNNER"
cat > USBTool/BUILD_AUDIT_PHASE41.txt <<'AUDIT'
USBTool Phase 41 - granular VirtualApp Activity launch diagnostics
- Persist client-side ActivityInfo resolution and remote ActivityManager call boundaries.
- Persist server-side ActivityStack task optimization, virtual process allocation, stub ProviderCall, client attachment, and host Context.startActivity boundaries.
- Include the last activity-launch substage in runtime error diagnostics.
- This phase is diagnostic instrumentation. It deliberately does not increase timeouts or claim a runtime fix.
- Validate the exact blocked substage on Android 10 / MT8183 before changing process topology or launch behavior.
AUDIT
echo "Phase 41 Activity launch-stage diagnostics audit passed."
